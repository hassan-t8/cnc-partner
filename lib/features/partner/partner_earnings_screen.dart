import '../../widgets/main_app_bar.dart';
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
  String _txFilter = 'settled'; // settled | pending | all

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Earn> _load() async {
    final repo = ref.read(partnerRepositoryProvider);
    final partnerId = ref.read(authControllerProvider).user?.partnerId ?? 0;
    final results = await Future.wait([
      repo.wallet(partnerId).catchError((_) => const WalletStatement()),
      repo.bookings().catchError((_) => <PartnerBooking>[]),
    ]);
    return _Earn(
        statement: results[0] as WalletStatement,
        bookings: results[1] as List<PartnerBooking>);
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Earnings'),
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
            final w = e.statement.wallet;
            // Newest-first chronological (web parity).
            final txns = [...e.statement.transactions]..sort((a, b) {
                final ad = a.createdAt, bd = b.createdAt;
                if (ad == null && bd == null) return 0;
                if (ad == null) return 1;
                if (bd == null) return -1;
                return bd.compareTo(ad);
              });
            final completed =
                e.bookings.where((b) => b.status == 'completed').length;
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
                      Text('AED ${w.balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900)),
                      if (w.pendingBalance > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                            'AED ${w.pendingBalance.toStringAsFixed(2)} pending clearance',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ],
                      const SizedBox(height: 8),
                      Text(
                          'Lifetime earned AED ${w.lifetimeEarnings.toStringAsFixed(0)} · '
                          'paid out AED ${w.lifetimePaidOut.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _stat('Completed', '$completed',
                            Icons.check_circle_outline)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _stat(
                            'Lifetime earned',
                            'AED ${w.lifetimeEarnings.toStringAsFixed(0)}',
                            Icons.payments_outlined)),
                  ],
                ),
                const SizedBox(height: 18),
                const Text('Transactions',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                _filterChips(),
                const SizedBox(height: 8),
                Builder(builder: (_) {
                  final shown = _applyFilter(txns);
                  if (shown.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: _txFilter == 'pending'
                              ? 'Nothing pending'
                              : 'No transactions yet',
                          subtitle: _txFilter == 'pending'
                              ? 'Earnings awaiting clearance will show here.'
                              : 'Earnings appear here as bookings complete.'),
                    );
                  }
                  return Column(children: shown.map(_txnRow).toList());
                }),
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
                    TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );

  List<WalletTransaction> _applyFilter(List<WalletTransaction> txns) {
    switch (_txFilter) {
      case 'pending':
        return txns.where((t) => t.isPendingClearance).toList();
      case 'settled':
        return txns
            .where((t) => t.status == 'completed' || t.status == 'reversed')
            .toList();
      default:
        return txns;
    }
  }

  Widget _filterChips() {
    const opts = [
      ('settled', 'Settled'),
      ('pending', 'Pending'),
      ('all', 'All'),
    ];
    return Row(
      children: [
        for (final (val, label) in opts) ...[
          GestureDetector(
            onTap: () => setState(() => _txFilter = val),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _txFilter == val ? AppColors.brand600 : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _txFilter == val
                        ? AppColors.brand600
                        : AppColors.border),
              ),
              child: Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _txFilter == val
                          ? Colors.white
                          : AppColors.textMuted)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _txnRow(WalletTransaction t) {
    final credit = t.isCredit;
    final color = credit ? AppColors.brand600 : AppColors.rose;
    final title = t.description.isNotEmpty
        ? t.description
        : t.type.replaceAll('_', ' ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                credit ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: color,
                size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    title.isEmpty
                        ? 'Transaction'
                        : '${title[0].toUpperCase()}${title.substring(1)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                Text(
                    [
                      if (t.bookingRef != null) '#${t.bookingRef}',
                      if (t.createdAt != null)
                        DateFormat('d MMM y').format(t.createdAt!),
                      if (t.isPendingClearance) 'Pending clearance',
                      if (t.isReversed) 'Reversed',
                      if (t.commissionAmount != null && t.commissionAmount! > 0)
                        'CNC AED ${t.commissionAmount!.toStringAsFixed(0)}',
                    ].where((s) => s.isNotEmpty).join(' · '),
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                  '${credit ? '+' : '−'} AED ${t.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      decoration: t.isReversed
                          ? TextDecoration.lineThrough
                          : null)),
              if (t.balanceAfter > 0)
                Text('Bal ${t.balanceAfter.toStringAsFixed(0)}',
                    style: TextStyle(
                        color: AppColors.textFaint, fontSize: 10.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Earn {
  final WalletStatement statement;
  final List<PartnerBooking> bookings;
  _Earn({required this.statement, required this.bookings});
}
