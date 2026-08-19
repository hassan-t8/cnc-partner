import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

/// Registers this install with the backend so it can be sent notifications.
///
/// The row exists from first launch, before anyone signs in — that is what
/// makes a broadcast reachable to a device that has only opened the app.
/// Signing in attaches the account to the same row; signing out detaches it
/// and leaves the row behind, so the device keeps receiving broadcasts but
/// stops receiving anything addressed to the person who left.
///
/// Deliberately built on plain `http` rather than the app's ApiClient: that
/// client redirects to the login screen on 401 and requires a session, and
/// both of the moments this matters most — a fresh install, and a sign-out —
/// have no session at all.
class DeviceRegistry {
  DeviceRegistry._();

  /// Which app this is. All three CNC apps share one Firebase project and one
  /// database, so without this a broadcast to partners would also land on
  /// every customer and CRM user.
  static const String appId = 'partner';

  static const _deviceIdKey = 'device_registry_install_id';

  /// A stable id for this install. FCM tokens rotate; this does not, so one
  /// phone stays one row instead of accumulating one per token.
  static Future<String> _installId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = '${appId}_${DateTime.now().microsecondsSinceEpoch}_'
          '${identityHashCode(prefs)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  static Future<Map<String, String?>> _describeDevice() async {
    final plugin = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        return {
          'platform': 'android',
          'deviceModel': a.model,
          // `name` is unset on most Android builds, so use something a
          // support agent can recognise on a call instead.
          'deviceName': '${a.manufacturer} ${a.model}'.trim(),
          'osVersion': 'Android ${a.version.release} (SDK ${a.version.sdkInt})',
        };
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return {
          'platform': 'ios',
          'deviceModel': i.utsname.machine,
          'deviceName': i.name,
          'osVersion': '${i.systemName} ${i.systemVersion}',
        };
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[device] could not read device info: $e');
    }
    return {'platform': Platform.operatingSystem};
  }

  /// Announce this device.
  ///
  /// [fcmToken] is passed in rather than fetched, because PushService already
  /// handles the iOS case where the APNs token has to land first.
  /// [sessionToken] attaches the account when there is one — the backend only
  /// ever SETS that link, so a launch without a session cannot unlink a user
  /// who is still signed in.
  static Future<void> register({
    required String? fcmToken,
    String? sessionToken,
  }) async {
    if (fcmToken == null || fcmToken.isEmpty) return;
    try {
      final device = await _describeDevice();
      final info = await PackageInfo.fromPlatform();

      final response = await http.post(
        Uri.parse('${Env.apiUrl}/pushNotify/register-device'),
        headers: {
          'Content-Type': 'application/json',
          if (sessionToken != null && sessionToken.isNotEmpty)
            'Authorization': 'Bearer $sessionToken',
        },
        body: jsonEncode({
          'token': fcmToken,
          'appId': appId,
          'appVersion': info.version,
          'buildNumber': info.buildNumber,
          'deviceId': await _installId(),
          ...device,
        }),
      );
      if (kDebugMode && response.statusCode != 200) {
        debugPrint('[device] register failed ${response.statusCode}: '
            '${response.body}');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[device] register error: $e');
    }
  }

  /// Detach this device from the account being signed out.
  ///
  /// Must run before the session is dropped: the row is addressed by the FCM
  /// token, and this is the last moment the app is certainly able to produce
  /// one. Never throws — a sign-out must not be blocked by the network.
  static Future<void> unregister({required String? fcmToken}) async {
    if (fcmToken == null || fcmToken.isEmpty) return;
    try {
      await http.post(
        Uri.parse('${Env.apiUrl}/pushNotify/unregister-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': fcmToken}),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[device] unregister error: $e');
    }
  }
}
