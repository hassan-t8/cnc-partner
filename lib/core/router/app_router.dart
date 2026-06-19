import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/set_password_screen.dart';
import '../../features/shell/role_shell.dart';
import '../../features/shell/unauthorized_screen.dart';
import '../../features/splash/splash_screen.dart';

/// Bridges a Riverpod listenable into go_router's refreshListenable.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    ref.listen(authControllerProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final onAuthPages = loc == '/login' ||
          loc == '/forgot-password' ||
          loc == '/reset-password' ||
          loc == '/set-password' ||
          loc == '/splash';

      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.unauthenticated:
          return onAuthPages && loc != '/splash' ? null : '/login';
        case AuthStatus.authenticated:
          if (onAuthPages) return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/forgot-password',
          builder: (_, state) => ForgotPasswordScreen(
              initialEmail: state.uri.queryParameters['email'])),
      GoRoute(
        path: '/reset-password',
        builder: (_, st) => SetPasswordScreen(
          token: st.uri.queryParameters['token'] ?? '',
          email: st.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(
        path: '/set-password',
        builder: (_, st) => SetPasswordScreen(
          token: st.uri.queryParameters['token'] ?? '',
          email: st.uri.queryParameters['email'] ?? '',
          setup: true,
        ),
      ),
      GoRoute(path: '/home', builder: (_, __) => const RoleShell()),
      GoRoute(
          path: '/unauthorized',
          builder: (_, __) => const UnauthorizedScreen()),
    ],
  );
});
