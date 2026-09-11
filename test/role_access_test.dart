// Who may enter what — the rules the whole portal hangs off.
//
// These mirror `Carencleanss_Partner/src/lib/auth.ts`, which is the canonical
// statement of them: canEnter() for the areas, landingForUser() for where a
// login lands. The app had no test for any of it, and role bugs do not look
// like bugs — they look like "that worker can't sign in", reported once, by
// one person, weeks later.

import 'package:flutter_test/flutter_test.dart';

import 'package:cnc_partner/core/auth/jwt_user.dart';

JwtUser user(String role, {List<String> workerRoles = const []}) =>
    JwtUser(id: 1, role: role, workerRoles: workerRoles);

void main() {
  group('role predicates match the portal', () {
    test('a partner is a partner and nothing else', () {
      final u = user('partner');
      expect(u.isPartner, isTrue);
      expect(u.isDriver, isFalse);
      expect(u.isCrew, isFalse);
      expect(u.areas, [RoleArea.partner]);
    });

    test('the dedicated driver role counts as a driver', () {
      final u = user('driver');
      expect(u.isDriver, isTrue);
      expect(u.isPartner, isFalse);
      expect(u.areas, contains(RoleArea.driver));
    });

    test('a legacy worker carrying driver in workerRoles is also a driver', () {
      // The split moved drivers to their own role; pre-split rows still say
      // worker. Neither may be locked out.
      final u = user('worker', workerRoles: ['driver']);
      expect(u.isDriver, isTrue);
      expect(u.isCrew, isFalse);
    });

    test('crew requires the worker role AND the crew entry', () {
      expect(user('worker', workerRoles: ['crew']).isCrew, isTrue);
      // A driver-only worker is not crew.
      expect(user('worker', workerRoles: ['driver']).isCrew, isFalse);
      // And the crew entry alone does not make a partner into crew.
      expect(user('partner', workerRoles: ['crew']).isCrew, isFalse);
    });

    test('someone can be both driver and crew', () {
      final u = user('worker', workerRoles: ['crew', 'driver']);
      expect(u.isDriver, isTrue);
      expect(u.isCrew, isTrue);
      expect(u.areas, containsAll([RoleArea.driver, RoleArea.crew]));
      expect(u.roleLabel, 'Driver · Crew');
    });
  });

  group('a worker whose roles are unknown is not locked out', () {
    // THE BUG THIS GUARDS. tryParse rejects a token whose `areas` is empty,
    // treating it as an unrecognised role — so a worker whose token carried no
    // workerRoles was refused at the door entirely. The portal deliberately
    // does the opposite: landingForUser() sends exactly that user to /crew
    // "so they at least land somewhere useful instead of /unauthorized".
    final u = user('worker');

    test('they get the crew area', () {
      expect(u.areas, contains(RoleArea.crew));
      expect(u.areas, isNotEmpty);
    });

    test('and they land on crew, as the portal does', () {
      expect(u.landingArea, RoleArea.crew);
    });

    test('so landing and permission agree', () {
      // The contradiction that started this: landingArea said crew while
      // canEnter(crew) said no.
      expect(u.canEnter(u.landingArea), isTrue);
    });
  });

  group('landing area mirrors landingForUser', () {
    test('partner lands on the partner area', () {
      expect(user('partner').landingArea, RoleArea.partner);
    });
    test('driver lands on the driver area', () {
      expect(user('driver').landingArea, RoleArea.driver);
    });
    test('crew lands on crew', () {
      expect(user('worker', workerRoles: ['crew']).landingArea, RoleArea.crew);
    });
    test('a driver-capable worker lands on driver, not crew', () {
      expect(user('worker', workerRoles: ['driver']).landingArea,
          RoleArea.driver);
    });
  });

  group('an unacceptable role is refused', () {
    // isAcceptableRole(): the portal takes partner, worker and driver. Admins
    // and agents belong in the CRM; customers use the app.
    for (final r in ['admin', 'agent', 'customer', '']) {
      test('"$r" gets no areas, so tryParse rejects the token', () {
        expect(user(r).areas, isEmpty);
      });
    }
  });

  group('every user can enter the area they land in', () {
    // The invariant the whole thing rests on. If this fails for any role, that
    // role signs in and is bounced.
    final all = [
      user('partner'),
      user('driver'),
      user('worker', workerRoles: ['crew']),
      user('worker', workerRoles: ['driver']),
      user('worker', workerRoles: ['crew', 'driver']),
      user('worker'),
    ];
    for (final u in all) {
      test('${u.role}/${u.workerRoles} lands somewhere it may enter', () {
        expect(u.canEnter(u.landingArea), isTrue,
            reason: 'lands on ${u.landingArea} but cannot enter it');
      });
    }
  });
}
