import 'package:cnc_partner/features/bookings/models.dart';
import 'package:cnc_partner/features/worker/crew_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Who is asked to collect cash, and when Complete unlocks.
///
/// The partner web changed this on 2026-09-18 and said why in its own code:
/// the Collect button "previously showed when the customer hadn't paid yet,
/// tricking the partner into thinking they should physically collect cash."
/// Card and online are settled by link, so cash due is 0 and the button
/// cannot render.
///
/// Removing the button is only half of it. That button was also what kept
/// Complete disabled, so hiding it alone would let a partner finish a job
/// nobody has paid for — the opposite failure, and the worse one.
/// `onlineUnpaid` replaces the gate it was providing by accident.

Assignment asg({
  String payment = 'cash',
  String paymentStatus = '',
  double cashDue = 250,
  bool cashCollected = false,
  double? remainingAmount,
}) =>
    Assignment(
      id: 1,
      bookingId: 10,
      payment: payment,
      paymentStatus: paymentStatus,
      cashDue: cashDue,
      cashCollected: cashCollected,
      remainingAmount: remainingAmount,
    );

/// CrewOverrides is a Riverpod Notifier, so it has to come from a container
/// rather than be constructed directly — a bare instance has no element and
/// throws on first write.
CrewOverrides _overrides() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container.read(crewOverridesProvider.notifier);
}

void main() {
  group('Cash is never collected on an online-settled booking', () {
    test('card, unpaid — no Collect button', () {
      final a = asg(payment: 'card', remainingAmount: 250);
      expect(a.cashPending, isFalse);
    });

    test('online, unpaid — no Collect button', () {
      expect(asg(payment: 'online', remainingAmount: 250).cashPending, isFalse);
    });

    test('cash, unpaid — Collect still shows, unchanged', () {
      // The whole point is that this path is untouched. Cash bookings are
      // still collected at the door.
      expect(asg(payment: 'cash').cashPending, isTrue);
    });

    test('wallet is still excluded, as before', () {
      expect(asg(payment: 'wallet').cashPending, isFalse);
    });

    test('a refund re-opens collection whatever the method', () {
      // The refund overlay sits ABOVE the method check, exactly as the web
      // has it: money went back to the customer, so it is owed again even
      // on a card booking.
      final a = asg(payment: 'card', paymentStatus: 'refunded');
      expect(a.cashPending, isTrue);
    });
  });

  group('Complete waits for an online payment', () {
    test('unpaid online blocks Complete', () {
      final a = asg(payment: 'card', remainingAmount: 250);
      expect(a.onlineUnpaid, isTrue);
      expect(a.blocksComplete, isTrue);
    });

    test('paid online does not', () {
      final a = asg(payment: 'card', paymentStatus: 'paid', cashDue: 0);
      expect(a.onlineUnpaid, isFalse);
      expect(a.blocksComplete, isFalse);
    });

    test('a zero remaining counts as paid even without the status', () {
      // The server's net remaining is the authority when it is present.
      final a = asg(payment: 'online', remainingAmount: 0);
      expect(a.onlineUnpaid, isFalse);
    });

    test('an UNKNOWN remaining counts as unpaid, not paid', () {
      // The safe direction. A feed that omits the field must not let a job
      // be completed for free; it should hold and let the server decide.
      final a = asg(payment: 'card', remainingAmount: null);
      expect(a.onlineUnpaid, isTrue);
    });

    test('a cash booking is never onlineUnpaid', () {
      expect(asg(payment: 'cash').onlineUnpaid, isFalse);
      // …but it still blocks Complete, via the cash side.
      expect(asg(payment: 'cash').blocksComplete, isTrue);
    });

    test('a hair under a fils is treated as settled', () {
      // Matches the web's `> 0.005`, so a rounding crumb does not strand a
      // finished job.
      expect(asg(payment: 'card', remainingAmount: 0.004).onlineUnpaid,
          isFalse);
    });
  });

  group('The crew override must not re-open the gate', () {
    // /booking-assignments sends no payment fields, so an Assignment built
    // from it always derives onlineUnpaid == false. The rich feed seeds the
    // answer across. Before this split, an unpaid online booking was seeded
    // as "cash collected" — which hid Collect correctly and then UNLOCKED
    // Complete on a job nobody had paid for.
    test('a bare crew row derives nothing on its own', () {
      final bare = asg(payment: '', paymentStatus: '', cashDue: 0);
      expect(bare.onlineUnpaid, isFalse);
    });

    test('the override marks it unpaid and keeps Complete shut', () {
      final ov = _overrides();
      ov.seedOnlineUnpaid([10]);
      final applied = ov.apply(asg(payment: '', cashDue: 0));
      expect(applied.onlineUnpaid, isTrue);
      expect(applied.blocksComplete, isTrue);
    });

    test('seeding collected does NOT mark anything unpaid', () {
      // The two reasons stay apart. A genuinely settled booking gets Collect
      // hidden and Complete enabled, which is the whole point of the seed.
      final ov = _overrides();
      ov.seedCollected([10]);
      final applied = ov.apply(asg(payment: 'cash'));
      expect(applied.cashCollected, isTrue);
      expect(applied.onlineUnpaid, isFalse);
      expect(applied.blocksComplete, isFalse);
    });

    test('an override can only ever say unpaid, never paid', () {
      // apply() passes null rather than false when the patch is absent, so
      // it cannot overwrite a row that worked out for itself that it is
      // unpaid. Marking something paid is the one direction that loses money.
      final ov = _overrides();
      ov.seedCollected([10]);
      final real = asg(payment: 'card', remainingAmount: 250);
      expect(ov.apply(real).onlineUnpaid, isTrue);
    });
  });
}
