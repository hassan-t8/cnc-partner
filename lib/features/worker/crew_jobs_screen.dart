import 'dart:async';

import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'booking_photos.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/booking_ref_chip.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'crew_sync.dart';
import 'otp_dialog.dart';
import 'today_summary.dart';
import 'worker_booking_detail_screen.dart';
import 'worker_repository.dart';

class CrewJobsScreen extends ConsumerStatefulWidget {
  const CrewJobsScreen({super.key});
  @override
  ConsumerState<CrewJobsScreen> createState() => _CrewJobsScreenState();
}

class _CrewJobsScreenState extends ConsumerState<CrewJobsScreen> {
  List<Assignment> _jobs = [];
  bool _loading = true;
  bool _error = false;
  int _acting = -1;
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  // Job count per date-only day (across all the worker's jobs) → drives the
  // dot markers on the day strip (more jobs = more dots).
  Map<DateTime, int> _jobCounts = {};

  // Captured once while `ref` is valid so dispose() can leave the booking rooms
  // without touching `ref` (using ref after dispose throws).
  BookingRealtime? _rt;
  Timer? _rtDebounce;
  // Ticks the "Up next" countdown label. Minute-granularity, so 30s is plenty.
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _rt = ref.read(bookingRealtimeProvider.notifier);
    _load();
    _loadJobDays();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _rtDebounce?.cancel();
    _tick?.cancel();
    _rt?.releaseBookingRooms(this);
    super.dispose();
  }

  /// The job the crew should focus on next: an in-progress job takes priority,
  /// else the soonest accepted job. Mirrors the web crew "Up next" hero.
  Assignment? _upNext(List<Assignment> jobs) {
    int byStart(Assignment a, Assignment b) =>
        (a.scheduledStart ?? DateTime(2100))
            .compareTo(b.scheduledStart ?? DateTime(2100));
    final inProg = jobs.where((j) => j.status == 'in_progress').toList()
      ..sort(byStart);
    if (inProg.isNotEmpty) return inProg.first;
    final accepted = jobs.where((j) => j.status == 'accepted').toList()
      ..sort(byStart);
    return accepted.isNotEmpty ? accepted.first : null;
  }

  /// "in 2h 15m" / "in 25m" / "starts now" / "5m late".
  String? _countdownLabel(DateTime? start) {
    if (start == null) return null;
    final diff = start.difference(DateTime.now());
    final abs = diff.abs();
    final parts =
        abs.inHours > 0 ? '${abs.inHours}h ${abs.inMinutes % 60}m' : '${abs.inMinutes}m';
    if (diff.inMinutes > 1) return 'in $parts';
    if (diff.inMinutes < -1) return '$parts late';
    return 'starts now';
  }

  /// Subscribe to a `booking_<id>` room for every job currently on screen.
  /// The backend has no worker room, so these per-booking rooms are the only
  /// way this screen hears about start / cash-collected / completed / cancelled
  /// happening from the web, the partner, or another device.
  void _syncRooms() =>
      _rt?.syncBookingRooms(this, _jobs.map((j) => j.bookingId).whereType<int>());

  /// A booking we're watching changed somewhere else — refetch quietly.
  void _onRealtime() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refresh();
    });
  }

  /// Count of jobs per day — for the day-strip dots. Best-effort. Also seeds
  /// the shared crew store with cash-collected state, because the My-Jobs feed
  /// (/booking-assignments) doesn't send `cashCollected` — so without this a
  /// booking whose cash was already collected keeps showing "Collect" here.
  Future<void> _loadJobDays() async {
    try {
      final all =
          await ref.read(workerRepositoryProvider).myBookings(status: 'all');
      if (!mounted) return;
      final counts = <DateTime, int>{};
      for (final a in all) {
        if (a.scheduledStart == null ||
            a.status == 'cancelled' ||
            a.status == 'declined') continue;
        final d = DateUtils.dateOnly(a.scheduledStart!);
        counts[d] = (counts[d] ?? 0) + 1;
      }
      // Seed "no cash to collect" from the rich /workers/me/bookings feed,
      // which carries the payment fields (paymentStatus, coins, remaining,
      // cashCollected) — so its cashPending is authoritative. Suppress the
      // My-Jobs "Collect" button for EVERY settled booking it reports (paid
      // online / wallet / already collected), not just cash-collected ones.
      // The My-Jobs feed (/booking-assignments) omits those payment fields and
      // would otherwise show a phantom "Collect AED …" on an already-paid
      // booking; the web reads this same feed and correctly shows "Complete".
      ref.read(crewOverridesProvider.notifier).seedCollected(
          all.where((a) => !a.cashPending).map((a) => a.bookingId));
      setState(() => _jobCounts = counts);
    } catch (_) {}
  }

  Future<List<Assignment>> _fetch() {
    final workerId = ref.read(authControllerProvider).user?.workerId ?? 0;
    final from = _date;
    final to = _date.add(const Duration(days: 1));
    return ref
        .read(workerRepositoryProvider)
        .assignments(workerId: workerId, from: from, to: to);
  }

  // Initial / date-change load — shows the skeleton.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final jobs = await _fetch();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
      _syncRooms();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _reload() => _load();

  // Pull-to-refresh: refetch in place WITHOUT dropping to the skeleton, so the
  // spinner ends as soon as fresh data lands and the list stays visible.
  Future<void> _refresh() async {
    _loadJobDays();
    try {
      final jobs = await _fetch();
      if (mounted) {
        setState(() {
          _jobs = jobs;
          _error = false;
        });
        _syncRooms();
      }
    } catch (_) {
      if (mounted && _jobs.isEmpty) setState(() => _error = true);
    }
  }

  void _pickDate(DateTime d) {
    final day = DateUtils.dateOnly(d);
    if (day == _date) return;
    setState(() => _date = day);
    _load();
  }

  Future<void> _openDetail(Assignment a) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerBookingDetailScreen(assignment: a)));
    // Refetch this day in place (no skeleton) — the detail screen may have
    // changed the booking.
    if (mounted) _refresh();
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
          final reason = await _reasonDialog();
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
      // Write to the shared crew store — no full-day refetch. Every crew
      // screen overlays this, so the change shows everywhere and survives a
      // refresh.
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
      // Persist in the shared store — /booking-assignments doesn't echo
      // cashCollected, so this is what stops "Collect" reappearing on refresh.
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

  Future<String?> _reasonDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline job'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration:
              const InputDecoration(hintText: 'Reason (optional)'),
        ),
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

  @override
  Widget build(BuildContext context) {
    // Refetch when this tab is (re)tapped on the bottom nav.
    ref.listen(tabRefreshProvider, (_, __) => _reload());
    // Live: a booking we're subscribed to changed (started / cash collected /
    // completed / cancelled) from the web, the partner, or another device.
    ref.listen(bookingRealtimeProvider, (_, __) => _onRealtime());
    // Rebuild whenever any crew screen changes a booking, and overlay those
    // changes on this day's server data so state is consistent everywhere.
    ref.watch(crewOverridesProvider);
    final ov = ref.read(crewOverridesProvider.notifier);
    final jobs = [for (final j in _jobs) ov.apply(j)];
    // "Up next" hero — only for today, so it stays a genuine "what's next".
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    final upNext = isToday ? _upNext(jobs) : null;
    // Drop the hero job from the list so it isn't shown twice.
    final listJobs =
        upNext == null ? jobs : [for (final j in jobs) if (j.id != upNext.id) j];
    return Scaffold(
      appBar: const MainAppBar('My jobs'),
      body: Column(
        children: [
          TodaySummary(jobs: jobs),
          _dateStrip(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading
                  ? const LoadingList()
                  : (_error && _jobs.isEmpty)
                      ? ListView(children: [
                          const SizedBox(height: 60),
                          ErrorRetry(
                              message: 'Couldn\'t load your jobs.',
                              onRetry: _reload),
                        ])
                      : jobs.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 80),
                              EmptyState(
                                icon: Icons.event_available,
                                title: 'Nothing scheduled',
                                subtitle:
                                    'No jobs for this day — try another date.',
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount:
                                  listJobs.length + (upNext != null ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) {
                                if (upNext != null && i == 0) {
                                  return _upNextCard(upNext);
                                }
                                final j =
                                    listJobs[upNext != null ? i - 1 : i];
                                return _jobCard(j);
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }

  /// Prominent hero card for the next/active job with a live countdown.
  Widget _upNextCard(Assignment a) {
    final inProgress = a.status == 'in_progress';
    final accent = inProgress ? AppColors.amber : AppColors.emerald;
    final countdown = _countdownLabel(a.scheduledStart);
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : null;
    return InkWell(
      onTap: () => _openDetail(a),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 4)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: accent),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(inProgress ? Icons.bolt : Icons.arrow_forward_rounded,
                          size: 14, color: accent),
                      const SizedBox(width: 5),
                      Text(inProgress ? 'WORKING NOW' : 'UP NEXT',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                              color: accent)),
                      const Spacer(),
                      if (countdown != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 12, color: accent),
                              const SizedBox(width: 4),
                              Text(countdown,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: accent)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ServiceTitle(a.serviceName, titleSize: 16),
                  const SizedBox(height: 2),
                  Text(a.bookingRef,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                  if (time != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule_outlined,
                            size: 15, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Text(time,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  _actions(a, _acting == a.id),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Horizontal day picker: the next ~10 days plus a calendar button for any
  /// date, so the crew can filter their jobs by day.
  Widget _dateStrip() {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = [for (var i = 0; i < 10; i++) today.add(Duration(days: i))];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _dayChip(days[i], today),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month_outlined, size: 22),
            color: AppColors.brand600,
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: today.subtract(const Duration(days: 30)),
                lastDate: today.add(const Duration(days: 120)),
              );
              if (picked != null) _pickDate(picked);
            },
          ),
        ],
      ),
    );
  }

  Widget _dayChip(DateTime day, DateTime today) {
    final on = day == _date;
    final count = _jobCounts[day] ?? 0;
    final label = day == today
        ? 'Today'
        : day == today.add(const Duration(days: 1))
            ? 'Next'
            : DateFormat('EEE').format(day);
    return GestureDetector(
      onTap: () => _pickDate(day),
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: on ? AppColors.brand600 : AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppColors.brand600 : AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // FittedBox keeps the labels centered + inside the chip on any
            // text-scale.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : AppColors.textMuted)),
                  const SizedBox(height: 3),
                  Text(DateFormat('d MMM').format(day),
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11.5,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: on ? Colors.white : AppColors.textPrimary)),
                ],
              ),
            ),
            const SizedBox(height: 5),
            // Job dots at the bottom, centered (more jobs → more dots). Always
            // reserves the row so every chip stays the same height.
            _jobDots(count, on),
          ],
        ),
      ),
    );
  }

  Widget _jobDots(int count, bool on) {
    final n = count.clamp(0, 3);
    final base = on ? Colors.white : AppColors.brand600;
    return SizedBox(
      height: 5,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: base.withValues(alpha: (1.0 - i * 0.30).clamp(0.35, 1.0)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _jobCard(Assignment a) {
    final busy = _acting == a.id;
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : 'Time TBD';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openDetail(a),
        borderRadius: BorderRadius.circular(14),
        child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ServiceTitle(a.serviceName, titleSize: 15.5),
              ),
              StatusBadge(a.status, worker: true),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
            ],
          ),
          // Booking reference (CNC-B-xxxx) so the crew can identify the job.
          const SizedBox(height: 4),
          BookingRefChip(a.bookingRef),
          const SizedBox(height: 6),
          _row(Icons.schedule, time),
          if (a.customerName.isNotEmpty)
            _row(Icons.person_outline, a.customerName,
                // Call the CUSTOMER (fall back to partner only if we have no
                // customer number). Previously dialled the partner, and showed
                // no Call button at all when partnerPhone was empty.
                trailing: () {
                  final phone = (a.customerPhone?.isNotEmpty ?? false)
                      ? a.customerPhone!
                      : (a.partnerPhone ?? '');
                  return phone.isNotEmpty
                      ? _miniAction(
                          Icons.call,
                          'Call',
                          () => launchUrl(Uri.parse(
                              'tel:${phone.replaceAll(' ', '')}')))
                      : null;
                }()),
          if (a.fullAddress.isNotEmpty || a.mapUrl != null)
            _row(Icons.place_outlined,
                a.fullAddress.isNotEmpty ? a.fullAddress : 'Pinned location',
                trailing: a.mapUrl != null
                    ? _miniAction(Icons.directions, 'Directions',
                        () => launchUrl(Uri.parse(a.mapUrl!),
                            mode: LaunchMode.externalApplication))
                    : null),
          const SizedBox(height: 10),
          _actions(a, busy),
          if (a.role.toLowerCase() != 'driver' &&
              (a.status == 'accepted' ||
                  a.status == 'in_progress' ||
                  a.status == 'completed')) ...[
            const Divider(height: 18),
            BookingPhotos(
              key: ValueKey('photos-${a.id}-${a.status}'),
              assignmentId: a.id,
              collapsible: true,
              showAfter:
                  a.status == 'in_progress' || a.status == 'completed',
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }

  /// Drivers (and driver-only users) never run the job.
  bool _isDriverView(Assignment a) {
    if (a.isDriverRole) return true;
    final u = ref.read(authControllerProvider).user;
    return u != null && u.isDriver && !u.isCrew;
  }

  /// Only the team LEAD may start the job, collect cash or complete it.
  bool _viewOnly(Assignment a) => _isDriverView(a) || !a.isLead;

  String _viewOnlyNote(Assignment a) => _isDriverView(a)
      ? 'View only — the crew or partner starts this job.'
      : 'View only — only the team lead can start or complete this job.';

  Widget _actions(Assignment a, bool busy) {
    // Non-lead crew + drivers see the job read-only once it's accepted.
    if (_viewOnly(a) && (a.status == 'accepted' || a.status == 'in_progress')) {
      return Row(
        children: [
          Icon(Icons.visibility_outlined, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(_viewOnlyNote(a),
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
        ],
      );
    }
    final children = <Widget>[];
    switch (a.status) {
      case 'pending_acceptance':
        children.add(_primary('Accept', AppColors.brand600,
            busy ? null : () => _act(a, 'accept')));
        children.add(_primary('Decline', AppColors.rose,
            busy ? null : () => _act(a, 'decline')));
        break;
      case 'accepted':
        children.add(_primary('Start', AppColors.violet,
            busy ? null : () => _act(a, 'start')));
        break;
      case 'in_progress':
        // Cash still owed → collect before completing (backend enforces it).
        if (a.cashPending) {
          children.add(_primary('Collect AED ${a.cashDue.toStringAsFixed(0)}',
              AppColors.amber, busy ? null : () => _collectCash(a)));
          children.add(
              _primary('Complete', AppColors.brand600, null)); // disabled
        } else {
          children.add(_primary('Complete', AppColors.brand600,
              busy ? null : () => _act(a, 'complete')));
        }
        break;
    }
    if (children.isEmpty) return const SizedBox.shrink();
    final row = Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
    if (a.status == 'in_progress' && a.cashPending) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
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
          ),
          const SizedBox(height: 8),
          row,
        ],
      );
    }
    return row;
  }

  Widget _primary(String label, Color color, VoidCallback? onTap) => SizedBox(
        height: 42,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  /// Circular icon action (Directions / Call) that lives at the end of an info
  /// row — keeps the card short instead of a full-width button row, but stays
  /// big enough to be an easy tap target.
  Widget _miniAction(IconData icon, String tooltip, VoidCallback onTap) =>
      Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.brand600.withValues(alpha: 0.35)),
            ),
            child: Icon(icon, size: 22, color: AppColors.brand600),
          ),
        ),
      );

  Widget _row(IconData icon, String text, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
          ],
        ),
      );
}
