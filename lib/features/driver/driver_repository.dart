import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';

class RouteStop {
  final String label;
  final String kind; // parking | pickup | job
  final double? lat;
  final double? lng;
  final String address;
  const RouteStop(
      {this.label = '',
      this.kind = 'job',
      this.lat,
      this.lng,
      this.address = ''});
  factory RouteStop.fromJson(Map<String, dynamic> j) {
    final p = j['point'] is Map ? Map<String, dynamic>.from(j['point']) : j;
    double? d(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    return RouteStop(
      label: (j['label'] ?? j['name'] ?? '').toString(),
      kind: (j['kind'] ?? j['type'] ?? 'job').toString(),
      lat: d(p['lat'] ?? j['lat']),
      lng: d(p['lng'] ?? j['lng']),
      address: (j['address'] ?? '').toString(),
    );
  }
}

class DriverDayPlan {
  final String vanName;
  final int vanSeats;
  final String homeZone;
  final List<RouteStop> stops;
  final List<String> warnings;
  const DriverDayPlan(
      {this.vanName = '',
      this.vanSeats = 0,
      this.homeZone = '',
      this.stops = const [],
      this.warnings = const []});
  factory DriverDayPlan.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] is Map ? Map<String, dynamic>.from(j['plan']) : j;
    final legs = (plan['legs'] ?? plan['stops']);
    final stops = legs is List
        ? legs
            .whereType<Map>()
            .map((e) => RouteStop.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RouteStop>[];
    final warns = plan['warnings'];
    return DriverDayPlan(
      vanName: (plan['vanName'] ?? '').toString(),
      vanSeats: (plan['vanSeats'] is num)
          ? (plan['vanSeats'] as num).toInt()
          : 0,
      homeZone: (plan['homeZone'] ?? '').toString(),
      stops: stops,
      warnings: warns is List ? warns.map((e) => '$e').toList() : const [],
    );
  }
}

class DriverRepository {
  final ApiClient _api;
  DriverRepository(this._api);

  /// GET /routing/driver/{workerId}/day?date=YYYY-MM-DD
  Future<DriverDayPlan> day(int workerId, DateTime date) async {
    final d =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final res =
        await _api.get('/routing/driver/$workerId/day', query: {'date': d});
    return DriverDayPlan.fromJson(pickMap(res.data));
  }
}

final driverRepositoryProvider = Provider<DriverRepository>(
    (ref) => DriverRepository(ref.read(apiClientProvider)));
