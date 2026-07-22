/// Shared helpers
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
// Nullable double — keeps null (and unparseable/empty) as null instead of 0, so
// "no coordinate" stays distinguishable from "0,0".
double? _dn(dynamic v) => v == null
    ? null
    : (v is num ? v.toDouble() : double.tryParse('$v'));
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
String _s(dynamic v) => v?.toString() ?? '';

/// Payment-status labels the backend treats as "fully paid" — mirrors
/// `assertPaidOrThrow`'s PAID list in CRM_Backend services/booking/
/// cashCollection.js. Any other status (unpaid/partial/pending/'not
/// received') leaves cash collectable at the door.
const Set<String> _kPaidStatuses = {
  'paid', 'full', 'success', 'complete', 'completed',
};

/// Payment statuses that mean the customer was refunded AFTER paying — they owe
/// money again, so cash becomes collectable at the door regardless of the
/// collected flag / payment method / paid status. Mirrors the web partner
/// `cashDueFor` refund overlay (2026-07-22).
const Set<String> _kRefundedStatuses = {
  'partial_refunded', 'fully_refunded',
  'partial refunded', 'fully refunded', 'refunded',
};

bool _isRefundedStatus(String s) => _kRefundedStatuses.contains(s.toLowerCase());

/// Refund-aware cash owed at the door — mirrors the web partner `cashDueFor`
/// (2026-07-22). A booking refunded after being paid owes the server's net
/// `remainingAmount` again (any method), so prefer that; otherwise an explicit
/// due, then the server net remaining, then (total − coins) with
/// cncChargesInclVat covering a null totalPrice. [status] is the booking's
/// resolved payment status.
double _cashDueFrom(Map<String, dynamic> src, String status) {
  final hasRemaining = src['remainingAmount'] != null;
  final serverRemaining = _d(src['remainingAmount']);
  // Refund overlay — trust the server net remaining even for a collected /
  // wallet / paid booking, so the Collect button re-appears post-refund.
  if (_isRefundedStatus(status) && hasRemaining) {
    return serverRemaining > 0 ? serverRemaining : 0.0;
  }
  final explicit = _d(src['cashDue'] ?? src['cashOwed'] ?? src['amountDue']);
  if (explicit > 0) return explicit;
  if (hasRemaining && serverRemaining > 0) return serverRemaining;
  final total = _d(src['totalPrice'] ?? src['cncChargesInclVat'] ?? src['price']);
  final owed = total - _d(src['coinsApplied']);
  return owed > 0 ? owed : 0.0;
}
DateTime? _dt(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// A worker's job assignment (crew/driver).
class Assignment {
  final int id;
  final int? bookingId;
  final String bookingCode; // human reference, e.g. "CNC-B-2070"
  final String status;
  final String serviceName;
  final String customerName;
  final String? customerPhone;
  final String? partnerPhone;
  final String address;
  final String area;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? completedAt;
  final String role;
  final double? lat;
  final double? lng;
  // The exact map pin the customer dropped. Either a full https Maps URL or a
  // plain "lat,lng"/address string — same field the web portals link to.
  final String pinLocation;
  // Cash-collection (worker gates the Complete button on these, like the
  // partner flow + the web).
  final String payment; // cash | card | ...
  // Payment-receipt status of the parent booking ('not received' | 'pending' |
  // 'partial' | 'complete', or '' when the endpoint omits it). Drives the
  // method-agnostic cash-pending check below.
  final String paymentStatus;
  final double cashDue;
  final bool cashCollected;
  // Who this assignment is for — a crew member (workerId) or the driver
  // (driverWorkerId), plus their name. Populated by GET /booking-assignments;
  // used by the partner day-roster to group jobs per worker.
  final int? workerId;
  final int? driverWorkerId;
  final String workerName;

  const Assignment({
    required this.id,
    this.bookingId,
    this.bookingCode = '',
    this.status = '',
    this.serviceName = '',
    this.customerName = '',
    this.customerPhone,
    this.partnerPhone,
    this.address = '',
    this.area = '',
    this.scheduledStart,
    this.scheduledEnd,
    this.completedAt,
    this.role = '',
    this.lat,
    this.lng,
    this.pinLocation = '',
    this.payment = '',
    this.paymentStatus = '',
    this.cashDue = 0,
    this.cashCollected = false,
    this.workerId,
    this.driverWorkerId,
    this.workerName = '',
  });

  /// This worker's role on the booking: 'lead' | 'crew' | 'driver'.
  /// Only the LEAD runs the job lifecycle (start / collect cash / complete);
  /// other crew members and drivers get a read-only view.
  bool get isLead => role.toLowerCase() == 'lead';
  bool get isDriverRole => role.toLowerCase() == 'driver';

  /// Money still owed on this booking that the worker can collect as cash —
  /// method-agnostic, mirroring the web WorkerBookings `cashDueFor` change
  /// (2026-07-03). Cash bookings AND unpaid card/online bookings the customer
  /// never captured are collectable; only wallet-prepaid or already-paid
  /// bookings are excluded. The backend's ONLINE_PAYMENT_COVERS_CASH guard
  /// still blocks a genuine double-collection if the status flag lags.
  bool get cashPending {
    if (cashDue <= 0) return false;
    // Refund overlay — a booking refunded after being paid owes again,
    // regardless of the collected flag / method / paid status.
    if (_isRefundedStatus(paymentStatus)) return true;
    return !cashCollected &&
        payment.toLowerCase() != 'wallet' &&
        !_kPaidStatuses.contains(paymentStatus.toLowerCase());
  }

  Assignment copyWith({String? status, bool? cashCollected}) => Assignment(
        id: id,
        bookingId: bookingId,
        bookingCode: bookingCode,
        status: status ?? this.status,
        serviceName: serviceName,
        customerName: customerName,
        customerPhone: customerPhone,
        partnerPhone: partnerPhone,
        address: address,
        area: area,
        scheduledStart: scheduledStart,
        scheduledEnd: scheduledEnd,
        completedAt: completedAt,
        role: role,
        lat: lat,
        lng: lng,
        pinLocation: pinLocation,
        payment: payment,
        paymentStatus: paymentStatus,
        cashDue: cashDue,
        cashCollected: cashCollected ?? this.cashCollected,
      );

  factory Assignment.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking']) : j;
    final cust = b['customer'] is Map ? Map<String, dynamic>.from(b['customer']) : const {};
    final ps = _s(b['paymentStatus'] ?? b['bookingPaymentStatus'] ?? b['status']);
    return Assignment(
      id: _i(j['id']) ?? 0,
      bookingId: _i(j['bookingId'] ?? b['id']),
      bookingCode: _s(b['bookingId'] ?? j['bookingCode'] ?? j['bookingRef']),
      status: _s(j['status']),
      serviceName: _s(b['serviceName'] ?? b['service'] ?? j['serviceName']),
      customerName: _s(cust['name'] ?? b['customerName'] ?? j['customerName']),
      customerPhone: (cust['phone'] ?? b['customerPhone'])?.toString(),
      partnerPhone: (b['partnerPhone'] ?? j['partnerPhone'])?.toString(),
      address: _s(b['address'] ?? j['address']),
      area: _s(b['area'] ?? b['city'] ?? j['area']),
      scheduledStart: _dt(j['scheduledStart'] ?? b['scheduledStart']),
      scheduledEnd: _dt(j['scheduledEnd'] ?? b['scheduledEnd']),
      completedAt: _dt(j['completedAt']),
      role: _s(j['role']),
      // Backend stores coordinates as latitude/longitude on the booking; accept
      // the short lat/lng aliases too, from either the booking or the row.
      lat: _dn(b['latitude'] ?? b['lat'] ?? j['latitude'] ?? j['lat']),
      lng: _dn(b['longitude'] ?? b['lng'] ?? j['longitude'] ?? j['lng']),
      pinLocation:
          _s(b['pinLocation'] ?? b['location'] ?? j['pinLocation']),
      payment: _s(b['payment'] ?? b['paymentMethod'] ?? j['payment']),
      // Payment-receipt status. workers/me/bookings denormalizes the parent
      // Booking's `status` enum ('not received'|'pending'|'partial'|'complete');
      // prefer an explicit paymentStatus if a future endpoint sends one.
      paymentStatus: ps,
      // Cash owed at the door — refund-aware, prefers the server's net
      // remaining, falls back to (total − coins). See _cashDueFrom.
      cashDue: _cashDueFrom(b, ps),
      // Truthy parse: the backend sends cashCollected as an int (1/0), and
      // `1 == true` is false in Dart — using `== true` made a collected cash
      // booking reappear as "Collect". _b handles 1 / '1' / true.
      cashCollected: _b(b['cashCollected'] ?? j['cashCollected']),
      workerId: _i(j['workerId']),
      driverWorkerId: _i(j['driverWorkerId']),
      workerName: _s((j['worker'] is Map ? j['worker']['name'] : null) ??
          (j['driverWorker'] is Map ? j['driverWorker']['name'] : null) ??
          ''),
    );
  }

  String get fullAddress =>
      [address, area].where((s) => s.trim().isNotEmpty).join(', ');

  /// Best directions/map link for this booking, or null when there's nothing to
  /// point at. Mirrors the web portals: prefer the customer's dropped pin, then
  /// exact coordinates, then the text address.
  ///   • pinLocation that's already an https link → open it verbatim (it points
  ///     at the exact spot the customer picked).
  ///   • otherwise build a Google Maps directions URL to the precise
  ///     destination (pin string → coordinates → address).
  String? get mapUrl {
    final pin = pinLocation.trim();
    if (pin.startsWith('http')) return pin;
    String? dest;
    if (pin.isNotEmpty) {
      dest = pin; // usually "lat,lng" or a place name
    } else if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      dest = '$lat,$lng';
    } else if (fullAddress.isNotEmpty) {
      dest = fullAddress;
    }
    if (dest == null) return null;
    return 'https://www.google.com/maps/dir/?api=1&destination='
        '${Uri.encodeComponent(dest)}';
  }

  /// Human-facing booking reference: the "CNC-B-…" code when present,
  /// otherwise the numeric id prefixed with '#'.
  String get bookingRef =>
      bookingCode.isNotEmpty ? bookingCode : '#${bookingId ?? id}';
}

/// A partner-side booking row.
class PartnerBooking {
  final int id;
  final String ref;
  final String customerName;
  final String serviceName;
  final String area;
  final String status;
  final DateTime? scheduledStart;
  // Cap-aware take-home (partnerNet). `partnerCost` is the Booking column
  // mirror of the central settlement helper's cap-aware `partnerNet` — net of
  // CNC commission and protected by the partner's discount cap. This is the
  // canonical per-booking take-home; do NOT re-derive it from list price.
  final double partnerCost;
  // partnerFloor = listPrice × (1 − maxDiscountPct) × (1 − commissionPct) —
  // the protected minimum the partner is guaranteed when a customer discount
  // pushes past the cap.
  final double partnerFloor;
  // True when the discount cap floor kicked in (customer-paid dropped below
  // the cap threshold), so partnerCost was raised to partnerFloor.
  final bool capApplied;
  final bool requiresStartOtp;
  final String paymentStatus;
  final String payment; // cash | card | ...
  final double cashDue;
  final bool cashCollected;
  // True once the partner has left a review for THIS booking's customer.
  // Mirrors the web's per-booking `customerReviewed` flag from
  // getPartnerBookings (batch-loaded Review rows with targetType 'customer').
  final bool customerReviewed;
  final int? zoneId;

  // Customer contact + destination. The getPartnerBookings response carries all
  // of this (Booking model spreads `...b`); the app just never parsed it, so a
  // partner-admin couldn't phone the customer or navigate to the job.
  final String? customerPhone;
  final String? customerEmail;
  final String address;
  final String specialInstructions;
  final String accessInstructions;
  final double? lat;
  final double? lng;
  final String pinLocation;

  const PartnerBooking({
    required this.id,
    this.ref = '',
    this.zoneId,
    this.customerName = '',
    this.serviceName = '',
    this.area = '',
    this.status = '',
    this.scheduledStart,
    this.partnerCost = 0,
    this.partnerFloor = 0,
    this.capApplied = false,
    this.requiresStartOtp = false,
    this.paymentStatus = '',
    this.payment = '',
    this.cashDue = 0,
    this.cashCollected = false,
    this.customerReviewed = false,
    this.customerPhone,
    this.customerEmail,
    this.address = '',
    this.specialInstructions = '',
    this.accessInstructions = '',
    this.lat,
    this.lng,
    this.pinLocation = '',
  });

  /// Address + area for display, deduped/joined.
  String get fullAddress =>
      [address, area].where((s) => s.trim().isNotEmpty).join(', ');

  /// Best directions link (pin → coordinates → text address), or null when
  /// there's nothing to point at. Mirrors the Assignment.mapUrl logic.
  String? get mapUrl {
    final pin = pinLocation.trim();
    if (pin.startsWith('http')) return pin;
    String? dest;
    if (pin.isNotEmpty) {
      dest = pin;
    } else if (lat != null && lng != null && !(lat == 0 && lng == 0)) {
      dest = '$lat,$lng';
    } else if (fullAddress.isNotEmpty) {
      dest = fullAddress;
    }
    if (dest == null) return null;
    return 'https://www.google.com/maps/dir/?api=1&destination='
        '${Uri.encodeComponent(dest)}';
  }

  /// Cap-aware take-home for this booking (net of CNC commission, cap-floor
  /// protected). Alias of [partnerCost] — mirrors the backend `partnerNet`.
  double get partnerNet => partnerCost;

  /// Money still owed on this booking that the partner can collect as cash —
  /// method-agnostic, mirroring the web partner-admin `cashDueFor` (2026-07-03
  /// merged form: skip already-collected, wallet-prepaid, and fully-paid
  /// bookings; anything else is collectable). Covers unpaid/partial bookings
  /// AND online bookings the customer never captured (COD fallback).
  bool get cashPending {
    if (cashDue <= 0) return false;
    // Refund overlay — a booking refunded after being paid owes again,
    // regardless of the collected flag / method / paid status.
    if (_isRefundedStatus(paymentStatus)) return true;
    return !cashCollected &&
        payment.toLowerCase() != 'wallet' &&
        !_kPaidStatuses.contains(paymentStatus.toLowerCase());
  }

  PartnerBooking copyWith(
          {String? status, bool? cashCollected, bool? customerReviewed}) =>
      PartnerBooking(
        id: id,
        ref: ref,
        customerName: customerName,
        serviceName: serviceName,
        area: area,
        status: status ?? this.status,
        scheduledStart: scheduledStart,
        partnerCost: partnerCost,
        partnerFloor: partnerFloor,
        capApplied: capApplied,
        requiresStartOtp: requiresStartOtp,
        paymentStatus: paymentStatus,
        payment: payment,
        cashDue: cashDue,
        cashCollected: cashCollected ?? this.cashCollected,
        customerReviewed: customerReviewed ?? this.customerReviewed,
        zoneId: zoneId,
        customerPhone: customerPhone,
        customerEmail: customerEmail,
        address: address,
        specialInstructions: specialInstructions,
        accessInstructions: accessInstructions,
        lat: lat,
        lng: lng,
        pinLocation: pinLocation,
      );

  factory PartnerBooking.fromJson(Map<String, dynamic> j) {
    final cust = j['customer'] is Map ? Map<String, dynamic>.from(j['customer']) : const {};
    final ps = _s(j['paymentStatus'] ?? j['bookingPaymentStatus']);
    return PartnerBooking(
      id: _i(j['id']) ?? 0,
      ref: _s(j['bookingId'] ?? j['ref'] ?? j['reference'] ?? j['bookingRef'] ??
          j['id']),
      customerName: _s(cust['name'] ?? j['customerName']),
      serviceName: _s(j['serviceName'] ?? j['service']),
      area: _s(j['area'] ?? j['city']),
      status: _s(j['dispatchStatus'] ?? j['status']),
      scheduledStart: _dt(j['scheduledStart'] ?? j['date']),
      // Cap-aware take-home (partnerNet mirror). Prefer the explicit
      // partnerNet field if the API ever returns it; else the Booking column
      // mirror `partnerCost`.
      partnerCost: _d(j['partnerNet'] ?? j['partnerCost']),
      partnerFloor: _d(j['partnerFloor']),
      capApplied: _b(j['capApplied']),
      requiresStartOtp: j['requiresStartOtp'] == true,
      paymentStatus: ps,
      payment: _s(j['payment'] ?? j['paymentMethod']),
      // Cash owed at the door — refund-aware, prefers the server's net
      // remaining, falls back to (total − coins). See _cashDueFrom.
      cashDue: _cashDueFrom(j, ps),
      cashCollected: _b(j['cashCollected']),
      customerReviewed: _b(j['customerReviewed']),
      zoneId: _i(j['zoneId']),
      customerPhone: _s(cust['phone'] ?? j['phone'] ?? j['customerPhone']),
      customerEmail: _s(cust['email'] ?? j['email'] ?? j['customerEmail']),
      address: _s(j['address'] ?? cust['address']),
      specialInstructions: _s(j['specialInstructions'] ?? j['instructions']),
      accessInstructions: _s(j['accessInstructions']),
      lat: _dn(j['latitude'] ?? j['lat']),
      lng: _dn(j['longitude'] ?? j['lng']),
      pinLocation: _s(j['pinLocation'] ?? j['location']),
    );
  }
}
