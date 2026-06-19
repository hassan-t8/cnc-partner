import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../storage/auth_storage.dart';
import 'auth_repository.dart';
import 'jwt_user.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final JwtUser? user;
  const AuthState(this.status, [this.user]);

  static const unknown = AuthState(AuthStatus.unknown);
  static const signedOut = AuthState(AuthStatus.unauthenticated);
  factory AuthState.signedIn(JwtUser u) =>
      AuthState(AuthStatus.authenticated, u);
}

final authRepositoryProvider = Provider<AuthRepository>(
    (ref) => AuthRepository(ref.read(apiClientProvider)));

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> {
  String? _token;
  Timer? _expiryTimer;

  @override
  AuthState build() {
    // Wire the api client to read our token + bounce on 401.
    ref.read(apiClientProvider).configure(
          token: () => _token,
          onUnauthorized: () => signOut(),
        );
    ref.onDispose(() => _expiryTimer?.cancel());
    return AuthState.unknown;
  }

  /// Restore a stored session on app start.
  Future<void> restore() async {
    final storage = ref.read(authStorageProvider);
    final token = await storage.readToken();
    final user = JwtUser.tryParse(token);
    if (user == null) {
      _token = null;
      state = AuthState.signedOut;
      return;
    }
    _token = token;
    _startExpiryWatch(user);
    state = AuthState.signedIn(user);
  }

  Future<JwtUser> login(String email, String password) async {
    final token = await ref.read(authRepositoryProvider).login(email, password);
    final user = JwtUser.tryParse(token);
    if (user == null) {
      throw Exception('This account cannot use the partner app.');
    }
    _token = token;
    final storage = ref.read(authStorageProvider);
    await storage.writeToken(token);
    await storage.saveAccount(SavedAccount(
      email: email.trim(),
      token: token,
      name: user.greetingName,
      role: user.roleLabel,
    ));
    // Arm biometric quick-login for next time (only shown if the device
    // actually supports biometrics).
    await storage.setBiometricEnabled(true);
    _startExpiryWatch(user);
    state = AuthState.signedIn(user);
    return user;
  }

  /// Restore a saved account (biometric quick-login). Throws if its token has
  /// expired — the caller should fall back to password sign-in.
  Future<JwtUser> loginWithSaved(SavedAccount account) async {
    final user = JwtUser.tryParse(account.token);
    if (user == null) {
      await ref.read(authStorageProvider).removeAccount(account.email);
      throw Exception('Your saved session expired. Please sign in again.');
    }
    _token = account.token;
    await ref.read(authStorageProvider).writeToken(account.token);
    _startExpiryWatch(user);
    state = AuthState.signedIn(user);
    return user;
  }

  Future<void> signOut() async {
    _expiryTimer?.cancel();
    _token = null;
    await ref.read(authStorageProvider).clear();
    state = AuthState.signedOut;
  }

  /// Re-validate the current token (called on resume); signs out if expired.
  void revalidate() {
    final user = JwtUser.tryParse(_token);
    if (user == null && state.status == AuthStatus.authenticated) {
      signOut();
    }
  }

  void _startExpiryWatch(JwtUser user) {
    _expiryTimer?.cancel();
    _expiryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      revalidate();
    });
  }
}
