import 'package:flutter_test/flutter_test.dart';
import 'package:cnc_partner/features/bookings/models.dart';

/// Web parity: BookingDetailModal.tsx parseContactPersons (2026-10-08).
void main() {
  group('ContactPerson.listFrom', () {
    test('parses an array, trims, and drops empty entries', () {
      final list = ContactPerson.listFrom([
        {'name': ' Sara ', 'role': 'Facilities', 'phone': '+971 50 1', 'email': ''},
        {'name': '', 'role': 'Only a role', 'phone': '', 'email': ''},
        'not a map',
        {'email': 'ops@acme.ae'},
      ]);
      expect(list.length, 2);
      expect(list[0].name, 'Sara');
      expect(list[0].role, 'Facilities');
      expect(list[0].phone, '+971 50 1');
      expect(list[1].name, '');
      expect(list[1].email, 'ops@acme.ae');
    });

    test('parses a JSON string; malformed or non-array → empty', () {
      expect(
          ContactPerson.listFrom('[{"name":"Ali","phone":"050"}]').single.name,
          'Ali');
      expect(ContactPerson.listFrom('{oops'), isEmpty);
      expect(ContactPerson.listFrom({'name': 'Ali'}), isEmpty);
      expect(ContactPerson.listFrom(null), isEmpty);
    });
  });

  test('PartnerBooking reads the corporate snapshot and keeps it on copyWith',
      () {
    final b = PartnerBooking.fromJson({
      'id': 1,
      'dispatchStatus': 'accepted',
      'bookingType': 'corporate',
      'companyName': 'Acme LLC',
      'contactPersons': [
        {'name': 'Sara', 'phone': '050'},
      ],
    });
    expect(b.isCorporate, isTrue);
    expect(b.companyName, 'Acme LLC');
    expect(b.contactPersons.single.name, 'Sara');
    final c = b.copyWith(status: 'in_progress');
    expect(c.isCorporate, isTrue);
    expect(c.contactPersons.single.phone, '050');
    expect(PartnerBooking.fromJson({'id': 2}).isCorporate, isFalse);
  });
}
