import 'dart:async';

import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/booking_ref_chip.dart';
import '../../widgets/reason_dialog.dart';
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

  // Captured once while `ref` is valid so dispose() never touches `ref`.
  BookingRealtime? _rt;
  Timer? _rtDebounce;

  @override
  void initState() {
    super.initState();
    _rt = ref.read(bookingRealtimeProvider.notifier);
    _tabs = TabController(length: 3, vsync: this);
    for (var i = 0; i < _statuses.length; i++) {
      _fetchInto(i);
    }
  }

  Future<void> _fetchInto(int i) async {
    try {
      final rows = await _load(_statuses[i]);
      if (mounted) {
        setState(() {
          _data[i] = rows;
          _err[i] = false;
        });
        _syncRooms();
      }
    } catch (_) {
      if (mounted) setState(() => _err[i] = true);
    }
  }

  /// Subscribe to a `booking_<id>` room for every booking across all tabs. The
  /// backend has no worker room, so per-booking rooms are the only way this
  /// screen hears about changes made from the web, the partner, or elsewhere.
  void _syncRooms() => _rt?.syncBookingRooms(
      this,
      _data
          .whereType<List<Assignment>>()
          .expand((rows) => rows)
          .map((a) => a.bookingId)
          .whereType<int>());

  /// A booking we're watching changed elsewhere — refetch every tab, because a
  /// status change can move a row between Upcoming and Completed.
  void _onRealtime() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _reloadAll();
    });
  }

  @override
  void dispose() {
    _rtDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _rt?.releaseBookingRooms(this);
    _tabs.dispose();
    super.dispose();
  }

  int _acting = -1;

  // Client-side search + date-range + pagination — mirrors the web
  // WorkerBookings page (the backend only filters by status). Shared across
  // all three tabs, like the web.
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _q = '';
  String _range = ''; // '' | this_week | last_week | this_month | ... | custom
  DateTime? _from;
  DateTime? _to;
  int _visible = 10;

  ({DateTime from, DateTime to})? _rangeFor(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case 'this_week':
      case 'last_week':
        final monday = today.subtract(Duration(
            days: (today.weekday - 1) + (preset == 'last_week' ? 7 : 0)));
        return (from: monday, to: monday.add(const Duration(days: 6)));
      case 'this_month':
      case 'last_month':
        final delta = preset == 'last_month' ? -1 : 0;
        return (
          from: DateTime(now.year, now.month + delta, 1),
          to: DateTime(now.year, now.month + delta + 1, 0),
        );
      case 'this_year':
        return (from: DateTime(now.year, 1, 1), to: DateTime(now.year, 12, 31));
      default:
        return null;
    }
  }

  /// A row passes the (client-side) search + date filters.
  bool _matchesFilters(Assignment a) {
    if (_q.isNotEmpty) {
      final needle = _q.toLowerCase();
      if (!a.bookingCode.toLowerCase().contains(needle) &&
          !(a.bookingId?.toString() ?? '').contains(needle) &&
          !a.id.toString().contains(needle)) {
        return false;
      }
    }
    if (_from != null || _to != null) {
      final d = a.scheduledStart;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      if (_from != null && day.isBefore(_from!)) return false;
      if (_to != null && day.isAfter(_to!)) return false;
    }
    return true;
  }

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() {
        _q = v.trim();
        _visible = 10;
      });
    });
  }

  Future<void> _setRange(String preset) async {
    if (preset == 'custom') {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(DateTime.now().year + 1, 12, 31),
        initialDateRange: (_from != null && _to != null)
            ? DateTimeRange(start: _from!, end: _to!)
            : null,
      );
      if (picked == null) return;
      setState(() {
        _range = 'custom';
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
        _visible = 10;
      });
      return;
    }
    final r = _rangeFor(preset);
    setState(() {
      _range = preset;
      _from = r?.from;
      _to = r?.to;
      _visible = 10;
    });
  }

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
        case 'decline':
          final reason =
              await showDeclineReasonDialog(context, title: 'Decline job');
          if (reason == null) {
            setState(() => _acting = -1);
            return;
          }
          await repo.decline(a.id, reason: reason.isEmpty ? null : reason);
          AppToast.success('Job declined');
          newStatus = 'declined';
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
    // Live: a booking we're subscribed to changed somewhere else.
    ref.listen(bookingRealtimeProvider, (_, __) => _onRealtime());
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
      body: Column(
        children: [
          _filterBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                for (var i = 0; i < 3; i++) _list(i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _rangePresets = [
    ('', 'All dates'),
    ('this_week', 'Week'),
    ('last_week', 'Last week'),
    ('this_month', 'This month'),
    ('last_month', 'Last month'),
    ('this_year', 'This year'),
    ('custom', 'Custom'),
  ];

  Widget _filterBar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search booking ID',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _q = '';
                          _visible = 10;
                        });
                      },
                    ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _rangePresets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final (val, label) = _rangePresets[i];
              final sel = _range == val;
              final text = (val == 'custom' &&
                      sel &&
                      _from != null &&
                      _to != null)
                  ? '${DateFormat('d MMM').format(_from!)} – ${DateFormat('d MMM').format(_to!)}'
                  : label;
              return ChoiceChip(
                label: Text(text, style: const TextStyle(fontSize: 12.5)),
                selected: sel,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _setRange(val),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _list(int i) {
    final base = _data[i];
    // Overlay shared crew patches, then keep only rows that still belong in
    // this tab (a completed job leaves "Upcoming", etc.) and pass the search /
    // date filters.
    final ov = ref.read(crewOverridesProvider.notifier);
    final filtered = base == null
        ? null
        : [
            for (final a in base.map(ov.apply))
              if (_belongsInTab(i, a.status) && _matchesFilters(a)) a
          ];
    // Client-side pagination: show the first _visible, with a Load More below.
    final hasMore = (filtered?.length ?? 0) > _visible;
    final rows = filtered?.take(_visible).toList();
    final filtering = _q.isNotEmpty || _from != null || _to != null;
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
      child = ListView(children: [
        const SizedBox(height: 80),
        EmptyState(
            icon: Icons.event_note_outlined,
            title: filtering ? 'No matching bookings' : 'Nothing here yet',
            subtitle: filtering ? 'Try a different search or date range.' : null),
      ]);
    } else {
      child = ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, k) {
          if (k >= rows.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _visible += 10),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text('Load more (${filtered!.length - rows.length})'),
              ),
            );
          }
          return _row(rows[k]);
        },
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
    Widget outlineBtn(String label, Color color, String action) {
      final handler = busy ? null : () => _act(a, action);
      return SizedBox(
        height: 42,
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withValues(alpha: 0.6)),
          ),
          onPressed: handler,
          child: Text(label),
        ),
      );
    }

    switch (a.status) {
      case 'pending_acceptance':
        return [
          const SizedBox(height: 10),
          btn('Accept', AppColors.brand600, 'accept'),
          const SizedBox(height: 8),
          outlineBtn('Decline', AppColors.rose, 'decline'),
        ];
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
