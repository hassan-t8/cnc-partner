import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the JWT (secure) + small non-secret caches (prefs).
class AuthStorage {
  static const _kToken = 'cnc_partner_token';
  static const _kName = 'cnc_partner_name';

  final FlutterSecureStorage _secure;
  AuthStorage([FlutterSecureStorage? secure])
      : _secure = secure ?? const FlutterSecureStorage();

  Future<String?> readToken() => _secure.read(key: _kToken);

  Future<void> writeToken(String token) =>
      _secure.write(key: _kToken, value: token);

  Future<void> clear() async {
    await _secure.delete(key: _kToken);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kName);
  }

  Future<void> writePartnerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kName, name);
  }

  Future<String?> readPartnerName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kName);
  }
}
