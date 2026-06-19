import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A sign-in saved for biometric quick-login.
class SavedAccount {
  final String email;
  final String token;
  final String name;
  final String role;
  const SavedAccount(
      {required this.email,
      required this.token,
      this.name = '',
      this.role = ''});

  Map<String, dynamic> toJson() =>
      {'email': email, 'token': token, 'name': name, 'role': role};

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
        email: '${j['email'] ?? ''}',
        token: '${j['token'] ?? ''}',
        name: '${j['name'] ?? ''}',
        role: '${j['role'] ?? ''}',
      );
}

/// Persists the JWT (secure) + small non-secret caches (prefs).
class AuthStorage {
  static const _kToken = 'cnc_partner_token';
  static const _kName = 'cnc_partner_name';
  static const _kAccounts = 'cnc_partner_accounts';
  static const _kBiometric = 'cnc_partner_biometric';

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

  // ---- Saved accounts (biometric quick-login) ----

  Future<List<SavedAccount>> savedAccounts() async {
    final raw = await _secure.read(key: _kAccounts);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SavedAccount.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveAccount(SavedAccount account) async {
    final list = (await savedAccounts())
        .where((a) => a.email.toLowerCase() != account.email.toLowerCase())
        .toList()
      ..insert(0, account);
    await _secure.write(
        key: _kAccounts,
        value: jsonEncode(list.map((a) => a.toJson()).toList()));
  }

  Future<void> removeAccount(String email) async {
    final list = (await savedAccounts())
        .where((a) => a.email.toLowerCase() != email.toLowerCase())
        .toList();
    await _secure.write(
        key: _kAccounts,
        value: jsonEncode(list.map((a) => a.toJson()).toList()));
  }

  Future<bool> biometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometric) ?? false;
  }

  Future<void> setBiometricEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometric, on);
  }

  static const _kOnboard = 'cnc_partner_onboarded';
  Future<bool> seenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboard) ?? false;
  }

  Future<void> setOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboard, true);
  }
}
