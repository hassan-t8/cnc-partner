import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class LegalSection {
  final String heading;
  final String body;
  const LegalSection(this.heading, this.body);
}

/// Terms & Conditions / Privacy Policy screen rendered as titled sections.
/// Content below is placeholder boilerplate for CNC Partner — replace with the
/// final legal copy before public release.
class LegalScreen extends StatelessWidget {
  final String title;
  final String intro;
  final List<LegalSection> sections;
  const LegalScreen({
    super.key,
    required this.title,
    required this.intro,
    required this.sections,
  });

  static const _effective = 'Last updated: June 2026 · Version 1.0';

  factory LegalScreen.terms() => const LegalScreen(
        title: 'Terms & Conditions',
        intro:
            'These Terms govern your access to and use of the CNC Partner app '
            'operated by Care n Clean ("CNC", "we", "us"). By creating an '
            'account or using the app, you ("Partner", "you") agree to these '
            'Terms on behalf of yourself and your team (drivers and crew).',
        sections: [
          LegalSection('1. Eligibility & accounts',
              'You must be an approved Care n Clean service partner with a valid '
                  'partner agreement. You are responsible for keeping your login '
                  'credentials secure and for all activity under your account and '
                  'the worker accounts you create. Notify us immediately of any '
                  'unauthorised use.'),
          LegalSection('2. Services & job offers',
              'The app lets you receive dispatch offers, accept or decline '
                  'bookings, assign workers and vans, run jobs (start with a '
                  'customer code, capture before/after photos, and complete), and '
                  'track earnings. Accepting a booking creates a binding '
                  'commitment to perform it to CNC quality standards, on time, '
                  'and in line with your partner agreement.'),
          LegalSection('3. Your team & conduct',
              'You are responsible for the accuracy of the worker, van and '
                  'availability information you submit, and for the professional '
                  'conduct, licensing and right-to-work of every member of your '
                  'team on every job. You must comply with all applicable laws, '
                  'health-and-safety rules and customer-site requirements.'),
          LegalSection('4. Pricing, fees & commission',
              'Job prices shown in the app are set by Care n Clean. Your payout '
                  'per job is the customer price less the platform commission '
                  'agreed in your partner agreement (typically a fixed percentage '
                  'per completed booking). Prices and commission rates may be '
                  'updated from time to time and will be reflected in the app. '
                  'Unless stated otherwise, amounts are shown in AED and may be '
                  'exclusive of VAT, which is applied where required by law.'),
          LegalSection('5. Payments & settlement',
              'Earnings from completed bookings accrue to your wallet and are '
                  'settled on the schedule in your partner agreement. CNC may '
                  'withhold, adjust or recover amounts for refunds, chargebacks, '
                  'customer disputes, cancellations, or breaches of these Terms. '
                  'You are responsible for your own taxes.'),
          LegalSection('6. Cancellations & no-shows',
              'Once accepted, bookings should not be cancelled except for genuine '
                  'reasons. Repeated cancellations, late arrivals, no-shows or low '
                  'customer ratings may reduce your dispatch priority, pause '
                  'offers, or lead to suspension of your account.'),
          LegalSection('7. Ratings & quality',
              'Customers may rate jobs. CNC may audit jobs, photos and ratings to '
                  'maintain quality. Persistently low quality may affect your '
                  'standing on the platform.'),
          LegalSection('8. Suspension & termination',
              'We may suspend or terminate your access for breach of these Terms, '
                  'your partner agreement, fraud, safety concerns, or as required '
                  'by law. You may stop using the app at any time; obligations '
                  'relating to completed jobs and settlement survive termination.'),
          LegalSection('9. Liability',
              'The app is provided "as is". To the maximum extent permitted by '
                  'law, CNC is not liable for indirect or consequential losses. '
                  'Nothing in these Terms limits liability that cannot be limited '
                  'by law.'),
          LegalSection('10. Changes & contact',
              'We may update these Terms; continued use after an update '
                  'constitutes acceptance. Questions? Contact support@carenclean.com.'),
        ],
      );

  factory LegalScreen.privacy() => const LegalScreen(
        title: 'Privacy Policy',
        intro:
            'This Policy explains what data the CNC Partner app collects, how we '
            'use it, and your choices. It applies to partners, drivers and crew '
            'using the app.',
        sections: [
          LegalSection('1. Information we collect',
              'Account details (name, email, phone, role, company). Team data '
                  'you add (workers, vans, availability, zones). Operational data '
                  '(bookings, job status, timestamps, locations, before/after '
                  'photos, ratings, earnings). Device data (app version, basic '
                  'diagnostics, push token).'),
          LegalSection('2. How we use it',
              'To operate the partner platform: send and manage job offers, '
                  'dispatch and route jobs, verify start codes, record job '
                  'completion and photos, calculate earnings and settlements, '
                  'maintain quality and ratings, and provide support.'),
          LegalSection('3. Permissions',
              'Location is used to plan driver routes and confirm job locations. '
                  'Camera access is used to capture before/after job photos. '
                  'Notifications are used for job offers and updates. Biometrics '
                  '(fingerprint/Face ID) are processed only on your device to '
                  'unlock saved sign-in — we never receive your biometric data.'),
          LegalSection('4. Sharing',
              'We do not sell your data. We share it only as needed to run the '
                  'service — for example with the customer for a booking you '
                  'fulfil, and with service providers (hosting, maps, '
                  'notifications) under appropriate safeguards, or where required '
                  'by law.'),
          LegalSection('5. Retention',
              'We keep data for as long as your account is active and as required '
                  'for legal, settlement and dispute purposes. Completed-booking '
                  'records may be retained after account closure as required.'),
          LegalSection('6. Security',
              'We use industry-standard measures to protect your data, including '
                  'encrypted storage of credentials on your device. No system is '
                  '100% secure; keep your login protected.'),
          LegalSection('7. Your rights',
              'You can request access to or deletion of your data from the '
                  'account screen or by contacting support. Some data may be '
                  'retained where the law requires.'),
          LegalSection('8. Contact',
              'For privacy questions or requests, contact '
                  'privacy@carenclean.com.'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(title),
      body: ListView(
        // Clear the Android system nav bar (edge-to-edge on Android 15) so the
        // last lines aren't hidden behind it when scrolled to the end.
        padding: EdgeInsets.fromLTRB(
            20, 16, 20, 32 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text(_effective,
              style: TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Text(intro,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          for (final s in sections) ...[
            const SizedBox(height: 18),
            Text(s.heading,
                style: const TextStyle(
                    fontSize: 15.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(s.body,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
