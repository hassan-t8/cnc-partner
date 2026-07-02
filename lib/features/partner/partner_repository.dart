import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../bookings/models.dart';
import 'partner_models.dart';

/// Partner-scoped API. Mirrors partnerApi.* in the portal's api.ts.
/// NOTE: endpoints verified against api.ts; adjust if the backend differs.
class PartnerRepository {
  final ApiClient _api;
  PartnerRepository(this._api);

  // ----- bookings -----
  Future<List<PartnerBooking>> bookings({int limit = 500}) async {
    final res = await _api
        .get('/booking/getPartnerBookings', query: {'limit': limit});
    return pickList(res.data).map(PartnerBooking.fromJson).toList();
  }

  /// One page of partner bookings + the pagination envelope, for
  /// infinite-scroll. Backend response shape:
  ///   { success, totalCount, data:[...],
  ///     pagination:{ totalRecords, currentPage, totalPages, pageSize } }
  Future<PartnerBookingsPage> bookingsPage(
      {int page = 1, int limit = 30}) async {
    final res = await _api.get('/booking/getPartnerBookings',
        query: {'page': page, 'limit': limit});
    final rows = pickList(res.data).map(PartnerBooking.fromJson).toList();
    final body = res.data;
    final pag = (body is Map && body['pagination'] is Map)
        ? Map<String, dynamic>.from(body['pagination'] as Map)
        : const <String, dynamic>{};
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final totalRecords = asInt(pag['totalRecords'] ??
        (body is Map ? body['totalCount'] : null) ??
        rows.length);
    final totalPages = asInt(pag['totalPages']) > 0
        ? asInt(pag['totalPages'])
        : (limit > 0 ? ((totalRecords + limit - 1) ~/ limit) : 1);
    final currentPage =
        asInt(pag['currentPage']) > 0 ? asInt(pag['currentPage']) : page;
    return PartnerBookingsPage(
      rows: rows,
      totalRecords: totalRecords,
      totalPages: totalPages,
      currentPage: currentPage,
    );
  }

  /// Aggregated dashboard KPIs computed server-side. Replaces the old
  /// "fetch up to 500 bookings + count on the client" pattern (which could
  /// truncate and undercount past the list cap). Mirrors partnerApi
  /// .getDashboardStats() → GET /partner/me/dashboard-stats.
  Future<DashboardStats> getDashboardStats() async {
    final res = await _api.get('/partner/me/dashboard-stats');
    return DashboardStats.fromJson(pickMap(res.data));
  }

  Future<void> acceptBooking(int id) =>
      _api.post('/booking/$id/partner-accept');
  Future<void> declineBooking(int id, {String? reason}) => _api.post(
      '/booking/$id/partner-decline',
      body: {if (reason != null) 'reason': reason});
  Future<void> startBooking(int id, {String? otp}) => _api
      .post('/booking/$id/partner-start', body: {if (otp != null) 'otp': otp});
  Future<void> completeBooking(int id) =>
      _api.post('/booking/$id/partner-complete');

  /// Release an accepted booking back to dispatch. Canonical self-unassign
  /// flow — captures a reason + idempotency key and returns the applied
  /// penalty ({pct, amount, ...}).
  Future<Map<String, dynamic>> partnerUnassign(int id,
      {String? reason, required String clientRequestId}) async {
    final res = await _api.post('/booking/$id/partner-unassign', body: {
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      'clientRequestId': clientRequestId,
    });
    return res.data is Map ? Map<String, dynamic>.from(res.data) : {};
  }

  /// Mark cash as collected at the door (required before completing a
  /// cash-payment booking).
  Future<void> cashCollect(int id, {String? notes}) => _api.post(
      '/booking/$id/cash-collect',
      body: {if (notes != null && notes.isNotEmpty) 'notes': notes});

  // ----- booking assignments (team picker) -----
  Future<List<BookingAssignment>> bookingAssignments(int bookingId) async {
    final res =
        await _api.get('/booking-assignments', query: {'bookingId': bookingId});
    return pickList(res.data).map(BookingAssignment.fromJson).toList();
  }

  Future<void> assignWorker(int bookingId, int workerId,
      {String role = 'crew', int? vanId}) {
    final isDriver = role == 'driver';
    return _api.post('/booking-assignments', body: {
      'bookingId': bookingId,
      if (isDriver) 'driverWorkerId': workerId,
      if (!isDriver) 'workerId': workerId,
      'role': role,
      if (vanId != null) 'vanId': vanId,
    });
  }

  Future<void> unassign(int assignmentId) =>
      _api.delete('/booking-assignments/$assignmentId');

  // ----- offers (requests) -----
  Future<List<Offer>> offers() async {
    final res = await _api.get('/offers/mine');
    return pickList(res.data).map(Offer.fromJson).toList();
  }

  Future<Map<String, dynamic>> getOffer(int id) async {
    final res = await _api.get('/offers/$id');
    return pickMap(res.data);
  }

  Future<void> acceptOffer(int id, {Map<String, dynamic>? substitutions}) =>
      _api.post('/offers/$id/accept',
          body: {if (substitutions != null) 'substitutions': substitutions});
  Future<void> declineOffer(int id, {String? reason}) =>
      _api.post('/offers/$id/decline', body: {if (reason != null) 'reason': reason});

  // ----- workers -----
  Future<List<Worker>> workers() async {
    final res = await _api.get('/workers');
    return pickList(res.data).map(Worker.fromJson).toList();
  }

  Future<int?> createWorker(Map<String, dynamic> body) async {
    final res = await _api.post('/workers', body: body);
    final d = res.data;
    final w = (d is Map && d['worker'] is Map) ? d['worker'] : d;
    final id = w is Map ? w['id'] : null;
    return id is num ? id.toInt() : int.tryParse('$id');
  }

  Future<void> updateWorker(int id, Map<String, dynamic> body) =>
      _api.put('/workers/$id', body: body);
  Future<void> deleteWorker(int id) => _api.delete('/workers/$id');

  // ----- worker account / password -----
  Future<Map<String, dynamic>> workerLoginInfo(int id) async {
    final res = await _api.get('/workers/$id/login-info');
    return res.data is Map ? Map<String, dynamic>.from(res.data) : {};
  }

  Future<void> setWorkerPassword(int id, String password) =>
      _api.post('/workers/$id/set-password', body: {'password': password});

  Future<Map<String, dynamic>> sendWorkerReset(int id) async {
    final res = await _api.post('/workers/$id/send-reset', body: {});
    return res.data is Map ? Map<String, dynamic>.from(res.data) : {};
  }

  // ----- worker zones / services -----
  Future<List<Map<String, dynamic>>> workerZones(int id) async {
    final res = await _api.get('/workers/$id/zones');
    return pickList(res.data);
  }

  Future<void> syncWorkerZones(int id, List<int> zoneIds, int? primaryZoneId) =>
      _api.post('/workers/$id/zones',
          body: {'zoneIds': zoneIds, 'primaryZoneId': primaryZoneId});

  Future<List<Map<String, dynamic>>> workerServices(int id) async {
    final res = await _api.get('/workers/$id/services');
    return pickList(res.data);
  }

  Future<void> syncWorkerServices(int id, List<int> basePriceIds) =>
      _api.post('/workers/$id/services', body: {'basePriceIds': basePriceIds});

  // ----- availability rules (working hours) -----
  Future<List<AvailabilityRule>> availabilityRules(
      String ownerType, int ownerId) async {
    final res = await _api.get('/availability/rules',
        query: {'ownerType': ownerType, 'ownerId': ownerId});
    return pickList(res.data).map(AvailabilityRule.fromJson).toList();
  }

  Future<void> createAvailabilityRule(Map<String, dynamic> body) =>
      _api.post('/availability/rules', body: body);

  Future<void> updateAvailabilityRule(int id, Map<String, dynamic> body) =>
      _api.put('/availability/rules/$id', body: body);

  Future<void> deleteAvailabilityRule(int id) =>
      _api.delete('/availability/rules/$id');

  // ----- vans -----
  Future<List<Van>> vans() async {
    final res = await _api.get('/vans');
    return pickList(res.data).map(Van.fromJson).toList();
  }

  Future<void> createVan(Map<String, dynamic> body) =>
      _api.post('/vans', body: body);
  Future<void> updateVan(int id, Map<String, dynamic> body) =>
      _api.put('/vans/$id', body: body);
  Future<void> deleteVan(int id) => _api.delete('/vans/$id');

  // ----- zones -----
  Future<List<Zone>> zones() async {
    final res = await _api.get('/zones/flat');
    return pickList(res.data).map(Zone.fromJson).toList();
  }

  // ----- partner profile -----
  Future<Partner> getPartner(int id) async {
    final res = await _api.get('/partner/$id');
    final body = res.data;
    // Backend returns { success, partner: {...} } (not under `data`).
    final map = (body is Map && body['partner'] is Map)
        ? Map<String, dynamic>.from(body['partner'] as Map)
        : pickMap(body);
    return Partner.fromJson(map);
  }

  Future<void> updatePartner(int id, Map<String, dynamic> body) =>
      _api.put('/partner/update/$id', body: body);

  /// Update the partner including an optional profile image (multipart).
  /// Array/object fields are JSON-encoded strings, matching the web form.
  Future<void> updatePartnerWithImage(
    int id,
    Map<String, dynamic> fields, {
    String? imagePath,
  }) {
    final form = <String, String>{};
    fields.forEach((k, v) {
      form[k] = (v is String) ? v : jsonEncode(v);
    });
    return _api.multipart('/partner/update/$id',
        method: 'PUT', fields: form, filePath: imagePath, fileField: 'uploadFile');
  }

  // ----- earnings -----
  Future<WalletStatement> wallet(int partnerId) async {
    final res = await _api.get('/settlement/wallet/$partnerId/statement');
    final data = pickMap(res.data);
    final w = data['wallet'] is Map
        ? Map<String, dynamic>.from(data['wallet'])
        : data;
    final txns = (data['transactions'] is List)
        ? (data['transactions'] as List)
            .whereType<Map>()
            .map((e) => WalletTransaction.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <WalletTransaction>[];
    return WalletStatement(wallet: WalletInfo.fromJson(w), transactions: txns);
  }

  // ----- reviews -----
  Future<RatingSummary> partnerRatingSummary() async {
    final res = await _api.get('/partner/me/rating-summary');
    return RatingSummary.fromJson(pickMap(res.data));
  }

  Future<void> submitCustomerReview(int bookingId, int stars,
          {String? comment}) =>
      _api.post('/reviews/partner-submit', body: {
        'bookingId': bookingId,
        'stars': stars,
        if (comment != null) 'comment': comment,
      });

  // ----- service requests -----
  Future<List<ServiceRequest>> serviceRequests() async {
    final res = await _api.get('/catalog/partner/service-requests');
    return pickList(res.data).map(ServiceRequest.fromJson).toList();
  }

  Future<void> submitServiceRequest(Map<String, dynamic> body) =>
      _api.post('/catalog/partner/service-requests', body: body);

  // ----- catalog (services I provide) -----
  Future<List<MyService>> myServices() async {
    final res = await _api.get('/catalog/partner/my-services');
    return pickList(res.data).map(MyService.fromJson).toList();
  }

  Future<List<CatalogVertical>> catalogTree() async {
    final res = await _api.get('/catalog/partner/catalog-tree');
    return pickList(res.data).map(CatalogVertical.fromJson).toList();
  }

  Future<void> linkService(int catalogServiceId) {
    debugPrint('[catalog] LINK  POST /catalog/partner/services '
        '{catalogServiceId: $catalogServiceId}');
    return _api.post('/catalog/partner/services',
        body: {'catalogServiceId': catalogServiceId});
  }

  Future<void> unlinkService(int partnerServiceId) {
    debugPrint('[catalog] UNLINK DELETE /catalog/partner/services/'
        '$partnerServiceId');
    return _api.delete('/catalog/partner/services/$partnerServiceId');
  }

  /// Replace the partner's picked items under a service. Ticking any item
  /// auto-links the parent service; clearing all auto-unlinks it.
  Future<void> syncItems(int catalogServiceId, List<int> itemIds) {
    debugPrint('[catalog] SYNC  POST /catalog/partner/services '
        '{catalogServiceId: $catalogServiceId, itemIds: $itemIds}');
    return _api.post('/catalog/partner/services',
        body: {'catalogServiceId': catalogServiceId, 'itemIds': itemIds});
  }
}

final partnerRepositoryProvider = Provider<PartnerRepository>(
    (ref) => PartnerRepository(ref.read(apiClientProvider)));
