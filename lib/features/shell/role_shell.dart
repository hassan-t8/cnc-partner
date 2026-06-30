import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/jwt_user.dart';
import '../../core/providers.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../driver/driver_route_screen.dart';
import '../driver/driver_schedule_screen.dart';
import '../partner/offer_alert_popup.dart';
import '../partner/partner_bookings_screen.dart';
import '../partner/partner_dashboard_screen.dart';
import '../partner/partner_repository.dart';
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
  // ── Live offer alert (partners only) ──────────────────────────────────────
  // Pops an inDrive-style alert the moment a new dispatch offer arrives while
  // the partner is in the app. Driven by the realtime socket (instant) with a
  // periodic poll as a fallback. The Requests tab stays the source of truth.
  final Set<int> _seenOffers = {};
  bool _seeded = false; // first sweep just records existing offers (no popup)
  bool _popupOpen = false;
  Timer? _offerPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOffers());
    _offerPoll =
        Timer.periodic(const Duration(seconds: 12), (_) => _checkOffers());
  }

  @override
  void dispose() {
    _offerPoll?.cancel();
    super.dispose();
  }

  Future<void> _checkOffers() async {
    if (!mounted || _popupOpen) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null || !user.isPartner) return;

    List offers;
    try {
      offers = await ref.read(partnerRepositoryProvider).offers();
    } catch (_) {
      return;
    }
    if (!mounted) return;

    final now = DateTime.now();
    final live = offers
        .where((o) => o.expiresAt == null || o.expiresAt!.isAfter(now))
        .toList();

    // First sweep: remember what's already pending so we don't alert for
    // offers that arrived before the app opened.
    if (!_seeded) {
      for (final o in live) {
        _seenOffers.add(o.id);
      }
      _seeded = true;
      return;
    }

    final fresh = live.where((o) => !_seenOffers.contains(o.id)).toList();
    if (fresh.isEmpty) return;
    for (final o in live) {
      _seenOffers.add(o.id);
    }

    _popupOpen = true;
    final action = await showOfferAlert(context, ref, fresh.first);
    _popupOpen = false;
    if (!mounted) return;
    // The popup is only an alert: on accept/decline refresh the data in place,
    // but on timeout/close ("later") do NOT navigate — the offer stays in the
    // Requests tab, which the user opens via "See all" when they choose to.
    if (action != 'later') {
      ref.read(tabRefreshProvider.notifier).state++;
    }
  }

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
      dests.add(const _Dest(
          'Schedule', Icons.calendar_month_rounded, DriverScheduleScreen()));
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
    // A realtime dispatch/assignment event likely means a new offer — check
    // immediately instead of waiting for the next poll.
    ref.listen(bookingRealtimeProvider, (_, __) => _checkOffers());
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
            onDestinationSelected: (i) {
              ref.read(shellIndexProvider.notifier).state = i;
              // Signal the kept-alive tab screens to refetch fresh data.
              ref.read(tabRefreshProvider.notifier).state++;
            },
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
