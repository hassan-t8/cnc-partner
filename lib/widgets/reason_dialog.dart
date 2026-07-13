import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Optional-reason prompt for a decline action (offers, bookings). Returns the
/// trimmed reason on confirm (may be empty), or null if the user cancelled.
/// Mirrors the web portal's decline flow, which lets the partner add a reason.
Future<String?> showDeclineReasonDialog(
  BuildContext context, {
  String title = 'Decline',
  String hint = 'Reason (optional)',
  String confirmLabel = 'Decline',
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
          onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
