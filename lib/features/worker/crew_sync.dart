import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bookings/models.dart';

/// One booking's optimistic state from an action the crew took this session.
class CrewPatch {
  final String? status;
  final bool? cashCollected;

  /// Settled by link and not yet paid.
  ///
  /// Distinct from [cashCollected] on purpose. Both hide the Collect button,
  /// but only this one keeps Complete shut. Folding the two together would
  /// mark an unpaid online booking as "cash collected" -- untrue, and it
  /// would unlock Complete on a job nobody has paid for.
  final bool? onlineUnpaid;

  const CrewPatch({this.status, this.cashCollected, this.onlineUnpaid});

  CrewPatch merge(CrewPatch o) => CrewPatch(
        status: o.status ?? status,
        cashCollected: o.cashCollected ?? cashCollected,
        onlineUnpaid: o.onlineUnpaid ?? onlineUnpaid,
      );
}

const _statusOrder = {
  'pending_acceptance': 0,
  'accepted': 1,
  'in_progress': 2,
  'completed': 3,
};
int _rank(String s) => _statusOrder[s] ?? -1;

/// Session-scoped source of truth that keeps the crew's Jobs / My-bookings /
/// booking-detail screens consistent.
///
/// Why this exists: the three surfaces each cache their own list, and the
/// `/booking-assignments` feed (My jobs) does NOT echo `cashCollected` back —
/// so after a refresh the "Collect AED" button reappeared and screens
/// disagreed. Every crew action writes a patch here (keyed by bookingId); every
/// screen overlays these patches on whatever the server returned, so a change
/// on one screen shows everywhere and survives a refetch.
class CrewOverrides extends Notifier<Map<int, CrewPatch>> {
  @override
  Map<int, CrewPatch> build() => {};

  void patch(int? bookingId,
      {String? status, bool? cashCollected, bool? onlineUnpaid}) {
    if (bookingId == null || bookingId <= 0) return;
    final cur = state[bookingId] ?? const CrewPatch();
    state = {
      ...state,
      bookingId: cur.merge(CrewPatch(
          status: status,
          cashCollected: cashCollected,
          onlineUnpaid: onlineUnpaid)),
    };
  }

  /// Mark several bookings as awaiting an online payment.
  ///
  /// Seeded from the rich feed like [seedCollected], and for the same reason
  /// -- the My-Jobs feed has no payment fields, so it cannot work this out
  /// for itself. The difference is what it means downstream: Collect is
  /// hidden either way, but these keep Complete disabled.
  void seedOnlineUnpaid(Iterable<int?> bookingIds) {
    final next = {...state};
    var changed = false;
    for (final id in bookingIds) {
      if (id == null || id <= 0) continue;
      final cur = next[id] ?? const CrewPatch();
      if (cur.onlineUnpaid != true) {
        next[id] = cur.merge(const CrewPatch(onlineUnpaid: true));
        changed = true;
      }
    }
    if (changed) state = next;
  }

  /// Mark several bookings cash-collected in one state update — used to seed
  /// from the /workers/me/bookings feed (which has cashCollected) so the
  /// My-Jobs feed (which doesn't) stops showing "Collect" on them.
  void seedCollected(Iterable<int?> bookingIds) {
    final next = {...state};
    var changed = false;
    for (final id in bookingIds) {
      if (id == null || id <= 0) continue;
      final cur = next[id] ?? const CrewPatch();
      if (cur.cashCollected != true) {
        next[id] = cur.merge(const CrewPatch(cashCollected: true));
        changed = true;
      }
    }
    if (changed) state = next;
  }

  /// Overlay the known patch for this assignment's booking. Status only wins
  /// when it's the same or further along than the server's (so a genuinely
  /// newer server status isn't masked); cashCollected sticks once true.
  Assignment apply(Assignment a) {
    final p = state[a.bookingId];
    if (p == null) return a;
    final useStatus =
        p.status != null && _rank(p.status!) >= _rank(a.status);
    return a.copyWith(
      status: useStatus ? p.status : a.status,
      cashCollected: p.cashCollected == true ? true : a.cashCollected,
      // Only ever set true from here. A null leaves the row's own derived
      // answer alone, so an override cannot mark something as paid.
      onlineUnpaidOverride: p.onlineUnpaid == true ? true : null,
    );
  }
}

final crewOverridesProvider =
    NotifierProvider<CrewOverrides, Map<int, CrewPatch>>(CrewOverrides.new);
