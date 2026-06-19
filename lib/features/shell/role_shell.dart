import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/jwt_user.dart';
import '../../core/theme/app_colors.dart';
import '../driver/driver_route_screen.dart';
import '../partner/partner_bookings_screen.dart';
import '../partner/partner_dashboard_screen.dart';
import '../partner/partner_more_screen.dart';
import '../partner/partner_requests_screen.dart';
import '../profile/profile_screen.dart';
import '../reviews/reviews_screen.dart';
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
  int _index = 0;

  List<_Dest> _destsFor(JwtUser user) {
    if (user.isPartner) {
      return const [
        _Dest('Home', Icons.dashboard_outlined, PartnerDashboardScreen()),
        _Dest('Bookings', Icons.assignment_outlined, PartnerBookingsScreen()),
        _Dest('Requests', Icons.inbox_outlined, PartnerRequestsScreen()),
        _Dest('More', Icons.menu, PartnerMoreScreen()),
      ];
    }
    // Worker (crew / driver)
    final dests = <_Dest>[];
    if (user.isDriver) {
      dests.add(
          const _Dest('Route', Icons.map_outlined, DriverRouteScreen()));
    }
    if (user.isCrew || !user.isDriver) {
      dests.add(const _Dest('Jobs', Icons.checklist_outlined, CrewJobsScreen()));
    }
    dests.add(const _Dest(
        'Bookings', Icons.event_note_outlined, WorkerBookingsScreen()));
    dests.add(const _Dest('Reviews', Icons.star_outline,
        ReviewsScreen(worker: true)));
    dests.add(const _Dest('Profile', Icons.person_outline, ProfileScreen()));
    return dests;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final dests = _destsFor(user);
    final index = _index.clamp(0, dests.length - 1);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: dests.map((d) => d.screen).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.brand50,
        destinations: dests
            .map((d) => NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.icon, color: AppColors.brand600),
                  label: d.label,
                ))
            .toList(),
      ),
    );
  }
}
