import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';

/// Cash submitted this session that is still waiting for an admin.
///
/// Since the 2026-09-23 cash-approval gate a submission leaves the booking
/// untouched: `cashCollected` stays false and `remainingAmount` still counts
/// the full due (it sums APPROVED payments only). A refetch therefore brings
/// the Collect button straight back, and the server does NOT dedupe — in
/// pending mode every submission becomes its own pending BookingPayment row
/// (cashCollection.js, "NEVER reuse an existing pending row"). A second tap
/// files a second claim for the same cash that an admin then has to reject.
///
/// The partner bookings API exposes nothing that says a cash payment is
/// pending (its `payments` include has no method column), so the app
/// remembers its own submissions: booking id → the cash due at the moment it
/// was submitted. The memory lapses by itself once the due moves (an admin
/// approved a part of it) or the booking stops owing cash (approved in full).
/// A rejection moves nothing, which is why the guard offers "Submit again"
/// behind a confirmation instead of hiding Collect outright.
final cashSubmittedProvider =
    StateProvider<Map<int, double>>((ref) => const {});

/// True while [bookingId] has a submission from this session that the server
/// has not acted on yet, judged by its cash due being unchanged.
///
/// [bookingId] is the BOOKING id (not a crew assignment id), so a submission
/// made from the partner screens and one made from the crew screens guard
/// each other. A null id (an assignment missing its booking reference) is
/// never awaiting.
bool isCashAwaitingApproval(
    Map<int, double> submitted, int? bookingId, double cashDue) {
  if (bookingId == null) return false;
  final at = submitted[bookingId];
  return at != null && (at - cashDue).abs() < 0.005;
}

/// Records a pending-approval submission of [bookingId] at [cashDue].
void rememberCashSubmitted(WidgetRef ref, int bookingId, double cashDue) {
  final n = ref.read(cashSubmittedProvider.notifier);
  n.state = {...n.state, bookingId: cashDue};
}

/// The notice shown in place of "Collect AED … cash" while a submission is
/// awaiting approval.
String cashAwaitingApprovalNote(double cashDue) =>
    'AED ${cashDue.toStringAsFixed(2)} cash submitted — waiting for an admin '
    'to approve it. Complete unlocks once it is approved.';

/// Confirms a second submission for cash already sent for approval.
Future<bool> confirmCashResubmit(BuildContext context, double cashDue) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Already submitted'),
      content: Text(
        'You already submitted AED ${cashDue.toStringAsFixed(2)} for this '
        'booking and it is waiting for an admin. Submit again only if the '
        'admin rejected it — otherwise it is counted twice.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: AppColors.amber),
          child: const Text('Submit again'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
