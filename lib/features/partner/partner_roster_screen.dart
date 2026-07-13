import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/main_app_bar.dart';
import '../bookings/models.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Partner "day roster" — the operational who's-on-what view. The web renders
/// a workers × time grid (/admin/schedule); on mobile we group the day's
/// assignments per worker so the partner sees each person's jobs (and who's
/// free) for the picked day.
class PartnerRosterScreen extends ConsumerStatefulWidget {
  const PartnerRosterScreen({super.key});
  @override
  ConsumerState<PartnerRosterScreen> createState() =>
      _PartnerRosterScreenState();
}

class _PartnerRosterScreenState extends ConsumerState<PartnerRosterScreen> {
  DateTime _date = DateTime.now();
  List<Worker>? _workers;
  List<Assignment>? _assignments;
  bool _err = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final repo = ref.read(partnerRepositoryProvider);
    final start = DateTime(_date.year, _date.month, _date.day);
    final end = start.add(const Duration(days: 1));
    try {
      final results = await Future.wait([
        repo.workers().catchError((_) => <Worker>[]),
        repo
            .dayAssignments(from: start, to: end)
            .catchError((_) => <Assignment>[]),
      ]);
      if (mounted) {
        setState(() {
          _workers = results[0] as List<Worker>;
          _assignments = results[1] as List<Assignment>;
          _err = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _err = true);
    }
  }

  void _changeDate(DateTime d) {
    setState(() {
      _date = d;
      _workers = null;
      _assignments = null;
      _err = false;
    });
    _fetch();
  }

  void _shift(int days) => _changeDate(_date.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (d != null) _changeDate(d);
  }

  // Jobs assigned to a worker (as crew or driver), earliest first.
  List<Assignment> _jobsFor(Worker w) {
    final list = (_assignments ?? [])
        .where((a) => a.workerId == w.id || a.driverWorkerId == w.id)
        .toList();
    list.sort((a, b) => (a.scheduledStart ?? DateTime(2100))
        .compareTo(b.scheduledStart ?? DateTime(2100)));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    return Scaffold(
      appBar: MainAppBar('Team roster', actions: [
        IconButton(onPressed: _fetch, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            IconButton(
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: InkWell(
                onTap: _pickDate,
                child: Center(
                  child: Text(
                    '${DateFormat('EEE d MMM y').format(_date)}'
                    '${isToday ? '  (today)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            if (!isToday)
              TextButton(
                  onPressed: () => _changeDate(DateTime.now()),
                  child: const Text('Today')),
            IconButton(
                onPressed: () => _shift(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: RefreshIndicator(onRefresh: _fetch, child: _body())),
      ]),
    );
  }

  Widget _body() {
    final workers = _workers;
    final assignments = _assignments;
    if (workers == null || assignments == null) {
      return _err
          ? ListView(children: [
              const SizedBox(height: 60),
              ErrorRetry(
                  message: "Couldn't load the roster.", onRetry: _fetch),
            ])
          : const LoadingList(height: 100);
    }
    if (workers.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 60),
        EmptyState(
            icon: Icons.groups_outlined,
            title: 'No team members',
            subtitle: 'Add workers to see their roster here.'),
      ]);
    }
    // Busy workers (with jobs) first, ordered by their earliest job; then free.
    final rows = workers.map((w) => (w, _jobsFor(w))).toList();
    rows.sort((a, b) {
      final aj = a.$2, bj = b.$2;
      if (aj.isEmpty != bj.isEmpty) return aj.isEmpty ? 1 : -1;
      if (aj.isEmpty) return a.$1.name.compareTo(b.$1.name);
      return (aj.first.scheduledStart ?? DateTime(2100))
          .compareTo(bj.first.scheduledStart ?? DateTime(2100));
    });
    final totalJobs = assignments.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${workers.length} worker${workers.length == 1 ? '' : 's'} · '
            '$totalJobs job${totalJobs == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _workerSection(r.$1, r.$2),
          ),
      ],
    );
  }

  Widget _workerSection(Worker w, List<Assignment> jobs) {
    final initials = w.name.isEmpty
        ? '?'
        : w.name
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();
    final role = w.roles.contains('driver')
        ? (w.roles.contains('crew') ? 'Crew · Driver' : 'Driver')
        : 'Crew';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.brand50,
              child: Text(initials,
                  style: const TextStyle(
                      color: AppColors.brand700,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name.isEmpty ? 'Worker #${w.id}' : w.name,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(role,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: jobs.isEmpty
                    ? AppColors.bg
                    : AppColors.brand50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                  jobs.isEmpty ? 'Free' : '${jobs.length} job${jobs.length == 1 ? '' : 's'}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: jobs.isEmpty
                          ? AppColors.textMuted
                          : AppColors.brand700)),
            ),
          ]),
          if (jobs.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Divider(height: 12),
            for (final a in jobs) _jobRow(a),
          ],
        ],
      ),
    );
  }

  Widget _jobRow(Assignment a) {
    final t = a.scheduledStart != null
        ? DateFormat('h:mm a').format(a.scheduledStart!)
        : '--:--';
    final (bg, fg) = AppColors.dispatchStatus(a.status);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(t,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    a.serviceName.isEmpty ? a.bookingCode : a.serviceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                if (a.customerName.isNotEmpty)
                  Text(a.customerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
            child: Text(a.status.replaceAll('_', ' '),
                style: TextStyle(
                    color: fg, fontSize: 9.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
