import 'package:flutter_test/flutter_test.dart';
import 'package:cnc_partner/features/partner/partner_models.dart';

void main() {
  group('WalletInfo', () {
    test('reads heldBalance and frozen status', () {
      final w = WalletInfo.fromJson({
        'balance': '120.50',
        'pendingBalance': 10,
        'heldBalance': '75.25',
        'lifetimeEarnings': 900,
        'lifetimePaidOut': 300,
        'status': 'frozen',
        'frozenReason': 'under review',
      });
      expect(w.balance, 120.50);
      expect(w.heldBalance, 75.25);
      expect(w.isFrozen, isTrue);
      expect(w.frozenReason, 'under review');
    });

    test('defaults to active when status is absent', () {
      final w = WalletInfo.fromJson({'balance': 5});
      expect(w.isFrozen, isFalse);
      expect(w.heldBalance, 0);
    });
  });

  group('PartnerCashRequest', () {
    test('parses a pending withdraw row', () {
      final r = PartnerCashRequest.fromJson({
        'id': 42,
        'type': 'withdraw',
        'amount': '250.00',
        'status': 'pending',
        'bankName': 'Emirates NBD',
        'bankAccountNumber': '1234567890',
        'createdAt': '2026-07-10T08:00:00.000Z',
      });
      expect(r.id, 42);
      expect(r.amount, 250.0);
      expect(r.isWithdraw, isTrue);
      expect(r.isPending, isTrue);
      expect(r.canCancel, isTrue);
      expect(r.currency, 'AED');
      expect(r.createdAt, isNotNull);
    });

    test('a decided request cannot be cancelled', () {
      for (final s in ['approved', 'rejected', 'cancelled']) {
        final r = PartnerCashRequest.fromJson({'id': 1, 'status': s});
        expect(r.canCancel, isFalse, reason: 'status=$s');
      }
    });
  });
}
