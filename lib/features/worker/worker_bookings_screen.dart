import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/booking_ref_chip.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'crew_sync.dart';
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
  // Cached rows per tab (null = first load). Keeping data across refreshes
  // means pull-to-refresh updates in place instead of flashing a loader.
  final List<List<Assignment>?> _data = [null, null, null];
  final List<bool> _err = [false, false, false];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    for (var i = 0; i < _statuses.length; i++) {
      _fetchInto(i);
    }
  }

  Future<void> _fetchInto(int i) async {
    try {
      final rows = await _load(_statuses[i]);
      if (mounted) setState(() {
            _data[i] = rows;
            _err[i] = false;
          });
    } catch (_) {
      if (mounted) setState(() => _err[i] = true);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  int _acting = -1;

  Future<List<Assignment>> _load(String status) =>
      ref.read(workerRepositoryProvider).myBookings(status: status);

  /// This job is view-only when the assignment is a driver role OR the signed-in
  /// user is a driver (and not also crew) — drivers only transport, they don't
  /// start/complete/upload photos.
  bool _isDriverView(Assignment a) {
    if (a.isDriverRole) return true;
    final u = ref.read(authControllerProvider).user;
    return u != null && u.isDriver && !u.isCrew;
  }

  /// Only the team LEAD may start the job, collect cash or complete it. Drivers
  /// and non-lead crew members see the job read-only.
  bool _viewOnly(Assignment a) => _isDriverView(a) || !a.isLead;

  String _viewOnlyNote(Assignment a) => _isDriverView(a)
      ? 'View only — the crew or partner starts this job.'
      : 'View only — only the team lead can start or complete this job.';

  Future<void> _openDetail(Assignment a) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerBookingDetailScreen(assignment: a)));
    // Refetch only the visible tab (in place, no skeleton) — the detail screen
    // may have changed this booking's status.
    if (mounted) _refresh(_tabs.index);
  }

  Future<void> _act(Assignment a, String action) async {
    final repo = ref.read(workerRepositoryProvider);
    setState(() => _acting = a.id);
    try {
      String? newStatus;
      switch (action) {
        case 'accept':
          await repo.accept(a.id);
          AppToast.success('Job accepted');
          newStatus = 'accepted';
          break;
        case 'start':
          if (!await _start(a)) return; // cancelled — nothing changed
          newStatus = 'in_progress';
          break;
        case 'complete':
          await repo.complete(a.id);
          AppToast.success('Job completed');
          newStatus = 'completed';
          break;
      }
      // Write to the shared crew store — overlaid at render across every crew
      // screen, so the change is consistent and survives a refetch. The tab
      // filter drops a completed job out of "Upcoming".
      if (newStatus != null) {
        ref
            .read(crewOverridesProvider.notifier)
            .patch(a.bookingId, status: newStatus);
      }
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
      ref
          .read(crewOverridesProvider.notifier)
          .patch(a.bookingId, cashCollected: true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  /// Returns true if the job actually started (false if the crew cancelled the
  /// OTP dialog), so the caller only patches the row on real success.
  Future<bool> _start(Assignment a) async {
    final repo = ref.read(workerRepositoryProvider);
    try {
      await repo.start(a.id);
      AppToast.success('Job started');
      return true;
    } on ApiException catch (e) {
      if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
        if (!mounted) return false;
        // The dialog validates the code itself and stays OPEN on a wrong code;
        // it only returns (non-null) once the start succeeds.
        final otp = await showOtpDialog(
          context,
          bookingRef: a.bookingRef,
          customerName: a.customerName,
          onSubmit: (code) async {
            try {
              await repo.start(a.id, otp: code);
              return null; // success → dialog closes
            } on ApiException catch (err) {
              return err.message; // wrong code → stay open, show message
            }
          },
        );
        if (otp == null) return false;
        AppToast.success('Job started');
        return true;
      }
      rethrow;
    }
  }

  /// Whether a booking with [status] should appear under tab [t].
  bool _belongsInTab(int t, String status) {
    switch (_statuses[t]) {
      case 'completed':
        return status == 'completed';
      case 'all':
        return true;
      default: // 'upcoming' — everything still live
        return status != 'completed' &&
            status != 'cancelled' &&
            status != 'declined';
    }
  }

  void _reload(int i) => _fetchInto(i);

  // Await-able for pull-to-refresh — keeps the current rows visible while it
  // fetches, then updates in place.
  Future<void> _refresh(int i) => _fetchInto(i);

  void _reloadAll() {
    for (var i = 0; i < _statuses.length; i++) {
      _fetchInto(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refetch every tab's data when the bottom-nav tab is (re)tapped.
    ref.listen(tabRefreshProvider, (_, __) => _reloadAll());
    // Rebuild when any crew screen changes a booking (shared store).
    ref.watch(crewOverridesProvider);
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
    final base = _data[i];
    // Overlay shared crew patches, then keep only rows that still belong in
    // this tab (a completed job leaves "Upcoming", etc.).
    final ov = ref.read(crewOverridesProvider.notifier);
    final rows = base == null
        ? null
        : [
            for (final a in base.map(ov.apply))
              if (_belongsInTab(i, a.status)) a
          ];
    Widget child;
    if (rows == null) {
      // First load (no cached data yet).
      child = _err[i]
          ? ListView(children: [
              const SizedBox(height: 80),
              ErrorRetry(
                  message: 'Couldn\'t load bookings.',
                  onRetry: () => _reload(i)),
            ])
          : const LoadingList();
    } else if (rows.isEmpty) {
      child = ListView(children: const [
        SizedBox(height: 80),
        EmptyState(icon: Icons.event_note_outlined, title: 'Nothing here yet'),
      ]);
    } else {
      child = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, k) => _row(rows[k]),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _refresh(i),
      // Always scrollable so pull-to-refresh works even when empty/loading.
      child: child is ListView
          ? child
          : ListView(children: [
              SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: child),
            ]),
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
                    child: ServiceTitle(a.serviceName, titleSize: 14.5),
                  ),
                  StatusBadge(a.status, worker: true),
                ],
              ),
              // Booking reference (CNC-B-xxxx) — easy to identify the booking.
              const SizedBox(height: 4),
              BookingRefChip(a.bookingRef),
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

    // Drivers and non-lead crew don't run the job — only the team lead can
    // start it, collect cash or complete it.
    if (_viewOnly(a) && (a.status == 'accepted' || a.status == 'in_progress')) {
      return [
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.visibility_outlined,
                size: 15, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_viewOnlyNote(a),
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          ],
        ),
      ];
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
