import '../config/env.dart';
import '../network/api_client.dart';

/// Why a reset / invite link can't be used, as reported by the server before
/// the user is shown a password form.
enum LinkState { valid, consumed, expired, invalid }

/// Outcome of a link pre-check, with the server's own wording when it gave any.
class LinkCheck {
  const LinkCheck(this.state, [this.message]);

  final LinkState state;
  final String? message;

  bool get isValid => state == LinkState.valid;

  /// Fallback copy for the states the server doesn't explain itself.
  String get describe =>
      message?.trim().isNotEmpty == true ? message!.trim() : switch (state) {
            LinkState.valid => '',
            LinkState.consumed =>
              'This link has already been used. Your password is set — please sign in.',
            LinkState.expired =>
              'This link has expired. Ask for a new one and try again.',
            LinkState.invalid =>
              "This link isn't valid. Check you opened the most recent email.",
          };
}

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

  /// PUT /api/users/update-password — change password while signed in.
  Future<void> changePassword(String current, String next) async {
    try {
      // skipAuthRedirect: a 401 here means "wrong current password", not an
      // expired session — don't let the global handler sign the user out.
      await _api.put('/api/users/update-password',
          body: {'currentPassword': current, 'newPassword': next},
          skipAuthRedirect: true);
    } on ApiException catch (e) {
      if (e.status == 401) {
        throw ApiException('Your current password is incorrect.', status: 401);
      }
      rethrow;
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

  /// GET /api/users/verify-setup-link — is this invite link still usable?
  ///
  /// Checked on screen open so the user isn't asked to type a password twice
  /// only to be told the link was already consumed. The server answers with a
  /// `status` string; anything it doesn't recognise is treated as invalid, and
  /// a transport failure is reported as valid so a flaky connection doesn't
  /// block a legitimate activation — the submit call re-checks server-side
  /// anyway.
  Future<LinkCheck> verifySetupLink(String token, String email) async {
    try {
      final res = await _api.get('/api/users/verify-setup-link',
          query: {'token': token, 'email': email}, skipAuthRedirect: true);
      final data = res.data;
      final status =
          (data is Map ? data['status'] : null)?.toString().toLowerCase();
      final message = (data is Map ? data['message'] : null)?.toString();
      return switch (status) {
        'valid' => LinkCheck(LinkState.valid, message),
        'consumed' => LinkCheck(LinkState.consumed, message),
        'expired' => LinkCheck(LinkState.expired, message),
        _ => LinkCheck(LinkState.invalid, message),
      };
    } on ApiException catch (e) {
      final body = e.message.toLowerCase();
      if (body.contains('expired')) return LinkCheck(LinkState.expired, e.message);
      if (body.contains('used') || body.contains('consumed')) {
        return LinkCheck(LinkState.consumed, e.message);
      }
      return LinkCheck(LinkState.invalid, e.message);
    } catch (_) {
      return const LinkCheck(LinkState.valid);
    }
  }

  /// POST /api/users/verify-link-forget-password-crm — is this reset link still
  /// usable? Unlike the setup check this one signals failure by throwing, so
  /// any successful response means the link is good.
  Future<LinkCheck> verifyResetLink(String token, String email) async {
    try {
      await _api.post('/api/users/verify-link-forget-password-crm',
          query: {'token': token, 'email': email}, skipAuthRedirect: true);
      return const LinkCheck(LinkState.valid);
    } on ApiException catch (e) {
      final body = e.message.toLowerCase();
      if (body.contains('expired')) return LinkCheck(LinkState.expired, e.message);
      if (body.contains('used') || body.contains('consumed')) {
        return LinkCheck(LinkState.consumed, e.message);
      }
      return LinkCheck(LinkState.invalid, e.message);
    } catch (_) {
      return const LinkCheck(LinkState.valid);
    }
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
