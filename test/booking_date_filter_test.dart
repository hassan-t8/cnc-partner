import 'package:cnc_partner/features/partner/partner_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shape of the Bookings date-range filter.
///
/// `/booking/getPartnerBookings` builds the end of its range by APPENDING to
/// whatever string it is handed:
///
///     new Date(`${to}T23:59:59.999Z`)
///
/// A full ISO timestamp therefore produced `...T00:00:00.000T23:59:59.999Z`,
/// an Invalid Date, and the request failed with "Could not load bookings".
/// `from` on its own survived — it is parsed with a plain `new Date(from)` —
/// which is precisely why picking a start date worked and adding an end date
/// did not.
void main() {
  group('ymdParam', () {
    test('is a bare calendar day, with no time component', () {
      final s = ymdParam(DateTime(2026, 9, 18, 14, 35, 7));
      expect(s, '2026-09-18');
      // The characters that broke it. Any of these back in the string and the
      // backend's concatenation yields an Invalid Date again.
      expect(s.contains('T'), isFalse);
      expect(s.contains(':'), isFalse);
      expect(s.contains('Z'), isFalse);
      expect(s.contains('.'), isFalse);
    });

    test('pads month and day', () {
      expect(ymdParam(DateTime(2026, 1, 5)), '2026-01-05');
      expect(ymdParam(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('appending the backend suffix gives a date that parses', () {
      // What the server actually does with this value.
      final parsed = DateTime.tryParse(
          '${ymdParam(DateTime(2026, 9, 18))}T23:59:59.999Z');
      expect(parsed, isNotNull);
      expect(parsed!.toUtc().day, 18);
      // And the old value, to show what was failing.
      final broken = DateTime.tryParse(
          '${DateTime(2026, 9, 18).toIso8601String()}T23:59:59.999Z');
      expect(broken, isNull);
    });

    test('keeps the day the user picked, in their own timezone', () {
      // NOT converted to UTC first: someone choosing the 18th in Dubai must
      // not have it filed as the 17th.
      final late = DateTime(2026, 9, 18, 23, 30);
      expect(ymdParam(late), '2026-09-18');
      final early = DateTime(2026, 9, 18, 0, 30);
      expect(ymdParam(early), '2026-09-18');
    });

    test('handles a year that needs padding', () {
      expect(ymdParam(DateTime(999, 3, 4)), '0999-03-04');
    });
  });
}
