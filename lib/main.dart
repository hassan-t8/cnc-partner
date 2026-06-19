import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/auth_controller.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppColors.applyBrightness(
      WidgetsBinding.instance.platformDispatcher.platformBrightness);
  NotificationService.instance.init();
  runApp(const ProviderScope(child: CncPartnerApp()));
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
