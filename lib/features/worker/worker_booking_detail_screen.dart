import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'booking_photos.dart';
import 'otp_dialog.dart';
import 'worker_repository.dart';

/// Full booking detail for a crew/driver assignment, with the lifecycle
/// actions (Accept / Decline / Start / Complete) and quick call/directions.
class WorkerBookingDetailScreen extends ConsumerStatefulWidget {
  final Assignment assignment;
  const WorkerBookingDetailScreen({super.key, required this.assignment});

  @override
  ConsumerState<WorkerBookingDetailScreen> createState() =>
      _WorkerBookingDetailScreenState();
}

class _WorkerBookingDetailScreenState
    extends ConsumerState<WorkerBookingDetailScreen> {
  late String _status = widget.assignment.status;
  bool _busy = false;
  late bool _cashCollected = widget.assignment.cashCollected;

  Assignment get a => widget.assignment;
  bool get _cashPending =>
      a.payment.toLowerCase() == 'cash' && a.cashDue > 0 && !_cashCollected;

  @override
  void initState() {
    super.initState();
    final bid = widget.assignment.bookingId;
    if (bid != null) {
      ref.read(bookingRealtimeProvider.notifier).joinBooking(bid);
    }
  }

  @override
  void dispose() {
    final bid = widget.assignment.bookingId;
    if (bid != null) {
      ref.read(bookingRealtimeProvider.notifier).leaveBooking(bid);
    }
    super.dispose();
  }

  /// Pull fresh state for this job so socket events (cash collected / completed
  /// from the web or another device) update the UI live.
  Future<void> _refresh() async {
    try {
      final list = await ref.read(workerRepositoryProvider).myBookings();
      final fresh = list.where((x) => x.id == a.id);
      if (fresh.isNotEmpty && mounted) {
        setState(() {
          _status = fresh.first.status;
          _cashCollected = fresh.first.cashCollected;
        });
      }
    } catch (_) {}
  }

  Future<void> _act(String action) async {
    final repo = ref.read(workerRepositoryProvider);
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'accept':
          await repo.accept(a.id);
          _status = 'accepted';
          AppToast.success('Job accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _busy = false);
            return;
          }
          await repo.decline(a.id, reason: reason.isEmpty ? null : reason);
          if (mounted) Navigator.pop(context, true);
          AppToast.success('Job declined');
          return;
        case 'start':
          await _start();
          break;
        case 'complete':
          await repo.complete(a.id);
          _status = 'completed';
          AppToast.success('Job completed');
          break;
      }
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final repo = ref.read(workerRepositoryProvider);
    try {
      await repo.start(a.id);
      _status = 'in_progress';
      AppToast.success('Job started');
    } on ApiException catch (e) {
      if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
        if (!mounted) return;
        final otp = await showOtpDialog(context,
            bookingRef: a.bookingRef,
            customerName: a.customerName);
        if (otp == null) return;
        await repo.start(a.id, otp: otp);
        _status = 'in_progress';
        AppToast.success('Job started');
      } else {
        rethrow;
      }
    }
  }

  Future<String?> _reasonDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline job'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live: refresh this job when its booking changes (payment/status).
    ref.listen(bookingRealtimeProvider, (_, __) {
      final lid = ref.read(bookingRealtimeProvider.notifier).lastBookingId;
      if (mounted && (lid == null || lid == a.bookingId)) _refresh();
    });
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM y · h:mm a').format(a.scheduledStart!)
        : 'Time to be confirmed';
    final endTime = a.scheduledEnd != null
        ? DateFormat('h:mm a').format(a.scheduledEnd!)
        : '';
    return Scaffold(
      appBar: const MainAppBar('Booking details'),
      body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Hero
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brand700, AppColors.brand500],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ServiceTitle(
                            a.serviceName,
                            titleSize: 19,
                            titleColor: Colors.white,
                            crumbColor: Colors.white.withValues(alpha: 0.8)),
                      ),
                      StatusBadge(_status, worker: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('Booking ${a.bookingRef}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _infoCard([
              _line(Icons.schedule,
                  endTime.isEmpty ? time : '$time – $endTime'),
              if (a.customerName.isNotEmpty)
                _line(Icons.person_outline, a.customerName),
              if (a.fullAddress.isNotEmpty)
                _line(Icons.place_outlined, a.fullAddress),
              if (a.role.isNotEmpty)
                _line(Icons.badge_outlined, 'Role: ${a.role}'),
              if (_status == 'completed' && a.completedAt != null)
                _line(Icons.check_circle_outline,
                    'Completed ${DateFormat('d MMM · h:mm a').format(a.completedAt!)}'),
            ]),
            const SizedBox(height: 12),
            Row(
              children: [
                if (a.fullAddress.isNotEmpty)
                  Expanded(
                    child: _ghost(Icons.directions_outlined, 'Directions',
                        () {
                      launchUrl(
                        Uri.parse(
                            'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a.fullAddress)}'),
                        mode: LaunchMode.externalApplication,
                      );
                    }),
                  ),
                if ((a.partnerPhone ?? '').isNotEmpty ||
                    (a.customerPhone ?? '').isNotEmpty) ...[
                  if (a.fullAddress.isNotEmpty) const SizedBox(width: 10),
                  Expanded(
                    child: _ghost(Icons.call_outlined, 'Call', () {
                      final phone = (a.partnerPhone ?? '').isNotEmpty
                          ? a.partnerPhone!
                          : a.customerPhone!;
                      launchUrl(Uri.parse('tel:$phone'));
                    }),
                  ),
                ],
              ],
            ),
            if (_status == 'accepted' ||
                _status == 'in_progress' ||
                _status == 'completed') ...[
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 14),
              BookingPhotos(
                key: ValueKey('photos-detail-${a.id}-$_status'),
                assignmentId: a.id,
                showAfter:
                    _status == 'in_progress' || _status == 'completed',
              ),
            ],
          ],
        ),
        bottomNavigationBar: _actionBar(),
    );
  }

  Future<void> _collectCash() async {
    final bookingId = a.bookingId;
    if (bookingId == null) {
      AppToast.error('Missing booking reference');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(workerRepositoryProvider).cashCollect(bookingId);
      if (!mounted) return;
      setState(() {
        _cashCollected = true;
        _busy = false;
      });
      AppToast.success('Cash collected — you can complete the job now');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget? _actionBar() {
    final buttons = <Widget>[];
    switch (_status) {
      case 'pending_acceptance':
        buttons.add(_primary('Accept', AppColors.brand600,
            _busy ? null : () => _act('accept')));
        buttons.add(_primary(
            'Decline', AppColors.rose, _busy ? null : () => _act('decline')));
        break;
      case 'accepted':
        buttons.add(_primary(
            'Start job', AppColors.violet, _busy ? null : () => _act('start')));
        break;
      case 'in_progress':
        // Cash still owed → collect before completing (backend enforces it).
        if (_cashPending) {
          buttons.add(_primary('Collect AED ${a.cashDue.toStringAsFixed(0)}',
              AppColors.amber, _busy ? null : _collectCash));
          buttons.add(_primary(
              'Complete job', AppColors.brand600, null)); // disabled
        } else {
          buttons.add(_primary('Complete job', AppColors.brand600,
              _busy ? null : () => _act('complete')));
        }
        break;
    }
    if (buttons.isEmpty) return null;
    final row = Row(
      children: [
        for (var i = 0; i < buttons.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: buttons[i]),
        ],
      ],
    );
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: (_status == 'in_progress' && _cashPending)
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.amber.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Collect AED ${a.cashDue.toStringAsFixed(2)} cash, then mark '
                    'it collected to complete.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
                const SizedBox(height: 8),
                row,
              ],
            )
          : row,
    );
  }

  Widget _primary(String label, Color color, VoidCallback? onTap) => SizedBox(
        height: 50,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: onTap,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white))
              : Text(label),
        ),
      );

  Widget _ghost(IconData icon, String label, VoidCallback onTap) => SizedBox(
        height: 44,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      );

  Widget _infoCard(List<Widget> rows) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: rows),
      );

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.brand600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
