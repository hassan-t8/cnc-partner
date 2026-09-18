import 'package:cnc_partner/features/partner/partner_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which name identifies a partner.
///
/// The web's profile page shows `partner.partnerName` — the BUSINESS. The
/// app's Profile hub was showing the account holder's own name from the JWT,
/// so the same person saw "Ahmed Khan" in the app and "Gulf Shine Services" on
/// the web, with nothing on either to say which was which.
void main() {
  group('Partner.name', () {
    test('is partnerName — the same field the web reads', () {
      final p = Partner.fromJson({
        'id': 4,
        'partnerName': 'Gulf Shine Services',
      });
      expect(p.name, 'Gulf Shine Services');
    });

    test('falls back to the legacy column', () {
      // The partner table was renamed in place and older rows kept `name`.
      final p = Partner.fromJson({'id': 5, 'name': 'Old Partner Co'});
      expect(p.name, 'Old Partner Co');
    });

    test('partnerName wins when a row carries both', () {
      final p = Partner.fromJson({
        'id': 6,
        'partnerName': 'Current Ltd',
        'name': 'Stale Ltd',
      });
      expect(p.name, 'Current Ltd');
    });

    test('email follows the same pair', () {
      expect(
        Partner.fromJson({'id': 1, 'partnerEmail': 'ops@gulf.ae'}).email,
        'ops@gulf.ae',
      );
      expect(
        Partner.fromJson({'id': 1, 'email': 'legacy@gulf.ae'}).email,
        'legacy@gulf.ae',
      );
    });

    test('a partner with no name at all is empty, not "null"', () {
      // The header falls back to the account holder in this case; a literal
      // "null" across the top of Profile is the thing to avoid.
      expect(Partner.fromJson({'id': 7}).name, isEmpty);
    });
  });
}
