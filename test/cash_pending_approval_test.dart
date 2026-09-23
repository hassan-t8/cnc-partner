import 'package:cnc_partner/features/bookings/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the app believes after submitting cash.
///
/// 2026-09-23 the backend put every CRM and partner cash submission behind
/// admin approval (bookingController.js:8705). On that path the booking is
/// NOT flipped: `cashCollected` comes back false, no wallet debit is
/// written, and a new `pendingApproval: true` is returned alongside
/// `success: true`.
///
/// The app used to read `success` as "collected", flip its own flag and
/// tell the partner they could complete the job — which the server would
/// then refuse with CASH_NOT_COLLECTED. These pin the server's answer as
/// the only source of that belief.

Map<String, dynamic> res({
  bool cashCollected = false,
  bool pendingApproval = false,
  double collected = 100,
  String message = '',
}) =>
    {
      'success': true,
      'message': message,
      'data': {
        'cashCollected': cashCollected,
        'cashDue': 0,
        'isPartial': false,
        'collectedAmount': collected,
        'pendingApproval': pendingApproval,
      },
    };

void main() {
  group('A submission awaiting approval', () {
    test('is not collected, however successful the call was', () {
      // THE BUG. success:true with cashCollected:false is the new normal,
      // and the old code read only the first half.
      final r = CashCollectResult.fromJson(res(
        cashCollected: false,
        pendingApproval: true,
        message: 'Cash payment (AED 100.00) submitted for admin approval.',
      ));
      expect(r.pendingApproval, isTrue);
      expect(r.cashCollected, isFalse);
    });

    test('carries the server message, which says what really happened', () {
      // Shown to the partner as-is. It names the amount and the fact that
      // an admin has to approve it — nothing written here could be more
      // accurate than the sentence the server sent.
      final r = CashCollectResult.fromJson(res(
        pendingApproval: true,
        message: 'Cash payment (AED 100.00) submitted for admin approval.',
      ));
      expect(r.message, contains('submitted for admin approval'));
    });
  });

  group('An approved or auto-approved collection', () {
    test('reports collected, and only then', () {
      // The internal auto-mark path (customer already paid online) still
      // self-approves, so this shape has not gone away.
      final r = CashCollectResult.fromJson(
          res(cashCollected: true, pendingApproval: false));
      expect(r.cashCollected, isTrue);
      expect(r.pendingApproval, isFalse);
    });
  });

  group('Older servers', () {
    test('a response with no pendingApproval key is not pending', () {
      // The field is additive. A backend that predates the gate omits it,
      // and its `cashCollected: true` is the whole answer — defaulting to
      // pending there would block completion on a booking that is settled.
      final r = CashCollectResult.fromJson({
        'success': true,
        'data': {'cashCollected': true, 'cashDue': 0},
      });
      expect(r.pendingApproval, isFalse);
      expect(r.cashCollected, isTrue);
    });
  });
}
