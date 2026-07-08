import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Confirm self-unassign with the booking details, a penalty note, and a
/// reason (max 500 chars). Mirrors the web's UnassignConfirmModal.
///
/// The sheet performs the unassign ITSELF via [onSubmit]: on tap it calls
/// onSubmit(reason) which returns `(result, errorMessage)` — a null error means
/// success. While it runs the Unassign button shows a spinner and both buttons
/// disable. On success the sheet closes returning the result map (incl. the
/// applied penalty); on error it stays OPEN and shows an inline message so the
/// user can retry. Returns null if cancelled.
Future<Map<String, dynamic>?> showUnassignSheet(
  BuildContext context, {
  required String bookingRef,
  String? customerName,
  required double partnerCost,
  double? penaltyPct, // null = legacy/no penalty, 0 = waived, >0 = active
  String penaltyType = '', // 'percent' | 'fixed' | ''
  double? penaltyAmount, // flat AED when type == 'fixed'
  required Future<(Map<String, dynamic>?, String?)> Function(String reason)
      onSubmit,
}) {
  final reason = TextEditingController();
  // Fixed (flat AED) or percent-of-cost, mirroring the web UnassignConfirmModal.
  final isFixed =
      penaltyType.toLowerCase() == 'fixed' && (penaltyAmount ?? 0) > 0;
  final isPercent = !isFixed && penaltyPct != null && penaltyPct > 0;
  final hasPenalty = isFixed || isPercent;
  final aed = isFixed
      ? penaltyAmount!
      : isPercent
          ? (partnerCost * penaltyPct / 100 * 100).roundToDouble() / 100
          : 0.0;
  bool submitting = false;
  String? error;

  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    isDismissible: false, // block dismiss while a submit may be in flight
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
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
                        _row(
                            'Penalty',
                            isFixed
                                ? 'AED ${aed.toStringAsFixed(2)} (flat fee)'
                                : 'AED ${aed.toStringAsFixed(2)} (${penaltyPct!.toStringAsFixed(penaltyPct % 1 == 0 ? 0 : 1)}%)',
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
                          hasPenalty
                              ? (isFixed
                                  ? 'A flat AED ${aed.toStringAsFixed(2)} penalty is charged when you unassign an accepted booking.'
                                  : 'A penalty of ${penaltyPct!.toStringAsFixed(penaltyPct % 1 == 0 ? 0 : 1)}% of your partner cost is charged when you unassign an accepted booking.')
                              : 'A penalty may be applied as per your partner contract.',
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
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 16, color: AppColors.rose),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(error!,
                            style: TextStyle(
                                color: AppColors.rose,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed:
                              submitting ? null : () => Navigator.pop(ctx),
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
                          onPressed: submitting
                              ? null
                              : () async {
                                  setSheet(() {
                                    submitting = true;
                                    error = null;
                                  });
                                  final (res, err) =
                                      await onSubmit(reason.text.trim());
                                  if (!ctx.mounted) return;
                                  if (err == null) {
                                    // Success → close with the result map.
                                    Navigator.pop(
                                        ctx, res ?? <String, dynamic>{});
                                  } else {
                                    setSheet(() {
                                      submitting = false;
                                      error = err;
                                    });
                                  }
                                },
                          child: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2, color: Colors.white))
                              : const Text('Unassign'),
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
