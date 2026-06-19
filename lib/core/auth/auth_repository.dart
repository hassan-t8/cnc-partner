import '../config/env.dart';
import '../network/api_client.dart';

/// Auth + password endpoints (mirrors api.ts). Returns the raw token on login.
class AuthRepository {
  final ApiClient _api;
  AuthRepository(this._api);

  /// POST /api/users/login → { token, user, code? }.
  /// Throws [ApiException] with a friendly message on failure.
  Future<String> login(String email, String password) async {
    try {
      final res = await _api.post('/api/users/login', body: {
        'email': email.trim(),
        'password': password,
        'portal': Env.loginPortal,
      });
      final data = res.data;
      if (data is Map && data['code'] == 'ACCOUNT_NOT_ACTIVATED') {
        throw ApiException(
            "Your account isn't activated yet. Please check your email.",
            code: 'ACCOUNT_NOT_ACTIVATED');
      }
      final token = (data is Map ? data['token'] : null)?.toString();
      if (token == null || token.isEmpty) {
        throw ApiException('Login failed. Please try again.');
      }
      return token;
    } on ApiException catch (e) {
      // Re-map auth-specific statuses to friendly copy.
      switch (e.status) {
        case 401:
          throw ApiException('Incorrect email or password.', status: 401);
        case 403:
          throw ApiException(
              'Your account has been suspended. Please contact support.',
              status: 403);
        case 404:
          throw ApiException('No account found with this email.', status: 404);
        default:
          rethrow;
      }
    }
  }

  /// POST /api/users/password-reset/request.
  Future<void> requestPasswordReset(String email) async {
    try {
      await _api.post('/api/users/password-reset/request',
          body: {'email': email.trim(), 'portal': Env.loginPortal});
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'EMAIL_NOT_FOUND') {
        throw ApiException(
            'No partner account is registered with this email.', status: 404);
      }
      rethrow;
    }
  }

  /// POST /api/users/reset-password-crm.
  Future<void> applyPasswordReset(
      String token, String email, String newPassword) async {
    await _api.post('/api/users/reset-password-crm', body: {
      'token': token,
      'email': email,
      'newPassword': newPassword,
    });
  }

  /// POST /api/users/setup-password (invitation).
  Future<void> setupPassword(
      String token, String email, String password) async {
    await _api.post('/api/users/setup-password', body: {
      'token': token,
      'email': email,
      'password': password,
      'confirmPassword': password,
    });
  }
}
