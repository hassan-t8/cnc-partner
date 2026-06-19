import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_controller.dart';
import '../core/providers.dart';
import '../core/theme/app_colors.dart';
import 'notification_bell.dart';

/// Shared top bar for the main bottom-nav screens: a circular profile avatar on
/// the left (opens the Profile tab), a centered title, and the notification bell
/// on the right.
class MainAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final String title;
  const MainAppBar(this.title, {super.key});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final initial = (user?.greetingName.isNotEmpty == true
            ? user!.greetingName[0]
            : '?')
        .toUpperCase();
    return AppBar(
      centerTitle: true,
      title: Text(title),
      leadingWidth: 60,
      leading: Center(
        child: InkWell(
          customBorder: const CircleBorder(),
          // Land on the last (Profile) tab — RoleShell clamps the index.
          onTap: () =>
              ref.read(shellIndexProvider.notifier).state = 1 << 20,
          child: CircleAvatar(
            radius: 17,
            backgroundColor: AppColors.brand50,
            child: Text(initial,
                style: const TextStyle(
                    color: AppColors.brand700,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
        ),
      ),
      actions: const [NotificationBell()],
    );
  }
}
