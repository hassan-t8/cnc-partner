import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'otp_dialog.dart';
import 'worker_booking_detail_screen.dart';
import 'worker_repository.dart';

class WorkerBookingsScreen extends ConsumerStatefulWidget {
  const WorkerBookingsScreen({super.key});
  @override
  ConsumerState<WorkerBookingsScreen> createState() =>
      _WorkerBookingsScreenState();
}

class _WorkerBookingsScreenState extends ConsumerState<WorkerBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  static const _statuses = ['upcoming', 'completed', 'all'];
  late List<Future<List<Assignment>>> _futures;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _futures = _statuses.map(_load).toList();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int _acting = -1;

  Future<List<Assignment>> _load(String status) =>
      ref.read(workerRepositoryProvider).myBookings(status: status);

  Future<void> _openDetail(Assignment a) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerBookingDetailScreen(assignment: a)));
    if (mounted) _reloadAll();
  }

  Future<void> _act(Assignment a, String action) async {
    final repo = ref.read(workerRepositoryProvider);
    setState(() => _acting = a.id);
    try {
      switch (action) {
        case 'accept':
          await repo.accept(a.id);
          AppToast.success('Job accepted');
          break;
        case 'start':
          await _start(a);
          break;
        case 'complete':
          await repo.complete(a.id);
          AppToast.success('Job completed');
          break;
      }
      _reloadAll();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  Future<void> _collectCash(Assignment a) async {
    final bookingId = a.bookingId;
    if (bookingId == null) {
      AppToast.error('Missing booking reference');
      return;
    }
    setState(() => _acting = a.id);
    try {
      await ref.read(workerRepositoryProvider).cashCollect(bookingId);
      AppToast.success('Cash collected — you can complete the job now');
      _reloadAll();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  Future<void> _start(Assignment a) async {
    final repo = ref.read(workerRepositoryProvider);
    try {
      await repo.start(a.id);
      AppToast.success('Job started');
    } on ApiException catch (e) {
      if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
        if (!mounted) return;
        final otp = await showOtpDialog(context,
            bookingRef: a.bookingRef,
            customerName: a.customerName);
        if (otp == null) return;
        await repo.start(a.id, otp: otp);
        AppToast.success('Job started');
      } else {
        rethrow;
      }
    }
  }

  void _reload(int i) => _refresh(i);

  // Await-able for pull-to-refresh.
  Future<void> _refresh(int i) {
    final f = _load(_statuses[i]);
    setState(() => _futures[i] = f);
    return f;
  }

  void _reloadAll() {
    for (var i = 0; i < _statuses.length; i++) {
      _futures[i] = _load(_statuses[i]);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Refetch every tab's data when the bottom-nav tab is (re)tapped.
    ref.listen(tabRefreshProvider, (_, __) => _reloadAll());
    return Scaffold(
      appBar: MainAppBar('My bookings',
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.brand600,
          indicatorColor: AppColors.brand600,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Completed'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (var i = 0; i < 3; i++) _list(i),
        ],
      ),
    );
  }

  Widget _list(int i) {
    return RefreshIndicator(
      onRefresh: () => _refresh(i),
      child: FutureBuilder<List<Assignment>>(
        future: _futures[i],
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList();
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: 'Couldn\'t load bookings.', onRetry: () => _reload(i));
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 80),
              EmptyState(
                  icon: Icons.event_note_outlined, title: 'Nothing here yet'),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, k) => _row(rows[k]),
          );
        },
      ),
    );
  }

  Widget _row(Assignment a) {
    final busy = _acting == a.id;
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : '';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(a),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                        a.serviceName.isEmpty ? 'Service' : a.serviceName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                  StatusBadge(a.status, worker: true),
                ],
              ),
              if (a.customerName.isNotEmpty || time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [a.customerName, time].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
              if (a.fullAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(a.fullAddress,
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textFaint)),
              ],
              Row(
                children: [
                  Text('Booking ${a.bookingRef}',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textFaint)),
                  const Spacer(),
                  Text('Details',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand600)),
                  Icon(Icons.chevron_right,
                      size: 16, color: AppColors.brand600),
                ],
              ),
              ..._cardActions(a, busy),
            ],
          ),
        ),
      ),
    );
  }

  /// Inline lifecycle action(s) for the card, gated by status.
  List<Widget> _cardActions(Assignment a, bool busy) {
    Widget btn(String label, Color color, String action,
        {VoidCallback? onTap, bool enabled = true}) {
      final handler =
          (!enabled || busy) ? null : (onTap ?? () => _act(a, action));
      final showSpinner = busy && handler != null;
      return SizedBox(
        height: 42,
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            disabledBackgroundColor: color.withValues(alpha: 0.35),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          ),
          onPressed: handler,
          child: showSpinner
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white))
              : Text(label),
        ),
      );
    }

    switch (a.status) {
      case 'pending_acceptance':
        return [const SizedBox(height: 10), btn('Accept', AppColors.brand600, 'accept')];
      case 'accepted':
        return [const SizedBox(height: 10), btn('Start job', AppColors.violet, 'start')];
      case 'in_progress':
        // Cash still owed → collect before completing (backend enforces it too).
        if (a.cashPending) {
          return [
            const SizedBox(height: 10),
            _cashNote(a),
            const SizedBox(height: 8),
            btn('Collect AED ${a.cashDue.toStringAsFixed(0)}', AppColors.amber,
                'collect',
                onTap: () => _collectCash(a)),
            const SizedBox(height: 8),
            btn('Complete job', AppColors.brand600, 'complete',
                enabled: false),
          ];
        }
        return [
          const SizedBox(height: 10),
          btn('Complete job', AppColors.brand600, 'complete')
        ];
      default:
        return const [];
    }
  }

  Widget _cashNote(Assignment a) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Collect AED ${a.cashDue.toStringAsFixed(2)} cash, then mark it '
          'collected to complete.',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      );
}
