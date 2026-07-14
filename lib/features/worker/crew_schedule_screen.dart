import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/main_app_bar.dart';
import '../bookings/models.dart';
import 'worker_booking_detail_screen.dart';
import 'worker_repository.dart';

/// The crew worker's own day schedule — their assignments for the picked day,
/// laid out in time order. Mirrors the partner-portal /crew/schedule grid,
/// scoped (like it) to the logged-in worker.
class CrewScheduleScreen extends ConsumerStatefulWidget {
  const CrewScheduleScreen({super.key});
  @override
  ConsumerState<CrewScheduleScreen> createState() =>
      _CrewScheduleScreenState();
}

class _CrewScheduleScreenState extends ConsumerState<CrewScheduleScreen> {
  DateTime _date = DateTime.now();
  List<Assignment>? _items;
  bool _err = false;

  int get _workerId => ref.read(authControllerProvider).user?.workerId ?? 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final start = DateTime(_date.year, _date.month, _date.day);
    final end = start.add(const Duration(days: 1));
    try {
      final list = await ref
          .read(workerRepositoryProvider)
          .assignments(workerId: _workerId, from: start, to: end);
      list.sort((a, b) =>
          (a.scheduledStart ?? start).compareTo(b.scheduledStart ?? start));
      if (mounted) {
        setState(() {
          _items = list;
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
      _items = null;
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

  @override
  Widget build(BuildContext context) {
    ref.listen(tabRefreshProvider, (_, __) => _fetch());
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    return Scaffold(
      appBar: MainAppBar('My schedule', actions: [
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
    final items = _items;
    if (items == null) {
      return _err
          ? ListView(children: [
              const SizedBox(height: 60),
              ErrorRetry(
                  message: "Couldn't load your schedule.", onRetry: _fetch),
            ])
          : const LoadingList(height: 100);
    }
    if (items.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 60),
        EmptyState(
            icon: Icons.event_available_outlined,
            title: 'Nothing scheduled',
            subtitle: 'You have no jobs on this day.'),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _card(items[i]),
      ),
    );
  }

  /// Open the job. The schedule was read-only — every other list of jobs in the
  /// app opens its detail on tap, so this one looked broken by comparison.
  /// Refresh on return: the status may have changed in there (started, completed).
  Future<void> _openDetail(Assignment a) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => WorkerBookingDetailScreen(assignment: a)));
    if (mounted) _fetch();
  }

  Widget _card(Assignment a) {
    final start = a.scheduledStart != null
        ? DateFormat('h:mm').format(a.scheduledStart!)
        : '--:--';
    final ampm = a.scheduledStart != null
        ? DateFormat('a').format(a.scheduledStart!)
        : '';
    final end = a.scheduledEnd != null
        ? DateFormat('h:mm a').format(a.scheduledEnd!)
        : '';
    final (bg, fg) = AppColors.dispatchStatus(a.status);
    final label = a.status.replaceAll('_', ' ');
    return InkWell(
      onTap: () => _openDetail(a),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(start,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                if (ampm.isNotEmpty)
                  Text(ampm,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Container(
            width: 3,
            height: 44,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          a.serviceName.isEmpty
                              ? a.bookingCode
                              : a.serviceName,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(20)),
                      child: Text(label,
                          style: TextStyle(
                              color: fg,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                if (a.customerName.isNotEmpty || end.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      [
                        if (a.customerName.isNotEmpty) a.customerName,
                        if (end.isNotEmpty) 'ends $end',
                      ].join('  ·  '),
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12.5),
                    ),
                  ),
                if (a.address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(a.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
