import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../bookings/models.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerEarningsScreen extends ConsumerStatefulWidget {
  const PartnerEarningsScreen({super.key});
  @override
  ConsumerState<PartnerEarningsScreen> createState() =>
      _PartnerEarningsScreenState();
}

class _PartnerEarningsScreenState
    extends ConsumerState<PartnerEarningsScreen> {
  late Future<_Earn> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Earn> _load() async {
    final repo = ref.read(partnerRepositoryProvider);
    final partnerId = ref.read(authControllerProvider).user?.partnerId ?? 0;
    final results = await Future.wait([
      repo.wallet(partnerId).catchError((_) => const WalletInfo()),
      repo.bookings(),
    ]);
    return _Earn(
        wallet: results[0] as WalletInfo,
        bookings: results[1] as List<PartnerBooking>);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<_Earn>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList(height: 110);
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load earnings.', onRetry: _reload);
            }
            final e = snap.data!;
            final completed =
                e.bookings.where((b) => b.status == 'completed').toList();
            final earned =
                completed.fold<double>(0, (s, b) => s + b.partnerCost);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.brand700, AppColors.brand500],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Wallet balance',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('AED ${e.wallet.balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                          'Lifetime earned AED ${e.wallet.lifetimeEarnings.toStringAsFixed(0)} · '
                          'paid out AED ${e.wallet.lifetimePaidOut.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _stat('Completed', '${completed.length}',
                            Icons.check_circle_outline)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _stat('Earned',
                            'AED ${earned.toStringAsFixed(0)}', Icons.payments_outlined)),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Completed bookings',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                if (completed.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: EmptyState(
                        icon: Icons.payments_outlined,
                        title: 'No completed bookings yet'),
                  )
                else
                  ...completed.map(_row),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.brand600, size: 20),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800)),
            Text(label,
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );

  Widget _row(PartnerBooking b) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.serviceName.isEmpty ? 'Service' : b.serviceName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  Text(
                      [
                        b.customerName,
                        if (b.scheduledStart != null)
                          DateFormat('d MMM').format(b.scheduledStart!)
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Text('AED ${b.partnerCost.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppColors.brand700, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _Earn {
  final WalletInfo wallet;
  final List<PartnerBooking> bookings;
  _Earn({required this.wallet, required this.bookings});
}
