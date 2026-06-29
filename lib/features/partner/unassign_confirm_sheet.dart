import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Confirm self-unassign with a live penalty preview + optional reason.
/// Returns the reason (may be empty) when confirmed, or null if cancelled.
/// Mirrors the web's UnassignConfirmModal.
Future<String?> showUnassignSheet(
  BuildContext context, {
  required double partnerCost,
  double? penaltyPct, // null = legacy/no penalty, 0 = waived, >0 = active
}) {
  final reason = TextEditingController();
  final hasPenalty = penaltyPct != null && penaltyPct > 0;
  final aed = hasPenalty
      ? (partnerCost * penaltyPct / 100 * 100).roundToDouble() / 100
      : 0.0;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Release this booking?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                  'It goes back to dispatch and is re-offered to another partner.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const SizedBox(height: 14),
              // Penalty preview
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: hasPenalty
                      ? AppColors.rose.withValues(alpha: 0.08)
                      : AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: hasPenalty
                          ? AppColors.rose.withValues(alpha: 0.35)
                          : AppColors.border),
                ),
                child: Row(
                  children: [
                    Icon(
                        hasPenalty
                            ? Icons.account_balance_wallet_outlined
                            : Icons.check_circle_outline,
                        size: 20,
                        color:
                            hasPenalty ? AppColors.rose : AppColors.brand600),
                    const SizedBox(width: 10),
                    Expanded(
                      child: hasPenalty
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Penalty: AED ${aed.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14)),
                                Text(
                                    '${penaltyPct.toStringAsFixed(penaltyPct.truncateToDouble() == penaltyPct ? 0 : 1)}% of AED ${partnerCost.toStringAsFixed(2)} — deducted from your wallet.',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12)),
                              ],
                            )
                          : Text(
                              penaltyPct == 0
                                  ? 'No penalty — waived for your account.'
                                  : 'No penalty applies.',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reason,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.rose),
                        onPressed: () => Navigator.pop(ctx, reason.text.trim()),
                        child: const Text('Release booking'),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
