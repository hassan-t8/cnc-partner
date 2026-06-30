import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Confirm self-unassign with the booking details, a penalty note, and a
/// reason (max 500 chars). Returns the reason (may be empty) when confirmed,
/// or null if cancelled. Mirrors the web's UnassignConfirmModal.
Future<String?> showUnassignSheet(
  BuildContext context, {
  required String bookingRef,
  String? customerName,
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
        child: SingleChildScrollView(
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
                const Text('Unassign yourself from this booking?',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    'We\'ll release this booking back to dispatch and try to '
                    're-offer it to another partner immediately.',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 14),
                // Details
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      _row('Booking', bookingRef),
                      if ((customerName ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _row('Customer', customerName!),
                      ],
                      const SizedBox(height: 8),
                      _row('Partner cost',
                          'AED ${partnerCost.toStringAsFixed(2)}'),
                      if (hasPenalty) ...[
                        const SizedBox(height: 8),
                        _row('Penalty', 'AED ${aed.toStringAsFixed(2)}',
                            valueColor: AppColors.rose),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 15, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'A penalty may be applied as per your partner contract.',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    hintText: 'e.g. Worker unavailable / vehicle breakdown',
                    helperText: 'Visible to the CNC admin',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
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
                          onPressed: () =>
                              Navigator.pop(ctx, reason.text.trim()),
                          child: const Text('Unassign'),
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
    ),
  );
}

Widget _row(String label, String value, {Color? valueColor}) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: valueColor)),
        ),
      ],
    );
