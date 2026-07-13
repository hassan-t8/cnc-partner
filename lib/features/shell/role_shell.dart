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
import '../partner/offer_alert_stack.dart';
import '../partner/partner_bookings_screen.dart';
import '../partner/partner_dashboard_screen.dart';
import '../partner/partner_repository.dart';
import '../partner/partner_requests_screen.dart';
import '../profile/profile_hub_screen.dart';
import '../bookings/models.dart';
import '../worker/crew_jobs_screen.dart';
import '../worker/crew_schedule_screen.dart';
import '../worker/job_alert_popup.dart';
import '../worker/worker_booking_detail_screen.dart';
import '../worker/worker_bookings_screen.dart';
import '../worker/worker_repository.dart';

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
  Timer? _offerPoll;

  // Worker/driver side: alert when a job is auto-assigned to them.
  final Set<int> _seenJobs = {};
  bool _jobsSeeded = false;
  bool _jobPopupOpen = false;

  void _check() {
    _checkOffers(); // partner: new dispatch offers
    _checkJobs(); // worker/driver: jobs assigned to them
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _offerPoll =
        Timer.periodic(const Duration(seconds: 12), (_) => _check());
  }

  @override
  void dispose() {
    _offerPoll?.cancel();
    super.dispose();
  }

  Future<void> _checkOffers() async {
    if (!mounted) return;
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

    // A new offer arrived → refresh the tabs' lists NOW (dashboard "New
    // requests" + Requests tab) so it appears live, without waiting for a tab
    // switch or for the user to act on the popup.
    if (mounted) ref.read(tabRefreshProvider.notifier).state++;

    // inDrive-style stack: push EVERY fresh offer (oldest first so the newest
    // lands on top). Each card auto-dismisses; the overlay is non-blocking.
    fresh.sort((a, b) => a.id.compareTo(b.id));
    for (final o in fresh) {
      OfferAlertOverlay.instance.push(
        context,
        ref,
        o,
        onAction: (action) {
          // On accept/decline refresh the data in place; on timeout/close the
          // offer simply stays in the Requests tab.
          if (action != 'later' && mounted) {
            ref.read(tabRefreshProvider.notifier).state++;
          }
        },
      );
    }
  }

  Future<void> _checkJobs() async {
    if (!mounted || _jobPopupOpen) return;
    final user = ref.read(authControllerProvider).user;
    if (user == null || user.isPartner) return; // workers/drivers only

    List<Assignment> jobs;
    try {
      jobs = await ref.read(workerRepositoryProvider).myBookings(status: 'all');
    } catch (_) {
      return;
    }
    if (!mounted) return;
    // Auto-assigned jobs the worker hasn't started yet.
    final active =
        jobs.where((a) => a.status == 'accepted' || a.status == 'pending_acceptance').toList();

    if (!_jobsSeeded) {
      for (final a in active) {
        _seenJobs.add(a.id);
      }
      _jobsSeeded = true;
      return;
    }
    final fresh = active.where((a) => !_seenJobs.contains(a.id)).toList();
    if (fresh.isEmpty) return;
    for (final a in active) {
      _seenJobs.add(a.id);
    }
    // Refresh the Jobs/Bookings tabs so the new job is listed.
    ref.read(tabRefreshProvider.notifier).state++;

    _jobPopupOpen = true;
    final action = await showJobAlert(context, ref, fresh.first);
    _jobPopupOpen = false;
    if (!mounted) return;
    if (action == 'view') {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WorkerBookingDetailScreen(assignment: fresh.first)));
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
      dests.add(const _Dest(
          'Schedule', Icons.calendar_month_rounded, CrewScheduleScreen()));
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
    ref.listen(bookingRealtimeProvider, (_, __) => _check());
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
