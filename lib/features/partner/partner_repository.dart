import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
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

  /// GET /tips/partner/me[?bookingId=X] — customer tips credited to this
  /// partner. Returns the rows plus the approved total.
  Future<({List<Tip> tips, double approvedTotal})> listMyTips(
      {int? bookingId}) async {
    final res = await _api.get('/tips/partner/me',
        query: bookingId != null ? {'bookingId': bookingId} : null);
    final tips = pickList(res.data).map(Tip.fromJson).toList();
    final body = res.data;
    final totals = (body is Map && body['totals'] is Map) ? body['totals'] : {};
    final approved = (totals['approvedTotal'] is num)
        ? (totals['approvedTotal'] as num).toDouble()
        : tips.where((t) => t.isApproved).fold<double>(0, (s, t) => s + t.amount);
    return (tips: tips, approvedTotal: approved);
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

  /// GET /booking-assignments?from&to — every assignment for the partner's team
  /// in the window (partner scope resolved server-side, no workerId). Powers the
  /// day roster (who's on what).
  Future<List<Assignment>> dayAssignments({
    required DateTime from,
    required DateTime to,
  }) async {
    final res = await _api.get('/booking-assignments', query: {
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
    });
    return pickList(res.data).map(Assignment.fromJson).toList();
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

  /// Change only a worker's status. This is a DIFFERENT endpoint from
  /// [updateWorker]: the generic `PUT /workers/:id` validates the smaller enum
  /// `active | on_leave | suspended | terminated`, so posting `not_working`
  /// there is rejected with 400 "Invalid status." The dedicated status route
  /// accepts `active | not_working | on_leave | suspended | terminated`
  /// (a partner may not set `terminated` — that's 403).
  ///
  /// `reason`, when given, is appended to the worker's notes.
  Future<void> setWorkerStatus(int id, String status, {String? reason}) =>
      _api.put('/workers/$id/status', body: {
        'status': status,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      });

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

  /// A worker's linked services, split into the legacy anchor rows
  /// (`basePriceIds`) and the per-item picks bucketed by basePriceId
  /// (`itemsByBp`). Mirrors the web's hydration of `listWorkerServices`
  /// (`GET /workers/:id/services` → `{ data:[{basePriceId}], items:[{basePriceId,
  /// serviceItemId}] }`).
  Future<WorkerServicesLink> workerServicesLink(int id) async {
    final res = await _api.get('/workers/$id/services');
    final body = res.data;
    final data = pickList(body);
    final basePriceIds = data
        .map((r) => r['basePriceId'])
        .map((v) => v is num ? v.toInt() : int.tryParse('$v'))
        .whereType<int>()
        .toList();
    // Per-item rows live under the top-level `items` key (not `data`).
    final rawItems = (body is Map && body['items'] is List)
        ? (body['items'] as List)
        : const [];
    final itemsByBp = <int, List<int>>{};
    for (final e in rawItems.whereType<Map>()) {
      final bp = e['basePriceId'] is num
          ? (e['basePriceId'] as num).toInt()
          : int.tryParse('${e['basePriceId']}');
      final sid = e['serviceItemId'] is num
          ? (e['serviceItemId'] as num).toInt()
          : int.tryParse('${e['serviceItemId']}');
      if (bp == null || sid == null) continue;
      (itemsByBp[bp] ??= <int>[]).add(sid);
    }
    return WorkerServicesLink(basePriceIds: basePriceIds, itemsByBp: itemsByBp);
  }

  /// Persist a worker's picked services + items. Matches the web contract:
  /// `POST /workers/:id/services { basePriceIds, itemsByBasePriceId }` where
  /// `itemsByBasePriceId` maps basePriceId → serviceItemId[].
  Future<void> syncWorkerServices(
    int id,
    List<int> basePriceIds, {
    Map<int, List<int>> itemsByBp = const {},
  }) =>
      _api.post('/workers/$id/services', body: {
        'basePriceIds': basePriceIds,
        'itemsByBasePriceId': {
          for (final e in itemsByBp.entries) '${e.key}': e.value,
        },
      });

  // ----- availability rules (recurring weekly shifts) -----
  Future<List<AvailabilityRule>> availabilityRules(
      String ownerType, int ownerId,
      {bool activeOnly = true}) async {
    final res = await _api.get('/availability/rules', query: {
      'ownerType': ownerType,
      'ownerId': ownerId,
      if (activeOnly) 'activeOnly': 'true',
    });
    return pickList(res.data).map(AvailabilityRule.fromJson).toList();
  }

  Future<void> createAvailabilityRule(Map<String, dynamic> body) =>
      _api.post('/availability/rules', body: body);

  Future<void> updateAvailabilityRule(int id, Map<String, dynamic> body) =>
      _api.put('/availability/rules/$id', body: body);

  Future<void> deleteAvailabilityRule(int id) =>
      _api.delete('/availability/rules/$id');

  // ----- availability exceptions (leaves / one-off changes) -----
  /// One-off overrides for [ownerId] between [from] and [to] (YYYY-MM-DD).
  /// Backend filters by the date range only when BOTH from + to are given.
  Future<List<AvailabilityException>> availabilityExceptions(
      String ownerType, int ownerId,
      {String? from, String? to}) async {
    final res = await _api.get('/availability/exceptions', query: {
      'ownerType': ownerType,
      'ownerId': ownerId,
      if (from != null && to != null) ...{'from': from, 'to': to},
    });
    return pickList(res.data).map(AvailabilityException.fromJson).toList();
  }

  Future<void> createAvailabilityException(Map<String, dynamic> body) =>
      _api.post('/availability/exceptions', body: body);

  Future<void> updateAvailabilityException(int id, Map<String, dynamic> body) =>
      _api.put('/availability/exceptions/$id', body: body);

  Future<void> deleteAvailabilityException(int id) =>
      _api.delete('/availability/exceptions/$id');

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
  /// Wallet ledger for the Earnings screen.
  ///
  /// The backend defaults this endpoint to 50 rows and clamps it at 200
  /// (settlementController: `min(200, query.limit || 50)`). Without an explicit
  /// limit the app was reading only the newest 50 rows, so the Settled tab, the
  /// pending-clearance list and the period cash/tips totals were all computed
  /// off a partial ledger — showing different money than the web, which asks for
  /// the full 200.
  Future<WalletStatement> wallet(int partnerId) async {
    final res = await _api.get('/settlement/wallet/$partnerId/statement',
        query: {'limit': 200});
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

  // ----- cash requests (withdraw) -----
  //
  // partnerId always comes from req.partnerScope server-side, never from the
  // URL or body, so none of these take one.

  /// `POST /partner-cash-requests` with `type: 'withdraw'`.
  ///
  /// The backend moves `amount` from wallet.balance into wallet.heldBalance
  /// inside a transaction before creating the row, so a successful call has
  /// already locked the funds.
  ///
  /// [clientRequestId] is mandatory (400 `IDEMPOTENCY_REQUIRED` without it) and
  /// must be STABLE across retries: the server keys on
  /// `withdraw:<partnerId>:<clientRequestId>` and returns the existing row
  /// instead of holding the money twice. Mint it once when the form opens.
  ///
  /// Throws [ApiException] with `code`:
  ///   `INSUFFICIENT_BALANCE` (400) — amount exceeds available balance
  ///   `WALLET_FROZEN`        (409) — withdrawals paused
  Future<PartnerCashRequest> submitWithdraw({
    required double amount,
    required String clientRequestId,
    required String bankAccountName,
    required String bankAccountNumber,
    String? bankName,
    String? iban,
    String? notes,
  }) async {
    final res = await _api.post('/partner-cash-requests', body: {
      'type': 'withdraw',
      'amount': amount,
      'clientRequestId': clientRequestId,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      if (bankName != null && bankName.isNotEmpty) 'bankName': bankName,
      if (iban != null && iban.isNotEmpty) 'iban': iban,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
    });
    // Both the 201 and the deduped 200 wrap the row as `data.request`.
    final data = pickMap(res.data);
    final row = data['request'] is Map
        ? Map<String, dynamic>.from(data['request'] as Map)
        : data;
    return PartnerCashRequest.fromJson(row);
  }

  /// `GET /partner-cash-requests/me` — newest first. `limit` caps at 100.
  Future<List<PartnerCashRequest>> myCashRequests({
    String? status,
    String? type,
    int limit = 25,
  }) async {
    final res = await _api.get('/partner-cash-requests/me', query: {
      if (status != null) 'status': status,
      if (type != null) 'type': type,
      'limit': limit,
    });
    return pickList(res.data).map(PartnerCashRequest.fromJson).toList();
  }

  /// `POST /partner-cash-requests/:id/cancel` — releases the hold back to
  /// balance. 409 `NOT_PENDING` if an admin already decided it.
  Future<void> cancelCashRequest(int id) =>
      _api.post('/partner-cash-requests/$id/cancel');

  // ----- HyperPay deposit -----

  /// `POST /partner-deposit/initiate` → the checkout the WebView renders.
  ///
  /// [clientRequestId] must be STABLE across retries (mint once per attempt):
  /// the server keys on it and, if the same id maps to a still-pending
  /// deposit, returns that one with `deduped:true` rather than starting a
  /// second checkout. Frozen wallet → 409 `WALLET_FROZEN`.
  Future<DepositInit> initiateDeposit({
    required double amount,
    required String paymentMethod, // card | apple_pay
    required String clientRequestId,
  }) async {
    final res = await _api.post('/partner-deposit/initiate', body: {
      'amount': amount,
      'paymentMethod': paymentMethod,
      'clientRequestId': clientRequestId,
    });

    final map = Map<String, dynamic>.from(pickMap(res.data));

    // The backend's DEDUPED branch (an existing pending deposit, returned when
    // the same clientRequestId is replayed) omits `shopperResultUrl` — only the
    // fresh branch sends it. Handing HyperPay an empty result URL renders
    // `<form action="">` and the widget rejects the card with "invalid or
    // missing parameters" the moment you press Pay.
    //
    // The URL is deterministic server-side
    // (`{base}/partner-deposit/hyperpay-callback?depositId={id}`) and depositId
    // comes back on BOTH branches, so rebuild it rather than shipping a broken
    // checkout page.
    final resultUrl = (map['shopperResultUrl'] ?? '').toString().trim();
    if (resultUrl.isEmpty && map['depositId'] != null) {
      final base = Env.apiUrl.replaceAll(RegExp(r'/+$'), '');
      map['shopperResultUrl'] =
          '$base/partner-deposit/hyperpay-callback?depositId=${map['depositId']}';
    }

    return DepositInit.fromJson(map);
  }

  /// `GET /partner-deposit/me` — this partner's deposits, newest first.
  Future<List<PartnerDepositRow>> myDeposits({int limit = 50}) async {
    final res =
        await _api.get('/partner-deposit/me', query: {'limit': limit});
    return pickList(res.data).map(PartnerDepositRow.fromJson).toList();
  }

  /// `GET /partner/me/wallet-thresholds` — the warn/block wallet limits for the
  /// negative-balance banner. Falls back to the system defaults on any error.
  Future<({double warn, double block})> walletThresholds() async {
    try {
      final res = await _api.get('/partner/me/wallet-thresholds');
      final m = pickMap(res.data);
      double d(dynamic v, double dflt) =>
          v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? dflt;
      return (warn: d(m['warn'], -1000), block: d(m['block'], -2000));
    } catch (_) {
      return (warn: -1000.0, block: -2000.0);
    }
  }

  // ----- settlement export -----

  /// `GET /partner/me/settlement/export.csv` — the raw CSV for this partner's
  /// settlements. `from`/`to` are `YYYY-MM-DD` and must be sent together (the
  /// server 400s on a half-open range); omit both for all-time. Scoped to
  /// req.partnerScope server-side, so a partner only ever gets their own rows.
  ///
  /// Returns the CSV text (with the leading BOM the server sends).
  Future<String> settlementCsv({String? from, String? to, String? status}) =>
      _api.getText('/partner/me/settlement/export.csv', query: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (status != null) 'status': status,
      });

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

  /// The partner's own review of THIS booking's customer, if one exists.
  /// Mirrors the web modal's pre-fill: GET /reviews/booking/:id then pick the
  /// row whose targetType == 'customer'. Returns null when not yet reviewed.
  Future<Review?> customerReviewFor(int bookingId) async {
    final res = await _api.get('/reviews/booking/$bookingId');
    final rows = pickList(res.data);
    for (final r in rows) {
      if ((r['targetType']?.toString() ?? '') == 'customer') {
        return Review.fromJson(r);
      }
    }
    return null;
  }

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
