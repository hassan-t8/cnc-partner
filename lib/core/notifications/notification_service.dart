import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local notifications + permission handling.
///
/// Push (FCM) is intentionally not wired yet: it needs Firebase config files
/// (google-services.json / GoogleService-Info.plist) + firebase_core/messaging.
/// Once those are added, register the device token after login and forward
/// incoming messages to [show] for foreground display + deep-link routing.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
        const InitializationSettings(android: android, iOS: ios));
    _ready = true;
  }

  /// Ask the OS for notification permission (iOS prompt / Android 13+).
  Future<bool> requestPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async =>
      (await Permission.notification.status).isGranted;

  Future<void> show(String title, String body, {int id = 0}) async {
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'cnc_partner_default',
        'General',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details);
  }
}
