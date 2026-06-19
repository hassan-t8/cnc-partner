import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/notification_bell.dart';
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

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DriverDayPlan> _load() {
    final workerId = ref.read(authControllerProvider).user?.workerId ?? 0;
    return ref.read(driverRepositoryProvider).day(workerId, DateTime.now());
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My route'), actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        const NotificationBell(),
      ]),
      body: FutureBuilder<DriverDayPlan>(
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
              if (plan.vanName.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: AppColors.brand50,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '${plan.vanName} · ${plan.vanSeats} seats'
                    '${plan.homeZone.isNotEmpty ? ' · ${plan.homeZone}' : ''}',
                    style: const TextStyle(
                        color: AppColors.brand700,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5),
                  ),
                ),
              if (located.isNotEmpty)
                SizedBox(height: 240, child: _buildMap(located)),
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
    );
  }

  Widget _buildMap(List<RouteStop> stops) {
    if (Env.googleMapsApiKey.isEmpty) {
      return Container(
        color: AppColors.bg,
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Map disabled — Google Maps key not configured.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
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
    return GoogleMap(
      initialCameraPosition: CameraPosition(
          target: LatLng(stops.first.lat!, stops.first.lng!), zoom: 12),
      markers: markers,
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
