import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../network/api_client.dart';
import '../providers.dart';
import 'notification_service.dart';

class AppNotification {
  final int id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final String ctaUrl;

  const AppNotification({
    required this.id,
    this.title = '',
    this.message = '',
    this.type = '',
    this.isRead = false,
    this.createdAt,
    this.ctaUrl = '',
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
        ctaUrl: ctaUrl,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    final data = j['data'] is Map ? Map<String, dynamic>.from(j['data']) : const {};
    return AppNotification(
      id: int.tryParse('${j['id']}') ?? 0,
      title: '${j['title'] ?? ''}',
      message: '${j['message'] ?? ''}',
      type: '${j['type'] ?? ''}',
      isRead: j['isRead'] == true,
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
      ctaUrl: '${data['ctaUrl'] ?? ''}',
    );
  }

  /// Which app section this notification points to.
  String get target {
    if (type == 'tip') return 'bookings';
    if (type.startsWith('dispatch')) return 'requests';
    if (type.startsWith('booking')) return 'bookings';
    if (type.startsWith('payment')) return 'earnings';
    return 'requests';
  }
}

class NotifState {
  final List<AppNotification> items;
  final bool loading;

  /// More rows exist on the server than are currently held.
  final bool hasMore;

  /// A "load older" fetch is in flight.
  final bool loadingMore;

  const NotifState({
    this.items = const [],
    this.loading = false,
    this.hasMore = false,
    this.loadingMore = false,
  });

  int get unread => items.where((n) => !n.isRead).length;

  NotifState copyWith({
    List<AppNotification>? items,
    bool? loading,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      NotifState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

final notificationsProvider =
    NotifierProvider<NotificationsController, NotifState>(
        NotificationsController.new);

class NotificationsController extends Notifier<NotifState> {
  Timer? _timer;
  int _lastMaxId = 0;
  bool _first = true;

  static const _pageSize = 30;

  /// The backend caps `limit` at 200. Rather than merge appended pages with the
  /// 45s replace-poll (fiddly, and the client-side filter reads the whole
  /// in-memory list), we simply grow the fetch window: "load older" widens
  /// [_limit] by a page and the poll keeps re-fetching everything currently
  /// shown, newest-first. 200 / 30 ≈ 6 pages, which is plenty for a bell.
  static const _maxLimit = 200;
  int _limit = _pageSize;

  @override
  NotifState build() {
    ref.onDispose(() => _timer?.cancel());
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 45), (_) => _fetch());
    // Kick off the first fetch after the current build completes.
    Future.microtask(_fetch);
    return const NotifState(loading: true);
  }

  Future<void> refresh() => _fetch();

  /// Widen the window by one page and re-fetch. No-op at the cap or when
  /// nothing more exists.
  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore) return;
    if (_limit >= _maxLimit) return;
    _limit = (_limit + _pageSize).clamp(_pageSize, _maxLimit);
    state = state.copyWith(loadingMore: true);
    await _fetch();
  }

  Future<void> _fetch() async {
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) return;
    try {
      final res = await ref
          .read(apiClientProvider)
          .get('/notification', query: {'limit': _limit});
      final items = pickList(res.data)
          .map(AppNotification.fromJson)
          .toList()
        ..sort((a, b) => b.id.compareTo(a.id));

      // hasMore: prefer the server's total; fall back to "we filled the window".
      final body = res.data;
      final pg = (body is Map && body['pagination'] is Map)
          ? Map<String, dynamic>.from(body['pagination'] as Map)
          : const {};
      final total = pg['totalRecords'];
      final hasMore = total is num
          ? items.length < total.toInt()
          : items.length >= _limit;
      // Surface a system notification for genuinely new unread arrivals. When
      // several land in the same poll (a burst), collapse them into one
      // "N new notifications" summary instead of surfacing only the first —
      // which silently dropped the rest.
      if (!_first) {
        final fresh = items
            .where((n) => n.id > _lastMaxId && !n.isRead)
            .toList();
        if (fresh.length == 1) {
          final n = fresh.first;
          NotificationService.instance.show(
              n.title.isEmpty ? 'New notification' : n.title, n.message);
        } else if (fresh.length > 1) {
          // fresh is sorted newest-first (items is id-desc); preview the
          // latest message so the summary still hints at what arrived.
          final latest = fresh.first;
          final preview = latest.message.isNotEmpty
              ? latest.message
              : (latest.title.isNotEmpty ? latest.title : 'Tap to view');
          NotificationService.instance
              .show('${fresh.length} new notifications', preview);
        }
      }
      if (items.isNotEmpty) _lastMaxId = items.first.id;
      _first = false;
      state = NotifState(items: items, hasMore: hasMore);
    } catch (_) {
      // Keep what we have; just drop any in-flight "loading older" flag.
      state = state.copyWith(loadingMore: false);
    }
  }

  /// Optimistically mark everything read, then tell the server.
  Future<void> markAllRead() async {
    if (state.unread == 0) return;
    state = state.copyWith(
        items: state.items.map((n) => n.copyWith(isRead: true)).toList());
    try {
      await ref.read(apiClientProvider).post('/notification/mark-read');
    } catch (_) {}
  }
}
