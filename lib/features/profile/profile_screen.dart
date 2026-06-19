import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/brand_logo.dart';
import '../legal/delete_account_screen.dart';
import '../legal/legal_screen.dart';
import '../reviews/reviews_screen.dart';
import '../settings/notifications_screen.dart';
import '../worker/worker_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Map<String, dynamic>? _workerProfile;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    if (user != null && (user.isCrew || user.isDriver) && !user.isPartner) {
      ref
          .read(workerRepositoryProvider)
          .myProfile()
          .then((p) {
        if (mounted) setState(() => _workerProfile = p);
      }).catchError((_) {});
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  void _push(Widget screen) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isWorker =
        user != null && (user.isCrew || user.isDriver) && !user.isPartner;
    final w = _workerProfile?['worker'] is Map
        ? Map<String, dynamic>.from(_workerProfile!['worker'])
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.brand600,
                  child: Text(
                    (user?.greetingName.isNotEmpty == true
                            ? user!.greetingName[0]
                            : '?')
                        .toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.greetingName ?? 'there',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(user?.email ?? '',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brand50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(user?.roleLabel ?? '',
                            style: const TextStyle(
                                color: AppColors.brand700,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (w != null) ...[
            const SizedBox(height: 12),
            _info('Code', '${w['code'] ?? ''}'),
            _info('Phone', '${w['phone'] ?? ''}'),
            _info('Zone', '${w['zoneName'] ?? w['primaryZone'] ?? ''}'),
          ],
          const SizedBox(height: 16),
          if (isWorker)
            _tile(Icons.star_outline, 'My reviews',
                () => _push(const ReviewsScreen(worker: true))),
          _tile(Icons.notifications_outlined, 'Notifications',
              () => _push(const NotificationsScreen())),
          _tile(Icons.description_outlined, 'Terms & Conditions',
              () => _push(LegalScreen.terms())),
          _tile(Icons.privacy_tip_outlined, 'Privacy Policy',
              () => _push(LegalScreen.privacy())),
          _tile(Icons.delete_outline, 'Delete account',
              () => _push(const DeleteAccountScreen()),
              color: AppColors.rose),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout, size: 18, color: AppColors.rose),
            label: const Text('Log out',
                style: TextStyle(color: AppColors.rose)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.rose),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          const Center(child: BrandLogo(size: 36)),
          const SizedBox(height: 8),
          Center(
            child: Text('CNC Partner · v1.0.0',
                style: TextStyle(color: AppColors.textFaint, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _info(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12.5))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _tile(IconData icon, String label, VoidCallback onTap,
      {Color? color}) {
    final c = color ?? AppColors.textSecondary;
    return Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ListTile(
          leading: Icon(icon, color: c),
          title: Text(label, style: TextStyle(color: c)),
          trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
          onTap: onTap,
        ),
      );
  }
}
