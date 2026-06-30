import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import '../worker/otp_dialog.dart';
import 'assign_team_sheet.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Full booking detail with the team-assignment flow (assign / unassign) and
/// the accept / start / complete lifecycle. Pops `true` if anything changed.
class BookingDetailScreen extends ConsumerStatefulWidget {
  final PartnerBooking booking;
  const BookingDetailScreen({super.key, required this.booking});
  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late PartnerBooking b;
  List<BookingAssignment>? _team; // null = loading
  bool _teamError = false;
  bool _busy = false; // lifecycle actions only (start / complete / cash)
  final Set<int> _removing = {}; // assignment ids being unassigned
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    b = widget.booking;
    _loadTeam();
    // Live: join this booking's room for dispatch/assignment updates.
    ref.read(bookingRealtimeProvider.notifier).joinBooking(b.id);
  }

  @override
  void dispose() {
    ref.read(bookingRealtimeProvider.notifier).leaveBooking(b.id);
    super.dispose();
  }

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  /// Re-fetch this booking (no single-booking endpoint, so pull the list and
  /// pick it out) so socket events — payment collected, completed from the web,
  /// status changes — update the header + action buttons live.
  Future<void> _reloadBooking() async {
    try {
      final list = await _repo.bookings();
      final fresh = list.where((x) => x.id == b.id);
      if (fresh.isNotEmpty && mounted) {
        final next = fresh.first;
        if (next.status != b.status ||
            next.cashCollected != b.cashCollected) {
          _changed = true;
        }
        setState(() => b = next);
      }
    } catch (_) {}
  }

  Future<void> _loadTeam() async {
    // Only show the skeleton on the FIRST load — on reloads (socket / after
    // assign-unassign) keep the current team visible so it doesn't flash a
    // loader that looks like the job is starting.
    if (_team == null) setState(() => _teamError = false);
    try {
      final list = await _repo.bookingAssignments(b.id);
      if (mounted) setState(() => _team = list);
    } catch (_) {
      if (mounted) {
        setState(() {
          _team ??= const [];
          _teamError = true;
        });
      }
    }
  }

  static const _statusForAction = {
    'accept': 'accepted',
    'decline': 'declined',
    'start': 'in_progress',
    'complete': 'completed',
  };

  // ---- lifecycle ----
  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'accept':
          await _repo.acceptBooking(b.id);
          AppToast.success('Booking accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _busy = false);
            return;
          }
          await _repo.declineBooking(b.id,
              reason: reason.isEmpty ? null : reason);
          AppToast.success('Booking declined');
          break;
        case 'start':
          try {
            await _repo.startBooking(b.id);
          } on ApiException catch (e) {
            if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
              if (!mounted) return;
              final otp = await showOtpDialog(context,
                  bookingRef: '#${b.ref}', customerName: b.customerName);
              if (otp == null) {
                setState(() => _busy = false);
                return;
              }
              await _repo.startBooking(b.id, otp: otp);
            } else {
              rethrow;
            }
          }
          AppToast.success('Booking started');
          break;
        case 'complete':
          await _repo.completeBooking(b.id);
          AppToast.success('Booking completed');
          break;
      }
      _changed = true;
      // Return the new status so the list updates optimistically.
      if (mounted) Navigator.pop(context, _statusForAction[action] ?? '');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Mark the door cash as collected. Required before completing a cash
  /// booking with money still owed (mirrors the web "Mark as collected").
  Future<void> _collectCash() async {
    setState(() => _busy = true);
    try {
      await _repo.cashCollect(b.id);
      if (!mounted) return;
      setState(() {
        b = b.copyWith(cashCollected: true);
        _busy = false;
      });
      _changed = true;
      AppToast.success('Cash collected — you can complete the job now');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _reasonDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline booking'),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason (optional)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  // ---- team ----
  Future<void> _openAssignTeam() async {
    final changed = await showAssignTeamSheet(
      context,
      ref,
      bookingId: b.id,
      ref0: b.ref,
      scheduledStart: b.scheduledStart,
      zoneId: b.zoneId,
    );
    if (changed && mounted) {
      _changed = true;
      _loadTeam();
    }
  }

  Future<void> _unassign(BookingAssignment a) async {
    setState(() => _removing.add(a.id));
    try {
      await _repo.unassign(a.id);
      AppToast.success('Removed from job');
      _changed = true;
      await _loadTeam();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _removing.remove(a.id));
    }
  }

  List<Widget> _actions() {
    Widget btn(String label, IconData icon, Color color, String action,
        {bool outlined = false, VoidCallback? onTap, bool enabled = true}) {
      final handler = (!enabled || _busy) ? null : (onTap ?? () => _act(action));
      final showSpinner = _busy && handler != null;
      return SizedBox(
        height: 46,
        child: outlined
            ? OutlinedButton.icon(
                onPressed: handler,
                icon: Icon(icon, size: 18, color: color),
                label: Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withValues(alpha: 0.5))),
              )
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  disabledBackgroundColor: color.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                ),
                onPressed: handler,
                icon: showSpinner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                    : Icon(icon, size: 18),
                label: Text(label),
              ),
      );
    }
    switch (b.status) {
      case 'awaiting_acceptance':
        return [
          btn('Accept', Icons.check_rounded, AppColors.brand600, 'accept'),
          btn('Decline', Icons.close_rounded, AppColors.rose, 'decline',
              outlined: true),
        ];
      case 'accepted':
        return [
          btn('Start job', Icons.play_arrow_rounded, AppColors.violet,
              'start'),
        ];
      case 'in_progress':
        // Cash still owed at the door → must collect before completing, like
        // the web. The Complete button stays disabled until cash is collected.
        if (b.cashPending) {
          return [
            btn('Collect AED ${b.cashDue.toStringAsFixed(0)}',
                Icons.payments_rounded, AppColors.amber, 'collect',
                onTap: _collectCash),
            btn('Complete', Icons.check_circle_rounded, AppColors.brand600,
                'complete',
                enabled: false),
          ];
        }
        return [
          btn('Complete', Icons.check_circle_rounded, AppColors.brand600,
              'complete'),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live: refresh team when this booking changes (status/dispatch/assign).
    ref.listen(bookingRealtimeProvider, (_, __) {
      final lid = ref.read(bookingRealtimeProvider.notifier).lastBookingId;
      if (mounted && (lid == null || lid == b.id)) {
        _loadTeam();
        _reloadBooking();
      }
    });
    final actions = _actions();
    final canManageTeam = b.status == 'awaiting_acceptance' ||
        b.status == 'accepted' ||
        b.status == 'in_progress';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed ? 'reload' : '');
      },
      child: Scaffold(
        appBar: MainAppBar('Booking details'),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ServiceTitle(b.serviceName, titleSize: 20)),
                const SizedBox(width: 8),
                StatusBadge(b.status),
              ],
            ),
            if (b.ref.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('#${b.ref}',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            const SizedBox(height: 16),
            _detailRow(Icons.person_outline, 'Customer',
                b.customerName.isEmpty ? '—' : b.customerName),
            _detailRow(Icons.place_outlined, 'Area',
                b.area.isEmpty ? '—' : b.area),
            _detailRow(
                Icons.schedule_outlined,
                'Scheduled',
                b.scheduledStart != null
                    ? DateFormat('EEE d MMM y · h:mm a')
                        .format(b.scheduledStart!)
                    : 'Not scheduled'),
            if (b.paymentStatus.isNotEmpty)
              _detailRow(Icons.payments_outlined, 'Payment',
                  b.paymentStatus.replaceAll('_', ' ')),
            _detailRow(Icons.account_balance_wallet_outlined, 'Your payout',
                'AED ${b.partnerCost.toStringAsFixed(2)}'),
            const SizedBox(height: 22),
            Row(
              children: [
                const Text('Team',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (canManageTeam)
                  TextButton.icon(
                    onPressed: _openAssignTeam,
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Assign'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _teamBody(canManageTeam),
            if (b.cashPending && b.status == 'in_progress') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 18, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Collect AED ${b.cashDue.toStringAsFixed(2)} in cash from '
                        'the customer, then mark it collected to complete the job.',
                        style: TextStyle(
                            fontSize: 12.5, color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _teamBody(bool canManageTeam) {
    final team = _team;
    if (team == null) {
      // A bounded placeholder — LoadingList is itself a ListView and can't be
      // nested directly inside this page's ListView (unbounded height).
      return Column(
        children: List.generate(
          2,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
          ),
        ),
      );
    }
    if (team.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.group_off_outlined,
                size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _teamError
                      ? 'Couldn\'t load the team. Pull down or reopen to retry.'
                      : canManageTeam
                          ? 'No one assigned yet. Tap Assign to add a worker.'
                          : 'No team assigned.',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
      );
    }
    // De-duplicate: the API can return the same worker+role more than once.
    final seen = <String>{};
    final unique = [
      for (final a in team)
        if (seen.add('${a.workerName.toLowerCase()}|${a.role}')) a
    ];
    return Column(
      children: [for (final a in unique) _teamRow(a, canManageTeam)],
    );
  }

  Widget _teamRow(BookingAssignment a, bool canManage) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brand50,
              child: Icon(
                  a.role == 'driver'
                      ? Icons.directions_car
                      : Icons.cleaning_services,
                  size: 16,
                  color: AppColors.brand700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.workerName.isEmpty ? 'Worker' : a.workerName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                      [a.role, if (a.status.isNotEmpty) a.status]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            if (canManage)
              _removing.contains(a.id)
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.2)),
                    )
                  : IconButton(
                      onPressed: () => _unassign(a),
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.rose),
                      tooltip: 'Remove',
                    ),
          ],
        ),
      );

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
