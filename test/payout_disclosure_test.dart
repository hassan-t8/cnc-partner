import 'package:cnc_partner/features/bookings/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the booking detail screen TELLS a partner about their money.
///
/// Both of these are sentences shown to a partner about their own earnings, so
/// being wrong here is worse than being absent — the partner reads a specific
/// figure or a specific promise and has no way to check it.
void main() {
  PartnerBooking parse(Map<String, dynamic> extra) =>
      PartnerBooking.fromJson({'id': 1, ...extra});

  group('the CNC service fee stated to the partner', () {
    // 2026-09-11 the backend split the fee: `serviceFeeAmount` stopped meaning
    // incl-VAT and became the ex-VAT slice, with the VAT in `serviceFeeVat`.
    // The screen says "the customer paid this extra to CNC", so the raw column
    // states an amount the customer did not pay.
    test('the split shape adds the two columns', () {
      final b = parse({'serviceFeeAmount': 10.0, 'serviceFeeVat': 0.5});
      expect(b.hasSplitFee, isTrue);
      expect(b.serviceFeeInclVat, 10.5);
    });

    test('a legacy row already holds the whole fee', () {
      final b = parse({'serviceFeeAmount': 10.5});
      expect(b.hasSplitFee, isFalse);
      expect(b.serviceFeeInclVat, 10.5);
    });

    test('a genuinely zero VAT is still the split shape', () {
      // NULL marks a legacy row; 0.00 is a fee whose rule charges no VAT.
      final b = parse({'serviceFeeAmount': 10.0, 'serviceFeeVat': 0.0});
      expect(b.hasSplitFee, isTrue);
      expect(b.serviceFeeInclVat, 10.0);
    });

    test('no fee means nothing is shown', () {
      expect(parse({}).serviceFeeInclVat, 0);
    });
  });

  group('the cap-protection promise', () {
    // "your payout is protected at your guaranteed floor" must not appear over
    // the top of a payout that is below that floor. When an admin fixes a
    // partner cost by hand, settlement replaces the payout but deliberately
    // leaves capApplied and partnerFloor at their commission-derived values,
    // so the two stop describing the same number.
    test('holds on an ordinary capped booking', () {
      final b = parse({
        'capApplied': true,
        'partnerFloor': 100.0,
        'partnerNet': 100.0,
      });
      expect(b.capProtectionHolds, isTrue);
    });

    test('does not hold once an admin has set the cost', () {
      final b = parse({
        'capApplied': true,
        'partnerFloor': 100.0,
        'partnerNet': 80.0,
        'partnerCostIsAdminOverride': true,
      });
      expect(b.partnerCostIsAdminOverride, isTrue);
      expect(b.capProtectionHolds, isFalse);
    });

    test('does not hold when the payout sits below the floor either way', () {
      // Belt and braces: even without the flag, promising protection over a
      // number below the floor is the thing worth refusing to print.
      final b = parse({
        'capApplied': true,
        'partnerFloor': 100.0,
        'partnerNet': 80.0,
      });
      expect(b.capProtectionHolds, isFalse);
    });

    test('a rounding-width shortfall still counts as protected', () {
      final b = parse({
        'capApplied': true,
        'partnerFloor': 100.0,
        'partnerNet': 99.999,
      });
      expect(b.capProtectionHolds, isTrue);
    });

    test('nothing is claimed when the cap never applied', () {
      expect(parse({'partnerNet': 100.0}).capProtectionHolds, isFalse);
    });
  });

  group('the admin-override flag', () {
    test('is read from the booking column', () {
      expect(
        parse({'partnerCostIsAdminOverride': true}).partnerCostIsAdminOverride,
        isTrue,
      );
    });

    test('is also read from the settlement helper\'s source', () {
      // The two endpoints do not both carry the column; `source` says the
      // same thing the other way.
      expect(
        parse({'source': 'admin_override'}).partnerCostIsAdminOverride,
        isTrue,
      );
      expect(
        parse({'source': 'commission'}).partnerCostIsAdminOverride,
        isFalse,
      );
    });

    test('defaults to false', () {
      expect(parse({}).partnerCostIsAdminOverride, isFalse);
    });
  });
}
