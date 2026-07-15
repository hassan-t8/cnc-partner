import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../widgets/reason_dialog.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/service_title.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Full request details (bottom sheet) for a dispatch offer — service, customer,
/// schedule, your earnings, and the AUTO-ASSIGNED team (workers / driver / van,
/// shown read-only like the web) — with Accept / Decline.
///
/// Returns 'accept' | 'decline' | null (dismissed).
Future<String?> showOfferDetailsSheet(
    BuildContext context, WidgetRef ref, Offer o) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _OfferDetailsSheet(offer: o, ref: ref),
  );
}

class _OfferDetailsSheet extends ConsumerStatefulWidget {
  final Offer offer;
  final WidgetRef ref;
  const _OfferDetailsSheet({required this.offer, required this.ref});
  @override
  ConsumerState<_OfferDetailsSheet> createState() => _OfferDetailsSheetState();
}

class _OfferDetailsSheetState extends ConsumerState<_OfferDetailsSheet> {
  bool _busy = false;

  Future<void> _act(bool accept) async {
    String? reason;
    if (!accept) {
      reason = await showDeclineReasonDialog(context, title: 'Decline offer');
      if (reason == null || !mounted) return;
    }
    setState(() => _busy = true);
    final repo = ref.read(partnerRepositoryProvider);
    try {
      if (accept) {
        await repo.acceptOffer(widget.offer.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineOffer(widget.offer.id,
            reason: reason!.isEmpty ? null : reason);
        AppToast.success('Declined — passed to the next partner');
      }
      if (mounted) Navigator.pop(context, accept ? 'accept' : 'decline');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offer;
    final expired =
        o.expiresAt != null && o.expiresAt!.isBefore(DateTime.now());
    final schedule = o.scheduledStart != null
        ? DateFormat('EEE d MMM y · h:mm a').format(o.scheduledStart!)
        : null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ServiceTitle(o.serviceName, titleSize: 18)),
                if (o.ref.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(o.ref,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand700)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(Icons.person_outline, 'Customer',
                        o.customerName.isEmpty ? '—' : o.customerName),
                    if ((o.customerPhone ?? '').isNotEmpty)
                      _row(Icons.call_outlined, 'Phone', o.customerPhone!,
                          onTap: () => launchUrl(
                              Uri.parse('tel:${o.customerPhone}')),
                          valueColor: AppColors.brand700),
                    if (o.address.isNotEmpty)
                      _row(Icons.place_outlined, 'Location', o.address),
                    if (schedule != null)
                      _row(Icons.schedule_outlined, 'Schedule', schedule),
                    if (o.crewRequired > 0)
                      _row(Icons.groups_outlined, 'Crew',
                          '${o.crewRequired} required'),
                    if (o.extraServiceCount > 0)
                      _row(Icons.list_alt_outlined, 'Services',
                          o.serviceNames.join(', ')),
                    _row(
                        Icons.payments_outlined,
                        'You earn',
                        'AED ${o.earnings.toStringAsFixed(2)}'
                        '${o.commissionPct != null ? '  ·  comm ${o.commissionPct!.toStringAsFixed(0)}%' : ''}',
                        valueColor: AppColors.brand700,
                        bold: true),
                    if (o.capApplied)
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_outlined,
                                size: 14, color: AppColors.emerald),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Your payout is protected at your floor for '
                                'this booking.',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.emerald,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    // Auto-assigned team (read-only — created on dispatch).
                    Text('Assigned team',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textMuted)),
                    const SizedBox(height: 8),
                    if (o.workerNames.isEmpty &&
                        o.driverName.isEmpty &&
                        o.vanName.isEmpty)
                      Text('Auto-assigned on accept.',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.textMuted))
                    else ...[
                      for (final w in o.workerNames)
                        _row(Icons.engineering_outlined, 'Worker', w),
                      if (o.driverName.isNotEmpty)
                        _row(Icons.directions_car_outlined, 'Driver',
                            o.driverName),
                      if (o.vanName.isNotEmpty)
                        _row(Icons.local_shipping_outlined, 'Van', o.vanName),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_busy || expired) ? null : () => _act(false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rose,
                        side: const BorderSide(color: AppColors.rose),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: (_busy || expired) ? null : () => _act(true),
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white))
                        : Text(expired ? 'Expired' : 'Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor, bool bold = false, VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 76,
            child: Text(label,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: valueColor)),
          ),
          if (onTap != null)
            Icon(Icons.call, size: 16, color: AppColors.brand600),
        ],
      ),
    );
    return onTap == null
        ? row
        : InkWell(onTap: onTap, child: row);
  }
}
