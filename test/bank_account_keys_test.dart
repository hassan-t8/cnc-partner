import 'package:cnc_partner/features/partner/partner_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which key the IBAN arrives under, and what survives a save.
///
/// 2026-09-23 the backend made `iban` canonical and kept `ibanNumber` as the
/// legacy key (Partner.js). Its normaliser mirrors ibanNumber → iban when
/// iban is empty and deliberately NOT the reverse, "so any old reader still
/// finds a value under the old key too".
///
/// This app was that old reader. It read `ibanNumber` only, so a partner
/// whose bank row had been written by the web — where only `iban` is set —
/// showed a blank IBAN. And it POSTs the whole bank array back, so any key
/// it did not carry was deleted on the partner's next save.

void main() {
  group('Reading an IBAN', () {
    test('a row written by the web, canonical key only', () {
      // THE BUG. This row read as a blank IBAN before.
      final b = BankAccount.fromJson({'iban': 'AE070331234567890123456'});
      expect(b.ibanNumber, 'AE070331234567890123456');
    });

    test('a legacy row, old key only', () {
      final b = BankAccount.fromJson({'ibanNumber': 'AE999'});
      expect(b.ibanNumber, 'AE999');
    });

    test('a normalised row carrying both — canonical wins', () {
      // The backend mirrors old → new, so both are present and equal in
      // practice. If they ever disagree, the canonical key is the one every
      // other consumer reads.
      final b = BankAccount.fromJson({
        'iban': 'AE_NEW',
        'ibanNumber': 'AE_OLD',
      });
      expect(b.ibanNumber, 'AE_NEW');
    });

    test('an empty canonical key falls through to the legacy one', () {
      // Not the same as absent: an empty string must not win over a real
      // value sitting under the old key.
      final b = BankAccount.fromJson({'iban': '', 'ibanNumber': 'AE_OLD'});
      expect(b.ibanNumber, 'AE_OLD');
    });
  });

  group('Writing a bank row', () {
    test('sends both keys, so no consumer is left stale', () {
      // The backend fills `iban` from `ibanNumber` but never the reverse.
      // Sending only the legacy key would leave the canonical one stale for
      // the settlement CSV, payment slips and admin display.
      final j = const BankAccount(ibanNumber: 'AE123').toJson();
      expect(j['iban'], 'AE123');
      expect(j['ibanNumber'], 'AE123');
    });

    test('carries the account holder name back', () {
      // The screen POSTs the whole array, so a field the app does not know
      // about is a field the partner deletes by pressing Save.
      final b = BankAccount.fromJson({
        'bankName': 'ADCB',
        'accountHolderName': 'Hassan T',
        'iban': 'AE1',
      });
      expect(b.accountHolderName, 'Hassan T');
      expect(b.toJson()['accountHolderName'], 'Hassan T');
    });
  });

  group('Emptiness', () {
    test('a row with only a holder name is still empty', () {
      // isEmpty decides whether a blank row is dropped before saving. A
      // name with no bank, account or IBAN is not an account.
      expect(const BankAccount(accountHolderName: 'X').isEmpty, isTrue);
    });

    test('an IBAN alone is enough to count', () {
      expect(const BankAccount(ibanNumber: 'AE1').isEmpty, isFalse);
    });
  });
}
