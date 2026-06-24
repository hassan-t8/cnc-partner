import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../worker/today_summary.dart';
import 'driver_repository.dart';

class DriverRouteScreen extends ConsumerStatefulWidget {
  const DriverRouteScreen({super.key});
  @override
  ConsumerState<DriverRouteScreen> createState() => _DriverRouteScreenState();
}

class _DriverRouteScreenState extends ConsumerState<DriverRouteScreen> {
  late Future<DriverDayPlan> _future;
  GoogleMapController? _map;
  DateTime _date = DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DriverDayPlan> _load() {
    final workerId = ref.read(authControllerProvider).user?.workerId ?? 0;
    return ref.read(driverRepositoryProvider).day(workerId, _date);
  }

  void _reload() => setState(() => _future = _load());

  void _shift(int days) => setState(() {
        _date = _date.add(Duration(days: days));
        _future = _load();
      });

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null) {
      setState(() {
        _date = d;
        _future = _load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () => setState(() {
                          _date = DateTime.now();
                          _future = _load();
                        }),
                    child: const Text('Today')),
              IconButton(
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<DriverDayPlan>(
            future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 120);
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: 'Couldn\'t load today\'s route.', onRetry: _reload);
          }
          final plan = snap.data!;
          final located =
              plan.stops.where((s) => s.lat != null && s.lng != null).toList();
          if (plan.stops.isEmpty) {
            return const EmptyState(
                icon: Icons.map_outlined,
                title: 'No stops today',
                subtitle: 'Enjoy the day — your route will appear here.');
          }
          return Column(
            children: [
              const TodaySummary(),
              if (plan.vanName.isNotEmpty || plan.totalDistanceMeters > 0)
                Container(
                  width: double.infinity,
                  color: AppColors.brand50,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    [
                      if (plan.vanName.isNotEmpty)
                        '${plan.vanName} · ${plan.vanSeats} seats',
                      if (plan.homeZone.isNotEmpty) plan.homeZone,
                      if (plan.totalDistanceMeters > 0)
                        '${(plan.totalDistanceMeters / 1000).toStringAsFixed(1)} km'
                            '${plan.totalDurationSeconds > 0 ? ' · ${(plan.totalDurationSeconds / 60).round()} min' : ''}',
                    ].join(' · '),
                    style: const TextStyle(
                        color: AppColors.brand700,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5),
                  ),
                ),
              if (located.isNotEmpty)
                SizedBox(height: 240, child: _buildMap(plan)),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: plan.stops.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _stopRow(i + 1, plan.stops[i]),
                ),
              ),
            ],
          );
          },
          ),
        ),
      ]),
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
      onMapCreated: (c) => _map = c,
    );
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
