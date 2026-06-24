import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../auth/auth_controller.dart';
import '../config/env.dart';
import '../providers.dart';

/// Live booking/dispatch updates over Socket.IO (mirrors the web + customer
/// app). Joins the partner/worker's `user_<id>` room to receive
/// `bookingStatusUpdated`, and per-booking rooms for dispatch/assignment
/// changes. The exposed [int] state bumps on every event so screens can
/// `ref.listen` and refresh.
class BookingRealtime extends Notifier<int> {
  io.Socket? _socket;

  /// Booking id from the most recent event (when present).
  int? lastBookingId;

  static const _events = [
    'bookingStatusUpdated',
    'bookingDispatchStatusUpdated',
    'bookingAssignmentUpdated',
    'bookingAssignmentsBulkUpdated',
    'newBookingPopup',
  ];

  @override
  int build() {
    _connect();
    ref.onDispose(() {
      _socket?.dispose();
      _socket = null;
    });
    return 0;
  }

  Future<void> _connect() async {
    if (_socket != null) return;
    final token = await ref.read(authStorageProvider).readToken();
    if (token == null || token.isEmpty) return;
    final uid = ref.read(authControllerProvider).user?.id;

    _socket = io.io(
      Env.apiUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket!.onConnect((_) {
      if (uid != null) _socket!.emit('joinUserRoom', uid);
      debugPrint('[partner-socket] connected; joined user_$uid');
    });
    _socket!.onConnectError((e) => debugPrint('[partner-socket] connErr $e'));
    for (final e in _events) {
      _socket!.off(e);
      _socket!.on(e, (data) => _onEvent(e, data));
    }
    _socket!.connect();
  }

  void joinBooking(int bookingId) =>
      _socket?.emit('joinBookingRoom', bookingId);

  void leaveBooking(int bookingId) =>
      _socket?.emit('leaveBookingRoom', bookingId);

  void _onEvent(String name, dynamic data) {
    try {
      if (data is Map) {
        final id = data['bookingId'];
        lastBookingId =
            id is num ? id.toInt() : int.tryParse('${id ?? ''}');
      }
    } catch (_) {}
    debugPrint('[partner-socket] $name bookingId=$lastBookingId');
    state = state + 1;
  }
}

final bookingRealtimeProvider =
    NotifierProvider<BookingRealtime, int>(BookingRealtime.new);
