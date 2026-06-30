import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'partner_repository.dart';

class PartnerScheduleScreen extends ConsumerStatefulWidget {
  const PartnerScheduleScreen({super.key});
  @override
  ConsumerState<PartnerScheduleScreen> createState() =>
      _PartnerScheduleScreenState();
}

class _PartnerScheduleScreenState
    extends ConsumerState<PartnerScheduleScreen> {
  late Future<List<PartnerBooking>> _future;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).bookings();
  }

  void _reload() => setState(
      () => _future = ref.read(partnerRepositoryProvider).bookings());

  void _shift(int days) =>
      setState(() => _date = _date.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    return Scaffold(
      appBar: MainAppBar('Schedule'),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Center(
                    child: Text(
                        '${DateFormat('EEE d MMM y').format(_date)}'
                        '${isToday ? '  (today)' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                if (!isToday)
                  TextButton(
                      onPressed: () => setState(() => _date = DateTime.now()),
                      child: const Text('Today')),
                IconButton(
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<PartnerBooking>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LoadingList();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(
                        message: 'Couldn\'t load schedule.', onRetry: _reload);
                  }
                  final rows = (snap.data ?? const [])
                      .where((b) =>
                          b.scheduledStart != null &&
                          DateUtils.isSameDay(b.scheduledStart, _date))
                      .toList()
                    ..sort((a, b) =>
                        (a.scheduledStart ?? DateTime(0))
                            .compareTo(b.scheduledStart ?? DateTime(0)));
                  if (rows.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(
                          icon: Icons.event_busy_outlined,
                          title: 'Nothing scheduled',
                          subtitle: 'No bookings on this day.'),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _row(rows[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(PartnerBooking b) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              alignment: Alignment.center,
              child: Text(
                  b.scheduledStart != null
                      ? DateFormat('h:mm a').format(b.scheduledStart!)
                      : '',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
            Container(width: 1, height: 36, color: AppColors.border),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ServiceTitle(b.serviceName, titleSize: 14),
                  Text(
                      [b.customerName, b.area]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            StatusBadge(b.status),
          ],
        ),
      );
}
