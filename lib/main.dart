import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/notifications/notification_service.dart';
import 'core/notifications/push_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppColors.applyBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness);
  NotificationService.instance.init();

  // Firebase / FCM. Reads the native config (google-services.json /
  // GoogleService-Info.plist) — added by the app owner. If those files aren't
  // present yet the init throws; we swallow it so the app still runs in dev.
  try {
    await Firebase.initializeApp();
    // BACKGROUND / TERMINATED delivery: a top-level handler must be registered
    // before runApp so FCM can wake a background isolate.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushService.instance.init();
  } catch (e) {
    if (kDebugMode) debugPrint('[push] Firebase init skipped: $e');
  }

  // Share one ProviderContainer between the widget tree and PushService so the
  // (non-widget) push service can read auth/api/router providers.
  final container = ProviderContainer();
  PushService.instance.attachContainer(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const CncPartnerApp(),
    ),
  );
}

class CncPartnerApp extends ConsumerStatefulWidget {
  const CncPartnerApp({super.key});
  @override
  ConsumerState<CncPartnerApp> createState() => _CncPartnerAppState();
}

class _CncPartnerAppState extends ConsumerState<CncPartnerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame the router is mounted → handle a TERMINATED/COLD
    // launch that came from tapping a notification. (Permission is asked AFTER
    // login, below.)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PushService.instance.processInitialMessage();
    });
    // On login (or biometric restore / restored session): ask for notification
    // permission, then generate the FCM token, print it, and register it with
    // the backend. Runs on every transition into the authenticated state.
    ref.listenManual(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        () async {
          await PushService.instance.requestPermission();
          await PushService.instance.registerToken();
        }();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-validate the token whenever the app returns to the foreground.
    if (state == AppLifecycleState.resumed) {
      ref.read(authControllerProvider.notifier).revalidate();
    }
  }

  @override
  void didChangePlatformBrightness() {
    // Swap the palette + rebuild when the system theme changes.
    AppColors.applyBrightness(
        WidgetsBinding.instance.platformDispatcher.platformBrightness);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CNC Partner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      routerConfig: router,
    );
  }
}
