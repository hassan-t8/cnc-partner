import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../common/placeholder_screen.dart';
import '../profile/profile_screen.dart';
import '../reviews/reviews_screen.dart';
import 'partner_earnings_screen.dart';
import 'partner_vans_screen.dart';
import 'partner_workers_screen.dart';

class PartnerMoreScreen extends StatelessWidget {
  const PartnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = <(IconData, String, Widget)>[
      (Icons.groups_outlined, 'Workers', const PartnerWorkersScreen()),
      (Icons.local_shipping_outlined, 'Vans', const PartnerVansScreen()),
      (Icons.wallet_outlined, 'Earnings', const PartnerEarningsScreen()),
      (Icons.reviews_outlined, 'Reviews', const ReviewsScreen()),
      (
        Icons.calendar_month_outlined,
        'Schedule',
        const PlaceholderScreen(title: 'Schedule', icon: Icons.calendar_month)
      ),
      (
        Icons.auto_awesome_outlined,
        'Service requests',
        const PlaceholderScreen(
            title: 'Service requests', icon: Icons.auto_awesome)
      ),
      (Icons.person_outline, 'Profile', const ProfileScreen()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final (icon, label, screen) = items[i];
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ListTile(
              leading: Icon(icon, color: AppColors.brand600),
              title: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.textFaint),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => screen)),
            ),
          );
        },
      ),
    );
  }
}
