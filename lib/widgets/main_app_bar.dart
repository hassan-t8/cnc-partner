import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/theme/app_colors.dart';
import 'notification_bell.dart';

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
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      centerTitle: true,
      title: Text(title, overflow: TextOverflow.ellipsis),
      leadingWidth: 60,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              color: AppColors.textPrimary,
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : Center(child: _avatar(ref)),
      actions: [
        ...actions,
        if (showBell) const NotificationBell(),
      ],
      bottom: bottom,
    );
  }

  Widget _avatar(WidgetRef ref) => InkWell(
        customBorder: const CircleBorder(),
        // Land on the last (Profile) tab — RoleShell clamps the index.
        onTap: () => ref.read(shellIndexProvider.notifier).state = 1 << 20,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brand50,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brand600, width: 1.4),
          ),
          // No profile image in the global session — show a person placeholder.
          child: const Icon(Icons.person, size: 19, color: AppColors.brand600),
        ),
      );
}
