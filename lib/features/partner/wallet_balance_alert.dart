import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import 'partner_repository.dart';

/// Negative-balance banner (partner-portal parity). Shows an amber "low
/// balance" warning below the warn threshold and a rose "jobs paused" block
/// below the block threshold. Pass [balance] when the host already has the
/// wallet; otherwise the widget self-fetches it (e.g. on the dashboard).
class WalletBalanceAlert extends ConsumerStatefulWidget {
  final double? balance;
  const WalletBalanceAlert({super.key, this.balance});

  @override
  ConsumerState<WalletBalanceAlert> createState() => _WalletBalanceAlertState();
}

class _WalletBalanceAlertState extends ConsumerState<WalletBalanceAlert> {
  double? _balance;
  double _warn = -1000;
  double _block = -2000;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _balance = widget.balance;
    _load();
  }

  @override
  void didUpdateWidget(covariant WalletBalanceAlert old) {
    super.didUpdateWidget(old);
    if (widget.balance != old.balance) {
      setState(() => _balance = widget.balance);
    }
  }

  Future<void> _load() async {
    final repo = ref.read(partnerRepositoryProvider);
    try {
      final t = await repo.walletThresholds();
      if (mounted) {
        setState(() {
          _warn = t.warn;
          _block = t.block;
        });
      }
    } catch (_) {}
    if (widget.balance == null) {
      try {
        final partnerId =
            ref.read(authControllerProvider).user?.partnerId ?? 0;
        final w = await repo.wallet(partnerId);
        if (mounted) setState(() => _balance = w.wallet.balance);
      } catch (_) {}
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    final b = _balance;
    // Only alert once we know the balance and it's below the warn line.
    if (!_ready || b == null || b > _warn) return const SizedBox.shrink();
    final blocked = b <= _block;
    final color = blocked ? AppColors.rose : AppColors.amber;
    final msg = blocked
        ? 'Your wallet is AED ${b.toStringAsFixed(2)}. New jobs are paused — top up to resume.'
        : 'Low wallet balance (AED ${b.toStringAsFixed(2)}). Top up to keep receiving jobs.';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(blocked ? Icons.block_rounded : Icons.warning_amber_rounded,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
