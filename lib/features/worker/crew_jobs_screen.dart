import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'booking_photos.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'otp_dialog.dart';
import 'today_summary.dart';
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
  // Date-only days (across all the worker's jobs) that have at least one job →
  // drives the dot markers on the day strip.
  Set<DateTime> _jobDays = {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadJobDays();
  }

  /// All days the worker has jobs on — for the day-strip dots. Best-effort.
  Future<void> _loadJobDays() async {
    try {
      final all =
          await ref.read(workerRepositoryProvider).myBookings(status: 'all');
      if (!mounted) return;
      setState(() {
        _jobDays = {
          for (final a in all)
            if (a.scheduledStart != null &&
                a.status != 'cancelled' &&
                a.status != 'declined')
              DateUtils.dateOnly(a.scheduledStart!)
        };
      });
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
      if (mounted) setState(() {
        _jobs = jobs;
        _error = false;
      });
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

  Future<void> _act(Assignment a, String action) async {
    final repo = ref.read(workerRepositoryProvider);
    setState(() => _acting = a.id);
    try {
      switch (action) {
        case 'accept':
          await repo.accept(a.id);
          AppToast.success('Job accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _acting = -1);
            return;
          }
          await repo.decline(a.id, reason: reason.isEmpty ? null : reason);
          AppToast.success('Job declined');
          break;
        case 'start':
          await _start(a);
          break;
        case 'complete':
          await repo.complete(a.id);
          AppToast.success('Job completed');
          break;
      }
      _reload();
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
      _reload();
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
    return Scaffold(
      appBar: const MainAppBar('My jobs'),
      body: Column(
        children: [
          TodaySummary(jobs: _jobs),
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
                      : _jobs.isEmpty
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
                              itemCount: _jobs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) => _jobCard(_jobs[i]),
                            ),
            ),
          ),
        ],
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
        // FittedBox keeps the labels inside the chip on any device / text-scale.
        child: FittedBox(
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
              const SizedBox(height: 3),
              // Dot marker when this day has at least one job.
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _jobDays.contains(day)
                      ? (on ? Colors.white : AppColors.brand600)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _jobCard(Assignment a) {
    final busy = _acting == a.id;
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : 'Time TBD';
    return Container(
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
            ],
          ),
          const SizedBox(height: 6),
          _row(Icons.schedule, time),
          if (a.customerName.isNotEmpty) _row(Icons.person_outline, a.customerName),
          if (a.fullAddress.isNotEmpty) _row(Icons.place_outlined, a.fullAddress),
          const SizedBox(height: 10),
          Row(
            children: [
              if (a.fullAddress.isNotEmpty)
                _ghost(Icons.directions_outlined, 'Directions', () {
                  launchUrl(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a.fullAddress)}'),
                    mode: LaunchMode.externalApplication,
                  );
                }),
              if (a.partnerPhone != null && a.partnerPhone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _ghost(Icons.call_outlined, 'Call', () {
                  launchUrl(Uri.parse('tel:${a.partnerPhone}'));
                }),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _actions(a, busy),
          if (a.status == 'accepted' ||
              a.status == 'in_progress' ||
              a.status == 'completed') ...[
            const Divider(height: 20),
            BookingPhotos(
              key: ValueKey('photos-${a.id}-${a.status}'),
              assignmentId: a.id,
              showAfter:
                  a.status == 'in_progress' || a.status == 'completed',
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(Assignment a, bool busy) {
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

  Widget _ghost(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))),
          ],
        ),
      );
}
