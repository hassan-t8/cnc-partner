import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/auth_controller.dart';
import '../config/env.dart';
import '../providers.dart';

/// Live booking/dispatch updates over Socket.IO.
///
/// Room model (backend `bin/www` → `io.on('connection')`):
///   * `joinUserRoom(userId)` → `user_<id>`
///   * `joinBookingRoom(id)`  → `booking_<id>`
///
/// **Important:** the backend only routes booking events to `admin_room`,
/// `booking_<id>` and the *customer's* `user_<customerId>` room. There is no
/// partner or worker room, so `user_<id>` delivers nothing booking-related to
/// this app. `booking_<id>` is therefore our only live channel — every screen
/// that shows bookings must subscribe to a room per visible booking via
/// [syncBookingRooms].
///
/// The exposed [int] state bumps on every event so screens can `ref.listen`
/// and refresh. [lastBookingId] carries the affected booking when present.
class BookingRealtime extends Notifier<int> {
  io.Socket? _socket;
  bool _connected = false;

  /// Booking id from the most recent event (when present).
  int? lastBookingId;

  /// Owner → the booking ids that owner wants live. The union is what we join,
  /// so two screens watching the same booking don't evict each other.
  final Map<Object, Set<int>> _roomSubs = {};
  Set<int> _joinedRooms = {};

  /// Bumped on every teardown. `_connect` awaits the token, so a logout can
  /// land mid-flight; the generation check stops it resurrecting a socket for
  /// the user who just signed out.
  int _gen = 0;

  static const _events = [
    'bookingStatusUpdated',
    'bookingDispatchStatusUpdated',
    'bookingAssignmentUpdated',
    'bookingAssignmentsBulkUpdated',
    'newBookingPopup',
  ];

  @override
  int build() {
    // Rebuild (and therefore reconnect) whenever the signed-in user changes —
    // this tears the socket down on logout so we never linger in the previous
    // user's rooms with a stale token.
    final uid = ref.watch(authControllerProvider.select((s) => s.user?.id));
    ref.onDispose(_teardown);
    if (uid != null) _connect(uid);
    return 0;
  }

  Future<void> _connect(int uid) async {
    if (_socket != null) return;
    final gen = _gen;
    final token = await ref.read(authStorageProvider).readToken();
    if (token == null || token.isEmpty) return;
    if (gen != _gen || _socket != null) return; // torn down while awaiting

    final socket = io.io(
      Env.apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      _connected = true;
      socket.emit('joinUserRoom', uid);
      // socket.io does not restore room membership across a reconnect.
      for (final id in _joinedRooms) {
        socket.emit('joinBookingRoom', id);
      }
      debugPrint(
          '[partner-socket] connected; user_$uid, ${_joinedRooms.length} booking rooms');
    });
    socket.onDisconnect((_) => _connected = false);
    socket.onConnectError((e) => debugPrint('[partner-socket] connErr $e'));
    for (final e in _events) {
      socket.off(e);
      socket.on(e, (data) => _onEvent(e, data));
    }
    socket.connect();
  }

  void _teardown() {
    _gen++;
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _roomSubs.clear();
    _joinedRooms = {};
    lastBookingId = null;
  }

  /// Declare the bookings [owner] wants live updates for. Call again whenever
  /// the visible list changes; call [releaseBookingRooms] in dispose.
  void syncBookingRooms(Object owner, Iterable<int> bookingIds) {
    _roomSubs[owner] = bookingIds.where((id) => id > 0).toSet();
    _reconcileRooms();
  }

  void releaseBookingRooms(Object owner) {
    if (_roomSubs.remove(owner) != null) _reconcileRooms();
  }

  /// Convenience for a single-booking screen (detail).
  void joinBooking(Object owner, int bookingId) =>
      syncBookingRooms(owner, [bookingId]);

  void _reconcileRooms() {
    final want = <int>{for (final s in _roomSubs.values) ...s};
    final sock = _socket;
    if (sock != null && _connected) {
      for (final id in want.difference(_joinedRooms)) {
        sock.emit('joinBookingRoom', id);
      }
      for (final id in _joinedRooms.difference(want)) {
        sock.emit('leaveBookingRoom', id);
      }
    }
    _joinedRooms = want;
  }

  void _onEvent(String name, dynamic data) {
    try {
      if (data is Map) {
        final id = data['bookingId'];
        lastBookingId = id is num ? id.toInt() : int.tryParse('${id ?? ''}');
      }
    } catch (_) {}
    debugPrint('[partner-socket] $name bookingId=$lastBookingId');
    state = state + 1;
  }
}

final bookingRealtimeProvider =
    NotifierProvider<BookingRealtime, int>(BookingRealtime.new);
