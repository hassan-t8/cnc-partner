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

/// One step in the driver's day timeline (depart, pickup, job, travel,
/// dropoff, return) — the data behind the Schedule screen.
class RouteLeg {
  final String type; // depart | pickup | job | travel | dropoff | return
  final String atLabel; // start time, e.g. "08:30"
  final String endAtLabel; // end time
  final String service;
  final String address;
  final String bookingRef;
  final String customerName;
  final String? customerPhone;
  final String note;
  final String fromLabel;
  final String toLabel;
  const RouteLeg({
    this.type = '',
    this.atLabel = '',
    this.endAtLabel = '',
    this.service = '',
    this.address = '',
    this.bookingRef = '',
    this.customerName = '',
    this.customerPhone,
    this.note = '',
    this.fromLabel = '',
    this.toLabel = '',
  });
  factory RouteLeg.fromJson(Map<String, dynamic> j) => RouteLeg(
        type: (j['type'] ?? j['kind'] ?? '').toString(),
        atLabel: (j['atLabel'] ?? j['at'] ?? '').toString(),
        endAtLabel: (j['endAtLabel'] ?? j['endAt'] ?? '').toString(),
        service: (j['service'] ?? j['serviceName'] ?? '').toString(),
        address: (j['address'] ?? '').toString(),
        bookingRef: (j['bookingRef'] ?? j['bookingId'] ?? '').toString(),
        customerName: (j['customerName'] ?? '').toString(),
        customerPhone: j['customerPhone']?.toString(),
        note: (j['note'] ?? '').toString(),
        fromLabel: (j['fromLabel'] ?? '').toString(),
        toLabel: (j['toLabel'] ?? '').toString(),
      );
}

class DriverDayPlan {
  final String vanName;
  final int vanSeats;
  final String homeZone;
  final List<RouteStop> stops;
  final List<RouteLeg> legs;
  final List<String> warnings;
  final List<String> subPolylines; // encoded route polylines (Routes API)
  final double totalDistanceMeters;
  final int totalDurationSeconds;
  const DriverDayPlan(
      {this.vanName = '',
      this.vanSeats = 0,
      this.homeZone = '',
      this.stops = const [],
      this.legs = const [],
      this.warnings = const [],
      this.subPolylines = const [],
      this.totalDistanceMeters = 0,
      this.totalDurationSeconds = 0});
  factory DriverDayPlan.fromJson(Map<String, dynamic> j) {
    final plan = j['plan'] is Map ? Map<String, dynamic>.from(j['plan']) : j;
    final legs = (plan['legs'] ?? plan['stops']);
    final timeline = legs is List
        ? legs
            .whereType<Map>()
            .map((e) => RouteLeg.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RouteLeg>[];
    final stops = legs is List
        ? legs
            .whereType<Map>()
            .map((e) => RouteStop.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <RouteStop>[];
    final warns = plan['warnings'];
    final polys = plan['subPolylines'];
    num asNum(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
    return DriverDayPlan(
      vanName: (plan['vanName'] ?? '').toString(),
      vanSeats: (plan['vanSeats'] is num)
          ? (plan['vanSeats'] as num).toInt()
          : 0,
      homeZone: (plan['homeZone'] ?? '').toString(),
      stops: stops,
      legs: timeline,
      warnings: warns is List ? warns.map((e) => '$e').toList() : const [],
      subPolylines:
          polys is List ? polys.map((e) => '$e').toList() : const [],
      totalDistanceMeters: asNum(plan['totalDistanceMeters']).toDouble(),
      totalDurationSeconds: asNum(plan['totalDurationSeconds']).toInt(),
    );
  }
}

/// Decode a Google "encoded polyline" string into lat/lng pairs.
List<List<double>> decodePolyline(String encoded) {
  final List<List<double>> points = [];
  int index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int shift = 0, result = 0, b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add([lat / 1e5, lng / 1e5]);
  }
  return points;
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
