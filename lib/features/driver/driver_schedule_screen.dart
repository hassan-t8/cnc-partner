import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/main_app_bar.dart';
import 'driver_repository.dart';

/// Driver's day-by-day schedule: the route as a timeline of legs (depart,
/// pickup, job, travel, drop, return) with times — mirrors the web
/// /driver/schedule page. Pick any date with the day arrows or calendar.
class DriverScheduleScreen extends ConsumerStatefulWidget {
  const DriverScheduleScreen({super.key});
  @override
  ConsumerState<DriverScheduleScreen> createState() =>
      _DriverScheduleScreenState();
}

class _DriverScheduleScreenState extends ConsumerState<DriverScheduleScreen> {
  DriverDayPlan? _plan;
  bool _loading = true;
  bool _error = false;
  DateTime _date = DateUtils.dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<DriverDayPlan> _fetch() {
    final workerId = ref.read(authControllerProvider).user?.workerId ?? 0;
    return ref.read(driverRepositoryProvider).day(workerId, _date);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final plan = await _fetch();
      if (!mounted) return;
      setState(() {
        _plan = plan;
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

  // Pull-to-refresh: refetch in place without the skeleton.
  Future<void> _refresh() async {
    try {
      final plan = await _fetch();
      if (mounted) setState(() {
        _plan = plan;
        _error = false;
      });
    } catch (_) {
      if (mounted && _plan == null) setState(() => _error = true);
    }
  }

  void _shiftDay(int days) {
    setState(() => _date = DateUtils.dateOnly(_date.add(Duration(days: days))));
    _load();
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today.subtract(const Duration(days: 30)),
      lastDate: today.add(const Duration(days: 120)),
    );
    if (picked != null) {
      setState(() => _date = DateUtils.dateOnly(picked));
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabRefreshProvider, (_, __) => _load());
    return Scaffold(
      appBar: const MainAppBar('Schedule'),
      body: Column(
        children: [
          _dateBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _loading
                  ? const LoadingList()
                  : (_error && _plan == null)
                      ? ListView(children: [
                          const SizedBox(height: 60),
                          ErrorRetry(
                              message: 'Couldn\'t load your schedule.',
                              onRetry: _load),
                        ])
                      : _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateBar() {
    final today = DateUtils.dateOnly(DateTime.now());
    final isToday = _date == today;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftDay(-1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Column(
                children: [
                  Text(DateFormat('EEE, d MMM y').format(_date),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14.5)),
                  if (isToday)
                    Text('Today',
                        style: TextStyle(
                            color: AppColors.brand600,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftDay(1),
          ),
          IconButton(
            tooltip: 'Pick a date',
            icon: const Icon(Icons.calendar_month_outlined),
            color: AppColors.brand600,
            onPressed: _pickDate,
          ),
        ],
      ),
    );
  }

  Widget _body() {
    final plan = _plan!;
    final legs = plan.legs;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (plan.vanName.isNotEmpty || plan.homeZone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              [
                if (plan.vanName.isNotEmpty)
                  '${plan.vanName} · ${plan.vanSeats} seats',
                if (plan.homeZone.isNotEmpty) 'Home ${plan.homeZone}',
              ].join(' · '),
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        for (final w in plan.warnings)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(w,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
        if (legs.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No stops on this day',
              subtitle: 'Pick another date to see that day\'s route.',
            ),
          )
        else
          for (var i = 0; i < legs.length; i++)
            _legTile(legs[i], i == legs.length - 1),
      ],
    );
  }

  Widget _legTile(RouteLeg leg, bool last) {
    final (icon, tone, label) = _legConfig(leg.type);
    final time = [leg.atLabel, leg.endAtLabel]
        .where((s) => s.isNotEmpty)
        .join(' – ');
    final isJob = leg.type == 'job';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail
          Column(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 17, color: tone),
              ),
              if (!last)
                Expanded(
                  child: Container(width: 2, color: AppColors.border),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14)),
                            if (leg.bookingRef.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(leg.bookingRef,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textMuted,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(time,
                            style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w700)),
                    ],
                  ),
                  if (isJob && leg.service.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(leg.service,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  if (leg.customerName.isNotEmpty)
                    _sub(Icons.person_outline, leg.customerName),
                  if (leg.address.isNotEmpty)
                    _sub(Icons.place_outlined, leg.address),
                  if (leg.type == 'travel' &&
                      (leg.fromLabel.isNotEmpty || leg.toLabel.isNotEmpty))
                    _sub(Icons.directions_car_outlined,
                        '${leg.fromLabel} → ${leg.toLabel}'),
                  if (leg.note.isNotEmpty)
                    _sub(Icons.sticky_note_2_outlined, leg.note),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sub(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ],
        ),
      );

  (IconData, Color, String) _legConfig(String type) {
    switch (type) {
      case 'depart':
        return (Icons.home_outlined, AppColors.brand600, 'Depart');
      case 'pickup':
        return (Icons.groups_outlined, AppColors.sky, 'Pickup');
      case 'job':
        return (Icons.work_outline, AppColors.violet, 'Job');
      case 'travel':
        return (Icons.navigation_outlined, AppColors.textMuted, 'Travel');
      case 'dropoff':
        return (Icons.groups_2_outlined, AppColors.amber, 'Drop off');
      case 'return':
        return (Icons.home_outlined, AppColors.brand600, 'Return');
      default:
        return (Icons.place_outlined, AppColors.textMuted,
            type.isEmpty ? 'Stop' : type);
    }
  }
}
