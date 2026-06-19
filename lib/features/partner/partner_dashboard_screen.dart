import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerDashboardScreen extends ConsumerStatefulWidget {
  const PartnerDashboardScreen({super.key});
  @override
  ConsumerState<PartnerDashboardScreen> createState() =>
      _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState
    extends ConsumerState<PartnerDashboardScreen> {
  late Future<_Dash> _future;
  int _acting = -1;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Dash> _load() async {
    final repo = ref.read(partnerRepositoryProvider);
    final results = await Future.wait([
      repo.bookings(),
      repo.workers().catchError((_) => <Worker>[]),
      repo.vans().catchError((_) => <Van>[]),
    ]);
    return _Dash(
      bookings: results[0] as List<PartnerBooking>,
      workers: (results[1] as List).length,
      vans: (results[2] as List).length,
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _act(PartnerBooking b, bool accept) async {
    setState(() => _acting = b.id);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (accept) {
        await repo.acceptBooking(b.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineBooking(b.id);
        AppToast.success('Booking declined');
      }
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(authControllerProvider).user?.greetingName ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<_Dash>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList(count: 4, height: 96);
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load the dashboard.', onRetry: _reload);
            }
            final d = snap.data!;
            final now = DateTime.now();
            final today = d.bookings
                .where((b) =>
                    b.scheduledStart != null &&
                    DateUtils.isSameDay(b.scheduledStart, now))
                .length;
            final week = d.bookings
                .where((b) =>
                    b.scheduledStart != null &&
                    b.scheduledStart!.isAfter(now) &&
                    b.scheduledStart!
                        .isBefore(now.add(const Duration(days: 7))))
                .length;
            final pending = d.bookings
                .where((b) => b.status == 'awaiting_acceptance')
                .toList();
            final weekEarn = d.bookings
                .where((b) => b.status == 'completed')
                .fold<double>(0, (s, b) => s + b.partnerCost);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Hi, $name 👋',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.7,
                  children: [
                    _kpi('Today', '$today', Icons.today, AppColors.brand600),
                    _kpi('Next 7 days', '$week', Icons.date_range,
                        AppColors.sky),
                    _kpi('Workers', '${d.workers}', Icons.groups,
                        AppColors.violet),
                    _kpi('Vans', '${d.vans}', Icons.local_shipping,
                        AppColors.amber),
                  ],
                ),
                const SizedBox(height: 12),
                _earningsCard(weekEarn),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('Pending acceptance',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    if (pending.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                            color: AppColors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('${pending.length}',
                            style: const TextStyle(
                                color: AppColors.amber,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (pending.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'All caught up',
                        subtitle: 'No bookings awaiting your acceptance.'),
                  )
                else
                  ...pending.map(_pendingCard),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12.5)),
          ],
        ),
      );

  Widget _earningsCard(double amount) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.brand600, AppColors.brand500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.account_balance_wallet,
                color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Earnings (completed)',
                    style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                Text('AED ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      );

  Widget _pendingCard(PartnerBooking b) {
    final busy = _acting == b.id;
    final time = b.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(b.scheduledStart!)
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                child: Text(b.serviceName.isEmpty ? 'Service' : b.serviceName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              StatusBadge(b.status),
            ],
          ),
          const SizedBox(height: 3),
          Text([b.customerName, b.area, time].where((s) => s.isNotEmpty).join(' · '),
              style:
                  const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: busy ? null : () => _act(b, true),
                    child: const Text('Accept'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: busy ? null : () => _act(b, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rose,
                        side: const BorderSide(color: AppColors.rose)),
                    child: const Text('Decline'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dash {
  final List<PartnerBooking> bookings;
  final int workers;
  final int vans;
  _Dash({required this.bookings, required this.workers, required this.vans});
}
