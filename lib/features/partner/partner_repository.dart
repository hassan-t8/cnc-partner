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

  Future<void> acceptBooking(int id) =>
      _api.post('/booking/$id/partner-accept');
  Future<void> declineBooking(int id, {String? reason}) => _api.post(
      '/booking/$id/partner-decline',
      body: {if (reason != null) 'reason': reason});
  Future<void> startBooking(int id, {String? otp}) => _api
      .post('/booking/$id/partner-start', body: {if (otp != null) 'otp': otp});
  Future<void> completeBooking(int id) =>
      _api.post('/booking/$id/partner-complete');

  // ----- booking assignments (team picker) -----
  Future<List<BookingAssignment>> bookingAssignments(int bookingId) async {
    final res =
        await _api.get('/booking-assignments', query: {'bookingId': bookingId});
    return pickList(res.data).map(BookingAssignment.fromJson).toList();
  }

  Future<void> assignWorker(int bookingId, int workerId,
      {String role = 'crew'}) {
    final isDriver = role == 'driver';
    return _api.post('/booking-assignments', body: {
      'bookingId': bookingId,
      if (isDriver) 'driverWorkerId': workerId,
      if (!isDriver) 'workerId': workerId,
      'role': role,
    });
  }

  Future<void> unassign(int assignmentId) =>
      _api.delete('/booking-assignments/$assignmentId');

  // ----- offers (requests) -----
  Future<List<Offer>> offers() async {
    final res = await _api.get('/offers/mine');
    return pickList(res.data).map(Offer.fromJson).toList();
  }

  Future<void> acceptOffer(int id) => _api.post('/offers/$id/accept');
  Future<void> declineOffer(int id, {String? reason}) =>
      _api.post('/offers/$id/decline', body: {if (reason != null) 'reason': reason});

  // ----- workers -----
  Future<List<Worker>> workers() async {
    final res = await _api.get('/workers');
    return pickList(res.data).map(Worker.fromJson).toList();
  }

  Future<void> createWorker(Map<String, dynamic> body) =>
      _api.post('/workers', body: body);
  Future<void> updateWorker(int id, Map<String, dynamic> body) =>
      _api.put('/workers/$id', body: body);
  Future<void> deleteWorker(int id) => _api.delete('/workers/$id');

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
