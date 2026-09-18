import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/profile/profile_image_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/profile_avatar.dart';
import '../partner/partner_repository.dart';
import '../auth/change_password_screen.dart';
import '../legal/delete_account_screen.dart';
import '../legal/legal_screen.dart';
import '../partner/availability_editor.dart';
import '../partner/partner_earnings_screen.dart';
import '../partner/partner_roster_screen.dart';
import '../partner/partner_profile_screen.dart';
import '../partner/partner_schedule_screen.dart';
import '../partner/partner_vans_screen.dart';
import '../partner/partner_workers_screen.dart';
import '../partner/service_requests_screen.dart';
import '../reviews/reviews_screen.dart';
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
  bool _uploadingPhoto = false;

  /// The partner's BUSINESS name, once the record has loaded.
  ///
  /// Null until then, and null for a worker — both fall back to the account
  /// holder's own name, which is the only name those cases have.
  String? _partnerName;

  /// The partner's own contact email — shown under the business name rather
  /// than the signed-in account's address.
  String? _partnerEmail;

  @override
  void initState() {
    super.initState();
    _seedPhoto();
    final u = ref.read(authControllerProvider).user;
    if (u != null && !u.isPartner) {
      ref.read(workerRepositoryProvider).myProfile().then((p) {
        if (!mounted) return;
        final w = p['worker'] is Map
            ? Map<String, dynamic>.from(p['worker'])
            : null;
        setState(() => _worker = w);
        // Seed the shared avatar from the worker's photo if present. `photoUrl`
        // is the key the web reads (Shell.tsx), so accept it too — without it a
        // worker whose record only carries that field falls back to an initial.
        final img = p['profileImage'] ??
            w?['profileImage'] ??
            w?['uploadFile'] ??
            w?['photoUrl'];
        if (img != null) {
          ref.read(profileImageProvider.notifier).setFromFilename('$img');
        }
      }).catchError((_) {});
    }
  }

  /// Pull the current photo fresh from the backend so the avatar reflects the
  /// latest server state whenever the Profile tab is shown.
  Future<void> _seedPhoto() async {
    final u = ref.read(authControllerProvider).user;
    if (u == null || !u.isPartner || u.partnerId == null) return;
    try {
      final p = await ref.read(partnerRepositoryProvider).getPartner(u.partnerId!);
      if (mounted) {
        ref.read(profileImageProvider.notifier).setFromFilename(p.uploadFile);
        // The same call already ran for the avatar; the name rides along
        // rather than costing a second request.
        setState(() {
          if (p.name.trim().isNotEmpty) _partnerName = p.name.trim();
          if (p.email.trim().isNotEmpty) _partnerEmail = p.email.trim();
        });
      }
    } catch (_) {}
  }

  Future<void> _changePhoto() async {
    final u = ref.read(authControllerProvider).user;
    if (u == null || !u.isPartner || u.partnerId == null) return;
    final picked = await pickProfileImage(context);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      // Image-only multipart update (backend updates just uploadFile).
      await repo.updatePartnerWithImage(u.partnerId!, const {},
          imagePath: picked.path);
      final fresh = await repo.getPartner(u.partnerId!);
      ref.read(profileImageProvider.notifier).setFromFilename(fresh.uploadFile);
      if (mounted) {
        setState(() {
          if (fresh.name.trim().isNotEmpty) _partnerName = fresh.name.trim();
          if (fresh.email.trim().isNotEmpty) {
            _partnerEmail = fresh.email.trim();
          }
        });
      }
      AppToast.success('Photo updated');
    } catch (_) {
      AppToast.error('Couldn\'t update photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  void _push(Widget s) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  void _openMyProfile({bool edit = false}) {
    final isPartner = ref.read(authControllerProvider).user?.isPartner ?? false;
    _push(isPartner
        ? PartnerProfileScreen(startInEdit: edit)
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
    if (ok != true || !mounted) return;

    // A BLOCKING loader, because signing out is not instant: it detaches this
    // device from push first (a network round-trip), then clears storage and
    // tears down the socket. Without it the sheet just sat there after the
    // confirm — long enough to look broken and to invite a second tap.
    //
    // Not dismissible: there is nothing useful to do with a half-finished
    // sign-out, and letting it be cancelled would leave the device still
    // registered for the old account's notifications.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.6, color: AppColors.brand600),
                ),
                const SizedBox(height: 14),
                Text('Signing out…',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      // Close the loader whatever happened. signOut is written not to throw,
      // but a dialog that outlives its work would strand the user on a
      // spinner with no way back.
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final isPartner = user?.isPartner ?? false;

    final manage = <_Item>[
      if (isPartner) ...[
        _Item(Icons.groups_rounded, 'Workers', AppColors.violet,
            screen: const PartnerWorkersScreen()),
        _Item(Icons.view_timeline_rounded, 'Roster', AppColors.emerald,
            screen: const PartnerRosterScreen()),
        _Item(Icons.local_shipping_rounded, 'Vans', AppColors.amber,
            screen: const PartnerVansScreen()),
        _Item(Icons.account_balance_wallet_rounded, 'Earnings',
            AppColors.brand600,
            screen: const PartnerEarningsScreen()),
        _Item(Icons.calendar_month_rounded, 'Schedule', AppColors.sky,
            screen: const PartnerScheduleScreen()),
        _Item(Icons.schedule_rounded, 'Working hours', AppColors.amber,
            screen: AvailabilityEditor(
                ownerType: 'partner',
                ownerId: user?.partnerId ?? 0,
                title: 'Working hours')),
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
      // Removed 2026-07-30: the Notifications entry opened a push-permission
      // toggle plus a "send a test notification" button — a debug surface, not
      // something a partner needs. The screen file is kept for reintroduction.
      _Item(Icons.description_rounded, 'Terms & Conditions',
          AppColors.textMuted,
          screen: LegalScreen.terms()),
      _Item(Icons.privacy_tip_rounded, 'Privacy Policy', AppColors.textMuted,
          screen: LegalScreen.privacy()),
      _Item(Icons.delete_rounded, 'Delete account', AppColors.rose,
          screen: const DeleteAccountScreen()),
    ];

    final photo = ref.watch(profileImageProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Green hero behind the status bar → use light (white) status-bar icons
      // so the time/battery stay visible, consistent across the app.
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(user, photo)),
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
    ),
    );
  }

  /// The headline name: the PARTNER BUSINESS, matching the web's profile
  /// page (`partner.partnerName`).
  ///
  /// It used to be the account holder's personal name from the token, so the
  /// same person saw "Ahmed Khan" here and "Gulf Shine Services" on the web
  /// with nothing to say which was which. The business name is what customers
  /// are billed by and what bookings carry, so it is the one that belongs at
  /// the top.
  ///
  /// A worker has no business name — for them the account holder IS the
  /// answer, which is what the fallback gives.
  String _displayName(dynamic user) {
    final partner = (_partnerName ?? '').trim();
    if (partner.isNotEmpty) return partner;
    final full = (user?.fullName ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return (user?.greetingName ?? 'there').toString();
  }

  /// The PARTNER's email, to sit under the partner's name.
  ///
  /// The header used to print the signed-in user's email under a business
  /// name, which pairs two different things. Falls back to the account's own
  /// address for a worker, who has no partner record — and while the partner
  /// record is still loading, so the line is never briefly blank.
  String _headerEmail(dynamic user) {
    final partner = (_partnerEmail ?? '').trim();
    if (partner.isNotEmpty) return partner;
    return (user?.email ?? '').toString();
  }

  Widget _header(dynamic user, String? photo) => GestureDetector(
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                ProfileAvatar(
                  url: photo,
                  size: 64,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  placeholder: Text(
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
                if (user?.isPartner == true)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: GestureDetector(
                      onTap: _uploadingPhoto ? null : _changePhoto,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.brand600, width: 1.5),
                        ),
                        child: _uploadingPhoto
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.brand600))
                            : const Icon(Icons.photo_camera,
                                size: 13, color: AppColors.brand600),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_displayName(user),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(_headerEmail(user),
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
