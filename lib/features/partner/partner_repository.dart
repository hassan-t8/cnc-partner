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

  // ----- earnings -----
  Future<WalletInfo> wallet(int partnerId) async {
    final res = await _api.get('/settlement/wallet/$partnerId/statement');
    final data = pickMap(res.data);
    final w = data['wallet'] is Map
        ? Map<String, dynamic>.from(data['wallet'])
        : data;
    return WalletInfo.fromJson(w);
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
}

final partnerRepositoryProvider = Provider<PartnerRepository>(
    (ref) => PartnerRepository(ref.read(apiClientProvider)));
