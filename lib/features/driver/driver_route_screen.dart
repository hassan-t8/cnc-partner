import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../bookings/models.dart';
import '../worker/today_summary.dart';
import '../worker/worker_repository.dart';
import 'driver_repository.dart';

class DriverRouteScreen extends ConsumerStatefulWidget {
  const DriverRouteScreen({super.key});
  @override
  ConsumerState<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends ConsumerState<DriverRouteScreen> {
  GoogleMapController? _map;

  // Range: past | today | upcoming.
  String _range = 'today';
  // Pending-acceptance assignments (independent of range).
  List<Assignment> _pending = const [];
  bool _pendingBusy = false;
  // Bookings in the selected range (the selector chips).
  List<UpcomingBooking> _bookings = const [];
  bool _listErr = false;
  // Selected booking to route (null = "Full day" for today).
  int? _selectedBookingId;

  // The route currently shown on the map (day plan or a booking's route-map).
  DriverDayPlan? _plan;
  bool _planErr = false;

  int get _workerId => ref.read(authControllerProvider).user?.workerId ?? 0;
  DriverRepository get _repo => ref.read(driverRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadPending(), _loadBookings()]);
  }

  Future<void> _loadPending() async {
    try {
      final p = await ref
          .read(workerRepositoryProvider)
          .assignments(workerId: _workerId, status: 'pending_acceptance');
      if (mounted) setState(() => _pending = p);
    } catch (_) {/* pending is best-effort */}
  }

  // Loads the range's bookings, picks a default selection, then loads its route.
  Future<void> _loadBookings() async {
    try {
      final bks = await _repo.upcomingBookings(_workerId, range: _range);
      if (!mounted) return;
      setState(() {
        _bookings = bks;
        _listErr = false;
        // Today defaults to the full-day route; past/upcoming pick the 1st job.
        _selectedBookingId =
            _range == 'today' ? null : (bks.isNotEmpty ? bks.first.id : null);
      });
      await _loadPlan();
    } catch (_) {
      if (mounted) setState(() => _listErr = true);
    }
  }

  Future<void> _loadPlan() async {
    setState(() {
      _plan = null;
      _planErr = false;
    });
    try {
      DriverDayPlan p;
      if (_selectedBookingId == null) {
        if (_range == 'today') {
          p = await _repo.day(_workerId, DateTime.now());
        } else {
          // Nothing selected for past/upcoming → show empty state.
          if (mounted) setState(() => _plan = const DriverDayPlan());
          return;
        }
      } else {
        final b = _bookings.firstWhere((x) => x.id == _selectedBookingId,
            orElse: () => const UpcomingBooking(id: 0));
        p = await _repo.routeMap(_workerId,
            date: b.scheduledStart ?? DateTime.now(),
            bookingId: _selectedBookingId);
      }
      if (mounted) setState(() => _plan = p);
    } catch (_) {
      if (mounted) setState(() => _planErr = true);
    }
  }

  void _setRange(String r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _bookings = const [];
      _selectedBookingId = null;
      _plan = null;
    });
    _loadBookings();
  }

  void _selectBooking(int? id) {
    setState(() => _selectedBookingId = id);
    _loadPlan();
  }

  void _reload() => _loadAll();

  // ---- pending accept / decline ----
  void _snack(String m, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m),
      backgroundColor: err ? AppColors.rose : AppColors.brand600,
    ));
  }

  Future<void> _accept(Assignment a) async {
    setState(() => _pendingBusy = true);
    try {
      await ref.read(workerRepositoryProvider).accept(a.id);
      _snack('Job accepted');
      await _loadAll();
    } catch (_) {
      _snack("Couldn't accept the job", err: true);
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Future<void> _decline(Assignment a) async {
    final reason = await _askReason();
    if (reason == null) return; // cancelled
    setState(() => _pendingBusy = true);
    try {
      await ref
          .read(workerRepositoryProvider)
          .decline(a.id, reason: reason.isEmpty ? null : reason);
      _snack('Job declined');
      await _loadAll();
    } catch (_) {
      _snack("Couldn't decline the job", err: true);
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Future<String?> _askReason() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Decline job'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            hintText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabRefreshProvider, (_, __) => _reload());
    return Scaffold(
      appBar: MainAppBar('My route', actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        _rangeTabs(),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // Today's at-a-glance counts (parity with crew Jobs). Self-
                // fetches for the driver when no jobs list is passed.
                if (_range == 'today') const TodaySummary(),
                if (_pending.isNotEmpty) _pendingSection(),
                _bookingSelector(),
                ..._routeBody(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ---- range tabs ----
  Widget _rangeTabs() {
    Widget tab(String key, String label) {
      final sel = _range == key;
      return Expanded(
        child: InkWell(
          onTap: () => _setRange(key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: sel ? AppColors.brand600 : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: sel ? AppColors.brand700 : AppColors.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: AppColors.surface,
      child: Row(children: [
        tab('past', 'Past'),
        tab('today', 'Today'),
        tab('upcoming', 'Upcoming'),
      ]),
    );
  }

  // ---- pending acceptance inbox ----
  Widget _pendingSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.pending_actions_rounded,
                size: 18, color: AppColors.amber),
            const SizedBox(width: 8),
            Text('Pending your acceptance (${_pending.length})',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.amber)),
          ]),
          const SizedBox(height: 8),
          for (final a in _pending) _pendingCard(a),
        ],
      ),
    );
  }

  Widget _pendingCard(Assignment a) {
    final when = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.serviceName.isEmpty ? (a.bookingCode) : a.serviceName,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (a.customerName.isNotEmpty || when.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [if (a.customerName.isNotEmpty) a.customerName, if (when.isNotEmpty) when].join('  ·  '),
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
            ),
          if (a.address.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(a.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pendingBusy ? null : () => _decline(a),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.rose,
                    side: BorderSide(color: AppColors.rose.withValues(alpha: 0.5))),
                child: const Text('Decline'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _pendingBusy ? null : () => _accept(a),
                style: FilledButton.styleFrom(backgroundColor: AppColors.brand600),
                child: const Text('Accept'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ---- booking selector chips ----
  Widget _bookingSelector() {
    final chips = <Widget>[];
    if (_range == 'today') {
      chips.add(_chip('Full day', _selectedBookingId == null,
          () => _selectBooking(null)));
    }
    for (final b in _bookings) {
      final t = b.scheduledStart != null
          ? DateFormat('h:mm a').format(b.scheduledStart!)
          : '';
      final label = [
        if (t.isNotEmpty) t,
        b.customerName.isNotEmpty
            ? b.customerName
            : (b.code.isNotEmpty ? b.code : b.service),
      ].join(' · ');
      chips.add(_chip(label, _selectedBookingId == b.id,
          () => _selectBooking(b.id)));
    }

    if (chips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          _listErr
              ? "Couldn't load bookings."
              : (_range == 'past'
                  ? 'No past bookings.'
                  : _range == 'upcoming'
                      ? 'Nothing coming up.'
                      : 'No bookings today.'),
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      );
    }

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          for (final c in chips)
            Padding(padding: const EdgeInsets.only(right: 8), child: c),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand600 : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppColors.textMuted)),
      ),
    );
  }

  // ---- route (map + stops) ----
  /// Route-plan warnings (e.g. "no van assigned", "stop outside your zone").
  /// The Schedule screen already surfaces these; the map-centric Route screen
  /// fetched them but never showed them.
  List<Widget> _warnings(DriverDayPlan plan) => [
        for (final w in plan.warnings)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(w,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600))),
              ],
            ),
          ),
      ];

  List<Widget> _routeBody() {
    final plan = _plan;
    if (plan == null) {
      return [
        _planErr
            ? Padding(
                padding: const EdgeInsets.only(top: 40),
                child: ErrorRetry(
                    message: "Couldn't load the route.", onRetry: _loadPlan),
              )
            : const LoadingList(height: 120),
      ];
    }
    if (plan.stops.isEmpty) {
      return [
        ..._warnings(plan),
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: EmptyState(
              icon: Icons.map_outlined,
              title: 'No route',
              subtitle: 'Pick a booking above to see its route.'),
        ),
      ];
    }
    final located =
        plan.stops.where((s) => s.lat != null && s.lng != null).toList();
    return [
      ..._warnings(plan),
      if (plan.vanName.isNotEmpty || plan.totalDistanceMeters > 0)
        Container(
          width: double.infinity,
          color: AppColors.brand50,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.local_shipping_rounded,
                  size: 16, color: AppColors.brand700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (plan.vanName.isNotEmpty)
                      '${plan.vanName} · ${plan.vanSeats} seats',
                    if (plan.homeZone.isNotEmpty) plan.homeZone,
                    if (plan.totalDistanceMeters > 0)
                      '${(plan.totalDistanceMeters / 1000).toStringAsFixed(1)} km'
                          '${plan.totalDurationSeconds > 0 ? ' · ${(plan.totalDurationSeconds / 60).round()} min' : ''}',
                  ].join('  ·  '),
                  style: const TextStyle(
                      color: AppColors.brand700,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      if (located.isNotEmpty) SizedBox(height: 240, child: _buildMap(plan)),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(
            '${plan.stops.length} stop${plan.stops.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      for (var i = 0; i < plan.stops.length; i++)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _stopRow(i + 1, plan.stops[i]),
        ),
    ];
  }

  Widget _buildMap(DriverDayPlan plan) {
    if (Env.googleMapsApiKey.isEmpty) {
      return Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Map disabled — Google Maps key not configured.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final stops =
        plan.stops.where((s) => s.lat != null && s.lng != null).toList();
    final markers = <Marker>{};
    for (var i = 0; i < stops.length; i++) {
      final s = stops[i];
      markers.add(Marker(
        markerId: MarkerId('s$i'),
        position: LatLng(s.lat!, s.lng!),
        infoWindow: InfoWindow(title: '${i + 1}. ${s.label}'),
        icon: BitmapDescriptor.defaultMarkerWithHue(s.kind == 'parking'
            ? BitmapDescriptor.hueGreen
            : s.kind == 'pickup'
                ? BitmapDescriptor.hueAzure
                : BitmapDescriptor.hueViolet),
      ));
    }
    final polylines = <Polyline>{};
    if (plan.subPolylines.isNotEmpty) {
      for (var i = 0; i < plan.subPolylines.length; i++) {
        final pts = decodePolyline(plan.subPolylines[i])
            .map((p) => LatLng(p[0], p[1]))
            .toList();
        if (pts.length > 1) {
          polylines.add(Polyline(
            polylineId: PolylineId('p$i'),
            points: pts,
            color: AppColors.brand600,
            width: 4,
          ));
        }
      }
    } else if (stops.length > 1) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route'),
        points: [for (final s in stops) LatLng(s.lat!, s.lng!)],
        color: AppColors.brand600.withValues(alpha: 0.6),
        width: 3,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }
    return GoogleMap(
      key: ValueKey('map_${_range}_${_selectedBookingId ?? 'day'}'),
      initialCameraPosition: CameraPosition(
          target: LatLng(stops.first.lat!, stops.first.lng!), zoom: 12),
      markers: markers,
      polylines: polylines,
      myLocationButtonEnabled: false,
      onMapCreated: (c) {
        _map = c;
        _fitBounds(stops);
      },
    );
  }

  void _fitBounds(List<RouteStop> stops) {
    if (stops.length < 2) return;
    var minLat = stops.first.lat!, maxLat = stops.first.lat!;
    var minLng = stops.first.lng!, maxLng = stops.first.lng!;
    for (final s in stops) {
      if (s.lat == null || s.lng == null) continue;
      minLat = s.lat! < minLat ? s.lat! : minLat;
      maxLat = s.lat! > maxLat ? s.lat! : maxLat;
      minLng = s.lng! < minLng ? s.lng! : minLng;
      maxLng = s.lng! > maxLng ? s.lng! : maxLng;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    Future.delayed(const Duration(milliseconds: 350), () {
      _map?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 56));
    });
  }

  Widget _stopRow(int n, RouteStop s) {
    final color = s.kind == 'parking'
        ? AppColors.brand600
        : s.kind == 'pickup'
            ? AppColors.sky
            : AppColors.violet;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
              radius: 14,
              backgroundColor: color,
              child: Text('$n',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label.isEmpty ? s.kind : s.label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (s.address.isNotEmpty)
                  Text(s.address,
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          ),
          if (s.kind != 'parking' && s.lat != null)
            IconButton(
              icon: const Icon(Icons.directions, color: AppColors.brand600),
              onPressed: () => launchUrl(
                Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=${s.lat},${s.lng}&travelmode=driving'),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }
}
