import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/profile/profile_image_provider.dart';
import '../core/providers.dart';
import '../core/theme/app_colors.dart';
import 'notification_bell.dart';
import 'profile_avatar.dart';

/// Shared top bar for the main bottom-nav screens: a circular profile avatar on
/// the left (opens the Profile tab), a centered title, and the notification bell
/// on the right. When the screen was pushed (can pop), it shows a back button
/// in place of the avatar instead.
class MainAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;

  /// Extra actions shown before the notification bell.
  final List<Widget> actions;

  /// Optional bottom (e.g. a TabBar).
  final PreferredSizeWidget? bottom;

  /// Show the notification bell (hide it on the Notifications screen itself).
  final bool showBell;

  const MainAppBar(
    this.title, {
    super.key,
    this.actions = const [],
    this.bottom,
    this.showBell = true,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Show the back button only on genuinely *pushed* screens. The bottom-nav
    // tabs live under the shell's first route, so `isFirst` stays true for
    // them even while a sub-screen is pushed elsewhere — using Navigator.canPop
    // here wrongly flipped the tabs to a back arrow whenever any sub-screen
    // (or even a modal sheet) was on the stack.
    final isRootTab = ModalRoute.of(context)?.isFirst ?? true;
    return AppBar(
      centerTitle: true,
      title: Text(title, overflow: TextOverflow.ellipsis),
      leadingWidth: 60,
      leading: isRootTab
          ? Center(child: _avatar(ref, ref.watch(profileImageProvider)))
          : IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: AppColors.textPrimary,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
      actions: [
        ...actions,
        if (showBell) const NotificationBell(),
      ],
      bottom: bottom,
    );
  }

  Widget _avatar(WidgetRef ref, String? imageUrl) => InkWell(
        customBorder: const CircleBorder(),
        // Land on the last (Profile) tab — RoleShell clamps the index.
        onTap: () => ref.read(shellIndexProvider.notifier).state = 1 << 20,
        child: ProfileAvatar(
          url: imageUrl,
          size: 34,
          backgroundColor: AppColors.brand50,
          border: Border.all(color: AppColors.brand600, width: 1.4),
          placeholder:
              const Icon(Icons.person, size: 19, color: AppColors.brand600),
        ),
      );
}
