import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
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

  Future<List<Assignment>> _load(String status) =>
      ref.read(workerRepositoryProvider).myBookings(status: status);

  void _reload(int i) =>
      setState(() => _futures[i] = _load(_statuses[i]));

  @override
  Widget build(BuildContext context) {
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
      onRefresh: () async => _reload(i),
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
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : '';
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
              style:
                  TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
          if (a.fullAddress.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(a.fullAddress,
                style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
          ],
        ],
      ),
    );
  }
}
