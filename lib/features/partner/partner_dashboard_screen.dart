import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import 'offer_details_sheet.dart';
import 'partner_bookings_screen.dart';
import 'partner_earnings_screen.dart';
import 'wallet_balance_alert.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'partner_vans_screen.dart';
import 'partner_workers_screen.dart';

class PartnerDashboardScreen extends ConsumerStatefulWidget {
  const PartnerDashboardScreen({super.key});
  @override
  ConsumerState<PartnerDashboardScreen> createState() =>
      _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState
    extends ConsumerState<PartnerDashboardScreen> {
  _Dash? _data;
  bool _loading = true;
  bool _error = false;
  int _acting = -1;
  Timer? _tick;
  // First-seen remaining seconds per offer → the timer bar depletes from full.
  final Map<int, int> _offerStartSecs = {};

  // Captured once while `ref` is valid so dispose() never touches `ref`.
  BookingRealtime? _rt;
  Timer? _rtDebounce;

  @override
  void initState() {
    super.initState();
    _rt = ref.read(bookingRealtimeProvider.notifier);
    _load();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_data?.offers.isNotEmpty ?? false)) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _rtDebounce?.cancel();
    _rt?.releaseBookingRooms(this);
    super.dispose();
  }

  /// Subscribe to a room per live offer so this screen hears when an offer is
  /// withdrawn, expires, or is accepted by another partner — the backend emits
  /// those to `booking_<id>`, never to a partner room.
  void _syncRooms() => _rt?.syncBookingRooms(
      this, (_data?.offers ?? const <Offer>[]).map((o) => o.bookingId).whereType<int>());

  void _onRealtime() {
    _rtDebounce?.cancel();
    _rtDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _refresh();
    });
  }

  Future<_Dash> _fetch() async {
    final repo = ref.read(partnerRepositoryProvider);
    // KPIs (today/week/pending/workers/vans/earnings) are computed server-side
    // via /partner/me/dashboard-stats — no more client-side counting over a
    // capped booking list. Offers still come from the live offers inbox.
    final results = await Future.wait([
      repo.getDashboardStats().catchError((_) => const DashboardStats()),
      repo.offers().catchError((_) => <Offer>[]),
    ]);
    return _Dash(
      stats: results[0] as DashboardStats,
      offers: results[1] as List<Offer>,
    );
  }

  // Initial / tab load — shows the skeleton.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final d = await _fetch();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
      _syncRooms();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  void _reload() => _refresh();

  // Pull-to-refresh / realtime: refetch in place — the spinner ends as soon
  // as data lands and the list stays visible (no skeleton flash / hang).
  Future<void> _refresh() async {
    try {
      final d = await _fetch();
      if (mounted) {
        setState(() {
          _data = d;
          _error = false;
        });
        _syncRooms();
      }
    } catch (_) {
      if (mounted && _data == null) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live KPIs/pending-acceptance: refresh on any booking event.
    ref.listen(bookingRealtimeProvider, (_, __) => _onRealtime());
    // Refetch when the bottom-nav tab is (re)tapped.
    ref.listen(tabRefreshProvider, (_, __) {
      if (mounted) _reload();
    });
    final name = ref.watch(authControllerProvider).user?.greetingName ?? '';
    return Scaffold(
      appBar: const MainAppBar('Dashboard'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const LoadingList(count: 4, height: 96)
            : (_error && _data == null)
                ? ListView(children: [
                    const SizedBox(height: 60),
                    ErrorRetry(
                        message: 'Couldn\'t load the dashboard.',
                        onRetry: _load),
                  ])
                : Builder(builder: (context) {
                    final d = _data!;
            // Server-computed KPIs (no client-side counting over a capped
            // booking list). weekEarn is sum(partnerCost) for completed
            // bookings in the current Monday-week, per the backend window.
            final today = d.stats.bookingsToday;
            final week = d.stats.bookingsWeek;
            final weekEarn = d.stats.earningsWeek;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const WalletBalanceAlert(),
                Text('Hi, $name 👋',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: _kpi('Today', '$today', Icons.today_rounded,
                            AppColors.brand600, () {
                      final now = DateTime.now();
                      final t0 = DateTime(now.year, now.month, now.day);
                      _open(PartnerBookingsScreen(
                          initialFrom: t0, initialTo: t0));
                    })),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _kpi('Next 7 days', '$week',
                            Icons.date_range_rounded, AppColors.sky, () {
                      final now = DateTime.now();
                      final t0 = DateTime(now.year, now.month, now.day);
                      _open(PartnerBookingsScreen(
                          initialFrom: t0,
                          initialTo: t0.add(const Duration(days: 6))));
                    })),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _kpi('Workers', '${d.stats.workersCount}',
                            Icons.groups_rounded, AppColors.violet,
                            () => _open(const PartnerWorkersScreen()))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _kpi('Vans', '${d.stats.vansCount}',
                            Icons.local_shipping_rounded, AppColors.amber,
                            () => _open(const PartnerVansScreen()))),
                  ],
                ),
                const SizedBox(height: 12),
                _earningsCard(weekEarn),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text('New requests',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    if (d.offers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                            color: AppColors.rose.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('${d.offers.length}',
                            style: const TextStyle(
                                color: AppColors.rose,
                                fontWeight: FontWeight.w800,
                                fontSize: 12)),
                      ),
                    const Spacer(),
                    if (d.offers.length > 3)
                      TextButton(
                        onPressed: () =>
                            ref.read(shellIndexProvider.notifier).state = 2,
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap),
                        child: const Text('See all'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (d.offers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'All caught up',
                        subtitle: 'New dispatch offers will appear here.'),
                  )
                else ...[
                  ...d.offers.take(3).map(_offerCard),
                  if (d.offers.length > 3)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () =>
                            ref.read(shellIndexProvider.notifier).state = 2,
                        child: Text('See all ${d.offers.length} requests'),
                      ),
                    ),
                ],
              ],
            );
          }),
      ),
    );
  }

  void _open(Widget s) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => s));

  Widget _kpi(String label, String value, IconData icon, Color color,
          VoidCallback onTap) =>
      Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 8),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                Text(label,
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );

  Widget _earningsCard(double amount) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _open(const PartnerEarningsScreen()),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brand700, AppColors.brand500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                    color: AppColors.brand600.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Earnings (completed)',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 12.5)),
                      Text('AED ${amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      );

  Future<void> _offerAct(Offer o, bool accept) async {
    setState(() => _acting = o.id);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (accept) {
        await repo.acceptOffer(o.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineOffer(o.id);
        AppToast.success('Declined — passed to the next partner');
      }
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  // A dispatch offer card with a NEW tag, depleting timer bar + accept/decline.
  Widget _offerCard(Offer o) {
    final busy = _acting == o.id;
    final exp = o.expiresAt;
    final remaining = exp == null ? 0 : exp.difference(DateTime.now()).inSeconds;
    final start =
        _offerStartSecs.putIfAbsent(o.id, () => remaining > 0 ? remaining : 1);
    if (remaining > start) _offerStartSecs[o.id] = remaining;
    final denom = _offerStartSecs[o.id]!;
    final frac = denom > 0 ? (remaining / denom).clamp(0.0, 1.0) : 0.0;
    final barColor = frac < 0.33
        ? AppColors.rose
        : (frac < 0.66 ? AppColors.amber : AppColors.brand600);
    final mm = remaining ~/ 60, ss = remaining % 60;
    final countdown =
        remaining <= 0 ? 'Expired' : '$mm:${ss.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: busy
          ? null
          : () async {
              final action = await showOfferDetailsSheet(context, ref, o);
              if (action != null && mounted) _reload();
            },
      borderRadius: BorderRadius.circular(12),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            value: frac,
            minHeight: 4,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.rose.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20)),
                      child: const Text('NEW',
                          style: TextStyle(
                              color: AppColors.rose,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                              letterSpacing: 0.5)),
                    ),
                    const Spacer(),
                    Icon(Icons.timer_outlined, size: 14, color: barColor),
                    const SizedBox(width: 3),
                    Text(countdown,
                        style: TextStyle(
                            color: barColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5)),
                  ],
                ),
                const SizedBox(height: 8),
                ServiceTitle(o.serviceName, titleSize: 14.5),
                if (o.address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(o.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
                const SizedBox(height: 4),
                Text('You earn AED ${o.earnings.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: busy ? null : () => _offerAct(o, true),
                          child: const Text('Accept'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton(
                          onPressed: busy ? null : () => _offerAct(o, false),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.rose,
                              side: const BorderSide(color: AppColors.rose)),
                          child: const Text('Decline'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

}

class _Dash {
  final DashboardStats stats;
  final List<Offer> offers;
  _Dash({required this.stats, required this.offers});
}
