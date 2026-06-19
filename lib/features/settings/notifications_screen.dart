import 'package:flutter/material.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _enabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final ok = await NotificationService.instance.hasPermission();
    if (!mounted) return;
    setState(() {
      _enabled = ok;
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    if (v) {
      final granted = await NotificationService.instance.requestPermission();
      if (!granted) {
        AppToast.error('Enable notifications in system settings.');
      }
      await _refresh();
    } else {
      AppToast.success('Turn off notifications in system settings.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SwitchListTile(
                    value: _enabled,
                    activeTrackColor: AppColors.brand600,
                    title: const Text('Push notifications'),
                    subtitle: const Text(
                        'Job offers, assignment updates and reminders'),
                    onChanged: _toggle,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => NotificationService.instance.show(
                      'CNC Partner', 'This is a test notification.'),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Send a test notification'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Push delivery (FCM) is enabled once Firebase config is added '
                  'to the project. Local reminders work now.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
              ],
            ),
    );
  }
}
