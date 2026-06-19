import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/jwt_user.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../driver/driver_route_screen.dart';
import '../partner/partner_bookings_screen.dart';
import '../partner/partner_dashboard_screen.dart';
import '../partner/partner_requests_screen.dart';
import '../profile/profile_hub_screen.dart';
import '../worker/crew_jobs_screen.dart';
import '../worker/worker_bookings_screen.dart';

class _Dest {
  final String label;
  final IconData icon;
  final Widget screen;
  const _Dest(this.label, this.icon, this.screen);
}

/// Bottom-nav shell that adapts to the signed-in user's role.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key});
  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  List<_Dest> _destsFor(JwtUser user) {
    if (user.isPartner) {
      return const [
        _Dest('Home', Icons.dashboard_rounded, PartnerDashboardScreen()),
        _Dest('Bookings', Icons.assignment_rounded, PartnerBookingsScreen()),
        _Dest('Requests', Icons.inbox_rounded, PartnerRequestsScreen()),
        _Dest('Profile', Icons.person_rounded, ProfileHubScreen()),
      ];
    }
    // Worker (crew / driver)
    final dests = <_Dest>[];
    if (user.isDriver) {
      dests.add(
          const _Dest('Route', Icons.map_rounded, DriverRouteScreen()));
    }
    if (user.isCrew || !user.isDriver) {
      dests.add(const _Dest('Jobs', Icons.checklist_rounded, CrewJobsScreen()));
    }
    dests.add(const _Dest(
        'Bookings', Icons.event_note_rounded, WorkerBookingsScreen()));
    dests.add(const _Dest('Profile', Icons.person_rounded, ProfileHubScreen()));
    return dests;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dests = _destsFor(user);
    final index = ref.watch(shellIndexProvider).clamp(0, dests.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: dests.map((d) => d.screen).toList(),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, -2)),
          ],
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              final on = states.contains(WidgetState.selected);
              return TextStyle(
                fontSize: 11.5,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? AppColors.brand600 : AppColors.textMuted,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (i) =>
                ref.read(shellIndexProvider.notifier).state = i,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            height: 66,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            indicatorColor: AppColors.brand50,
            destinations: dests
                .map((d) => NavigationDestination(
                      icon: Icon(d.icon, color: AppColors.textMuted),
                      selectedIcon: Icon(d.icon, color: AppColors.brand600),
                      label: d.label,
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
