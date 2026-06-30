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
import 'driver_repository.dart';

class DriverRouteScreen extends ConsumerStatefulWidget {
  const DriverRouteScreen({super.key});
  @override
  ConsumerState<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends ConsumerState<DriverRouteScreen> {
  GoogleMapController? _map;
  DateTime _date = DateTime.now();
  // Cached plan (null = loading). Kept across refreshes so pull-to-refresh
  // updates in place instead of flashing a loader.
  DriverDayPlan? _plan;
  bool _planErr = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<DriverDayPlan> _load() {
    final workerId = ref.read(authControllerProvider).user?.workerId ?? 0;
    return ref.read(driverRepositoryProvider).day(workerId, _date);
  }

  // Refresh in place — keeps the current plan visible while fetching.
  Future<void> _fetch() async {
    try {
      final p = await _load();
      if (mounted) setState(() {
            _plan = p;
            _planErr = false;
          });
    } catch (_) {
      if (mounted) setState(() => _planErr = true);
    }
  }

  void _reload() => _fetch();

  void _changeDate(DateTime d) {
    setState(() {
      _date = d;
      _plan = null; // new date → show the loader for it
      _planErr = false;
    });
    _fetch();
  }

  void _shift(int days) => _changeDate(_date.add(Duration(days: days)));

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null) _changeDate(d);
  }

  @override
  Widget build(BuildContext context) {
    // Refetch when this tab is (re)tapped on the bottom nav.
    ref.listen(tabRefreshProvider, (_, __) => _reload());
    final isToday = DateUtils.isSameDay(_date, DateTime.now());
    return Scaffold(
      appBar: MainAppBar('My route', actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: InkWell(
                  onTap: _pickDate,
                  child: Center(
                    child: Text(
                        '${DateFormat('EEE d MMM y').format(_date)}'
                        '${isToday ? '  (today)' : ''}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              if (!isToday)
                TextButton(
                    onPressed: () => _changeDate(DateTime.now()),
                    child: const Text('Today')),
              IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetch,
            child: _routeBody(),
          ),
        ),
      ]),
    );
  }

  Widget _routeBody() {
    final plan = _plan;
    if (plan == null) {
      return _planErr
          ? ListView(children: [
              const SizedBox(height: 60),
              ErrorRetry(
                  message: 'Couldn\'t load the route.', onRetry: _reload),
            ])
          : const LoadingList(height: 120);
    }
    if (plan.stops.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 60),
        EmptyState(
            icon: Icons.map_outlined,
            title: 'No stops',
            subtitle: 'Enjoy the day — your route will appear here.'),
      ]);
    }
    final located =
        plan.stops.where((s) => s.lat != null && s.lng != null).toList();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
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
        if (located.isNotEmpty)
          SizedBox(height: 240, child: _buildMap(plan)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Text('${plan.stops.length} stop${plan.stops.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        for (var i = 0; i < plan.stops.length; i++)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _stopRow(i + 1, plan.stops[i]),
          ),
        const SizedBox(height: 12),
      ],
    );
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
    // Draw the route polylines (Routes API encoded paths) when available;
    // otherwise connect the stops in order as a fallback.
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

  /// Frame the whole route so every stop is visible (web map-fix parity).
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
    // Small delay so the map has laid out before the camera move.
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
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 12)),
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
