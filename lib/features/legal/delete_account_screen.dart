import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';

/// Account-deletion request screen (store/Play compliance). Worker/partner
/// account removal is administered server-side, so this submits a request.
class DeleteAccountScreen extends StatelessWidget {
  const DeleteAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.rose, size: 44),
          const SizedBox(height: 14),
          const Text('Request account deletion',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'Deleting your account removes your profile and stops all future '
            'job offers. Bookings already completed are retained for legal and '
            'settlement records as required.\n\n'
            'Account removal is processed by the Care n Clean team. Submit a '
            'request below and we will confirm by email.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => _confirm(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Request deletion'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
            'This will email a deletion request to the Care n Clean team.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await launchUrl(Uri.parse(
          'mailto:support@carenclean.com?subject=Account%20deletion%20request'));
    }
  }
}
