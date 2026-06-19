import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/theme/app_colors.dart';
import '../auth/change_password_screen.dart';
import '../legal/delete_account_screen.dart';
import '../legal/legal_screen.dart';
import '../partner/partner_earnings_screen.dart';
import '../partner/partner_profile_screen.dart';
import '../partner/partner_schedule_screen.dart';
import '../partner/partner_vans_screen.dart';
import '../partner/partner_workers_screen.dart';
import '../partner/service_requests_screen.dart';
import '../reviews/reviews_screen.dart';
import '../settings/notifications_screen.dart';
import '../worker/worker_repository.dart';
import 'worker_profile_screen.dart';

class _Item {
  final IconData icon;
  final String label;
  final Color color;
  final Widget? screen;
  const _Item(this.icon, this.label, this.color, {this.screen});
}

/// One polished profile + navigation hub for every role.
class ProfileHubScreen extends ConsumerStatefulWidget {
  const ProfileHubScreen({super.key});
  @override
  ConsumerState<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends ConsumerState<ProfileHubScreen> {
  Map<String, dynamic>? _worker;

  @override
  void initState() {
    super.initState();
    final u = ref.read(authControllerProvider).user;
    if (u != null && !u.isPartner) {
      ref.read(workerRepositoryProvider).myProfile().then((p) {
        if (!mounted) return;
        setState(() => _worker = p['worker'] is Map
            ? Map<String, dynamic>.from(p['worker'])
            : null);
      }).catchError((_) {});
    }
  }

  void _push(Widget s) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  void _openMyProfile() {
    final isPartner = ref.read(authControllerProvider).user?.isPartner ?? false;
    _push(isPartner
        ? const PartnerProfileScreen()
        : const WorkerProfileScreen());
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log out?'),
        content: const Text('You\'ll need to sign in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true) ref.read(authControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isPartner = user?.isPartner ?? false;

    final manage = <_Item>[
      if (isPartner) ...[
        _Item(Icons.groups_rounded, 'Workers', AppColors.violet,
            screen: const PartnerWorkersScreen()),
        _Item(Icons.local_shipping_rounded, 'Vans', AppColors.amber,
            screen: const PartnerVansScreen()),
        _Item(Icons.account_balance_wallet_rounded, 'Earnings',
            AppColors.brand600,
            screen: const PartnerEarningsScreen()),
        _Item(Icons.calendar_month_rounded, 'Schedule', AppColors.sky,
            screen: const PartnerScheduleScreen()),
        _Item(Icons.auto_awesome_rounded, 'Service requests',
            AppColors.violet,
            screen: const ServiceRequestsScreen()),
        _Item(Icons.business_rounded, 'Business profile', AppColors.brand600,
            screen: const PartnerProfileScreen()),
      ],
      _Item(Icons.star_rounded, 'Reviews', AppColors.star,
          screen: ReviewsScreen(worker: !isPartner)),
    ];

    final account = <_Item>[
      _Item(Icons.lock_reset_rounded, 'Change password', AppColors.brand600,
          screen: const ChangePasswordScreen()),
      _Item(Icons.notifications_rounded, 'Notifications', AppColors.sky,
          screen: const NotificationsScreen()),
      _Item(Icons.description_rounded, 'Terms & Conditions',
          AppColors.textMuted,
          screen: LegalScreen.terms()),
      _Item(Icons.privacy_tip_rounded, 'Privacy Policy', AppColors.textMuted,
          screen: LegalScreen.privacy()),
      _Item(Icons.delete_rounded, 'Delete account', AppColors.rose,
          screen: const DeleteAccountScreen()),
    ];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(user)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_worker != null) ...[
                    _infoRow(Icons.badge_outlined, 'Code',
                        '${_worker!['code'] ?? ''}'),
                    _infoRow(Icons.phone_outlined, 'Phone',
                        '${_worker!['phone'] ?? ''}'),
                  ],
                  _sectionTitle('Manage'),
                  _card(manage),
                  _sectionTitle('Account'),
                  _card(account),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded,
                          size: 18, color: AppColors.rose),
                      label: const Text('Log out',
                          style: TextStyle(
                              color: AppColors.rose,
                              fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.rose),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('CNC Partner · v1.0.0',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 12)),
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(dynamic user) => GestureDetector(
        onTap: _openMyProfile,
        child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 64, 20, 26),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.brand700, AppColors.brand500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: Text(
                (user?.greetingName.isNotEmpty == true
                        ? user!.greetingName[0]
                        : '?')
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user?.greetingName ?? 'there',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(user?.email ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(user?.roleLabel ?? '',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chevron_right,
                  color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(t.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textMuted)),
      );

  Widget _card(List<_Item> items) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(height: 1, indent: 56, color: AppColors.border),
              _tile(items[i]),
            ],
          ],
        ),
      );

  Widget _tile(_Item it) => ListTile(
        onTap: it.screen != null ? () => _push(it.screen!) : null,
        leading: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: it.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(it.icon, color: it.color, size: 19),
        ),
        title: Text(it.label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: it.label == 'Delete account'
                    ? AppColors.rose
                    : AppColors.textPrimary)),
        trailing: Icon(Icons.chevron_right, color: AppColors.textFaint),
      );

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textMuted),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
