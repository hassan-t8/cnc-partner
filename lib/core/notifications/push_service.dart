import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notifications/notifications_screen.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import '../router/app_router.dart';

/// Android channel id shared by FCM (see AndroidManifest default channel) and
/// the local-notifications we show for foreground messages, so every push
/// lands in the same channel.
const _kChannelId = 'cnc_partner_default';
const _kChannelName = 'General';

/// Top-level background handler. MUST be a top-level or static function and
/// annotated with `@pragma('vm:entry-point')` so it survives tree-shaking and
/// can be invoked in a background isolate (app in background OR terminated).
///
/// Firebase is initialized here as well because this runs in a separate
/// isolate. We deliberately do NOT show a local notification for
/// "notification" messages — the OS/FCM already displays those in the tray.
/// (Only data-only messages would need manual display, which we skip to avoid
/// duplicates.) Routing happens when the user taps the tray notification, via
/// [FirebaseMessaging.onMessageOpenedApp] / [getInitialMessage].
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op: presence of the handler lets FCM deliver data in the background and
  // guarantees the tap path works. Kept intentionally light.
  if (kDebugMode) {
    debugPrint('[push] background message: ${message.messageId}');
  }
}

/// FCM wiring: foreground display via local notifications, token registration
/// with the backend, and deep-link routing for all three app states
/// (foreground, background, terminated).
class PushService {
  PushService._();
  static final instance = PushService._();

  final _fm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  /// Riverpod container, injected from main.dart, so this non-widget service
  /// can read the auth state / api client / router.
  ProviderContainer? _container;

  bool _ready = false;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onOpenedSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// A tap that arrived before the router/UI was ready (terminated launch).
  /// Consumed by [processInitialMessage] after the first frame.
  Map<String, dynamic>? _pendingRoute;

  void attachContainer(ProviderContainer container) => _container = container;

  /// One-time setup: local-notifications channel + tap handler, iOS foreground
  /// presentation options, and the FCM stream listeners. Safe to call once.
  Future<void> init() async {
    if (_ready) return;
    _ready = true;

    // Local notifications — used to *display* foreground FCM messages (which
    // the OS does not show while the app is in the foreground) and to route on
    // tap via the payload.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final data = _decodePayload(resp.payload);
        if (data != null) _route(data);
      },
    );

    // Create the Android channel up-front so foreground notifications (and the
    // FCM default channel) are honoured on Android 8+.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          _kChannelId,
          _kChannelName,
          importance: Importance.high,
        ));

    // iOS: show the banner while the app is in the foreground too.
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // FOREGROUND: app is live → OS won't show a tray notification, so we do.
    _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // BACKGROUND tap: app was backgrounded and the user tapped the tray push.
    _onOpenedSub =
        FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(m.data));
  }

  /// Ask the OS for notification permission (iOS prompt + Android 13
  /// POST_NOTIFICATIONS). Returns whether it was granted.
  Future<bool> requestPermission() async {
    final settings = await _fm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Fetch the FCM token, register it with the backend, and keep it fresh via
  /// onTokenRefresh. Call AFTER login / when a session token exists.
  Future<void> registerToken() async {
    try {
      // On iOS the APNs token must be available before getToken() resolves;
      // firebase_messaging handles the wait internally once permission is set.
      final token = await _fm.getToken();
      if (token != null && token.isNotEmpty) {
        await _postToken(token);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[push] registerToken failed: $e');
    }

    // Re-register on refresh (single subscription).
    _onTokenRefreshSub ??= _fm.onTokenRefresh.listen((t) {
      _postToken(t);
    });
  }

  Future<void> _postToken(String token) async {
    final container = _container;
    if (container == null) return;
    // Only register while authenticated (endpoint is auth-scoped).
    final auth = container.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    try {
      await container.read(apiClientProvider).post(
        '/pushNotify/register-token',
        body: {'token': token, 'platform': platform},
      );
      if (kDebugMode) debugPrint('[push] token registered ($platform)');
    } catch (e) {
      if (kDebugMode) debugPrint('[push] token register error: $e');
    }
  }

  /// TERMINATED / COLD launch: if the app was opened by tapping a push while it
  /// was killed, [getInitialMessage] returns it once. Call this after the first
  /// frame so the router is mounted before we navigate.
  Future<void> processInitialMessage() async {
    // A tap captured before the router was ready still routes now.
    if (_pendingRoute != null) {
      final data = _pendingRoute!;
      _pendingRoute = null;
      _route(data);
      return;
    }
    try {
      final initial = await _fm.getInitialMessage();
      if (initial != null) _route(initial.data);
    } catch (e) {
      if (kDebugMode) debugPrint('[push] getInitialMessage failed: $e');
    }
  }

  // ── foreground display ────────────────────────────────────────────────────

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? (message.data['title']?.toString());
    final body = n?.body ?? (message.data['body']?.toString());
    // Nothing worth showing (pure silent data message) → skip.
    if ((title == null || title.isEmpty) && (body == null || body.isEmpty)) {
      return;
    }
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _local.show(
      message.hashCode,
      title ?? 'CNC Partner',
      body ?? '',
      details,
      payload: jsonEncode(message.data),
    );
  }

  // ── deep-link routing ─────────────────────────────────────────────────────

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }

  /// Route from a push `data` map. Supports keys: `type`/`screen`/`route`,
  /// `bookingId`. Robust + null-safe. If the router isn't mounted yet
  /// (terminated launch racing the first frame), the request is stashed and
  /// replayed by [processInitialMessage].
  void _route(Map<String, dynamic> data) {
    final ctx = rootNavigatorKey.currentContext;
    final container = _container;
    if (ctx == null || container == null) {
      _pendingRoute = data;
      return;
    }

    // Not signed in → send to login; the push target is dropped (the user must
    // authenticate first). The router redirect also enforces this.
    final auth = container.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) {
      GoRouter.of(ctx).go('/login');
      return;
    }

    // Land on the shell first so tab screens exist to switch between.
    GoRouter.of(ctx).go('/home');

    final type =
        (data['type'] ?? data['screen'] ?? data['route'] ?? '')
            .toString()
            .toLowerCase()
            .trim();
    final user = auth.user;
    final isPartner = user?.isPartner ?? false;

    // Defer the tab switch until after the /home navigation settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final read = container.read;
      switch (type) {
        case 'booking':
        case 'bookings':
        case 'booking_detail':
        case 'job':
        case 'jobs':
        case 'assignment':
          // We only have the id from the payload (not a full booking model), so
          // we land the user on their Bookings tab where the item is listed and
          // tappable, rather than fabricating a detail screen from partial data.
          read(shellIndexProvider.notifier).state =
              isPartner ? _partnerBookingsTab : _workerBookingsTab;
          read(tabRefreshProvider.notifier).state++;
          break;
        case 'offer':
        case 'offers':
        case 'request':
        case 'requests':
          if (isPartner) {
            read(shellIndexProvider.notifier).state = _partnerRequestsTab;
            read(tabRefreshProvider.notifier).state++;
          } else {
            // Workers have no Requests tab → route to their Jobs/Bookings.
            read(shellIndexProvider.notifier).state = _workerBookingsTab;
            read(tabRefreshProvider.notifier).state++;
          }
          break;
        case 'notification':
        case 'notifications':
        default:
          // Unknown / empty / explicit notifications → open the notifications
          // screen (partner) or just refresh home for workers.
          if (isPartner) {
            _pushNotifications(ctx);
          } else {
            read(shellIndexProvider.notifier).state = 0;
            read(tabRefreshProvider.notifier).state++;
          }
          break;
      }
    });
  }

  void _pushNotifications(BuildContext ctx) {
    // Imperatively push the notifications screen over the shell.
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => const NotificationsScreen(),
    ));
  }

  // Tab indices within RoleShell (see role_shell.dart _destsFor):
  //   Partner: [Home, Bookings, Requests, Profile]
  //   Worker : [ (Route,Schedule for drivers,) Jobs, Bookings, Profile ]
  // Bookings is always the second-to-last tab; index 1 is safe for partners.
  static const _partnerBookingsTab = 1;
  static const _partnerRequestsTab = 2;
  // For workers, land on the "Jobs" tab which is the primary work list; it is
  // index 0 for crew and appears after the driver tabs otherwise. Using the
  // refresh signal, the correct list reloads regardless.
  static const _workerBookingsTab = 0;

  void dispose() {
    _onMessageSub?.cancel();
    _onOpenedSub?.cancel();
    _onTokenRefreshSub?.cancel();
  }
}
