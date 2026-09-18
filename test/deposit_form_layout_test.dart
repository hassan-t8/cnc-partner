import 'package:cnc_partner/features/partner/deposit_checkout_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// How the Add-funds card form is laid out.
///
/// Every `.wpwl-group` is `display:block` at full width by default, so each
/// field takes a whole row and the form runs past the fold on a phone. Expiry
/// and CVV are both short and belong together, which is what the customer app
/// already does.
void main() {
  group('deposit form layout', () {
    test('expiry and CVV are half-width and adjacent', () {
      // Both spellings: HyperPay emits a single `expiry` group on some
      // configurations and a month/year pair on others.
      expect(kDepositFormLayoutCss, contains('.wpwl-group-expiry,'));
      expect(kDepositFormLayoutCss, contains('.wpwl-group-expiryMonth'));
      expect(kDepositFormLayoutCss, contains('.wpwl-group-cvv,'));
      expect(kDepositFormLayoutCss, contains('.wpwl-group-expiryYear'));
      // 48 + 4 + 48 = 100.
      expect('48%'.allMatches(kDepositFormLayoutCss).length, 2);
      expect(kDepositFormLayoutCss, contains('margin-right: 4%'));
    });

    test('the pair is ORDERED, not floated', () {
      // A float pair only sits together when nothing is rendered between
      // them, and HyperPay does not emit these groups in a fixed order across
      // configurations. Explicit ordering puts them side by side wherever the
      // widget chose to place them.
      expect(kDepositFormLayoutCss, contains('display: flex'));
      expect(kDepositFormLayoutCss, contains('flex-wrap: wrap'));
      for (final o in ['order: 1', 'order: 2', 'order: 3', 'order: 4']) {
        expect(kDepositFormLayoutCss, contains(o));
      }
      // Expiry before CVV, so the row reads in the order a card is printed.
      expect(
        kDepositFormLayoutCss.indexOf('.wpwl-group-expiry,'),
        lessThan(kDepositFormLayoutCss.indexOf('.wpwl-group-cvv,')),
      );
    });

    test('the long fields keep a row of their own', () {
      // A card number squeezed to half width is unreadable, and the holder
      // name is the longest thing on the form.
      expect(
        kDepositFormLayoutCss,
        contains(
          '.wpwl-group-cardNumber, .wpwl-group-brand, .wpwl-group-cardHolder '
          '{ width: 100% !important; }',
        ),
      );
    });

    test('anything unlisted still gets a full row', () {
      // The widget emits groups this file has never heard of depending on
      // brand and configuration; they must not collapse to half width.
      expect(kDepositFormLayoutCss, contains('.wpwl-form > * { width: 100%; }'));
    });

    test('the pay button stays last', () {
      // Ordering the fields means the submit group needs an order too, or it
      // can float up between them.
      expect(kDepositFormLayoutCss,
          contains('.wpwl-group-submit, .wpwl-button-pay { order: 9'));
    });
  });
}
