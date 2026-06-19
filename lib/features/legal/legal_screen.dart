import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Terms & Conditions / Privacy Policy text screen.
class LegalScreen extends StatelessWidget {
  final String title;
  final String body;
  const LegalScreen({super.key, required this.title, required this.body});

  static const _terms = '''
By using the CNC Partner app you agree to provide services professionally, on
time, and in line with Care n Clean standards. You are responsible for the
accuracy of the information you submit (workers, vans, availability) and for the
conduct of your team on every job.

Bookings accepted through the app are binding. Repeated cancellations, no-shows,
or low ratings may affect your dispatch priority or account status.

Payments and settlements are processed per your partner agreement. Care n Clean
may update these terms; continued use of the app constitutes acceptance.
''';

  static const _privacy = '''
We collect the information you provide (account details, workers, vans,
availability) and operational data (bookings, locations, job photos, ratings) to
run the partner platform.

Location is used to plan driver routes. Camera access is used to capture
before/after job photos. Notifications are used for job offers and updates.

We do not sell your data. We share it only as needed to operate the service
(e.g. with customers for the bookings you fulfil). You can request access to or
deletion of your data from the account screen or by contacting support.
''';

  factory LegalScreen.terms() =>
      const LegalScreen(title: 'Terms & Conditions', body: _terms);
  factory LegalScreen.privacy() =>
      const LegalScreen(title: 'Privacy Policy', body: _privacy);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body.trim(),
            style: TextStyle(
                fontSize: 14, height: 1.55, color: AppColors.textSecondary)),
      ),
    );
  }
}
