/// Shared helpers
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
String _s(dynamic v) => v?.toString() ?? '';

/// Payment-status labels the backend treats as "fully paid" — mirrors
/// `assertPaidOrThrow`'s PAID list in CRM_Backend services/booking/
/// cashCollection.js. Any other status (unpaid/partial/pending/'not
/// received') leaves cash collectable at the door.
const Set<String> _kPaidStatuses = {
  'paid', 'full', 'success', 'complete', 'completed',
};
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
  // Cash-collection (worker gates the Complete button on these, like the
  // partner flow + the web).
  final String payment; // cash | card | ...
  // Payment-receipt status of the parent booking ('not received' | 'pending' |
  // 'partial' | 'complete', or '' when the endpoint omits it). Drives the
  // method-agnostic cash-pending check below.
  final String paymentStatus;
  final double cashDue;
  final bool cashCollected;

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
    this.payment = '',
    this.paymentStatus = '',
    this.cashDue = 0,
    this.cashCollected = false,
  });

  /// Money still owed on this booking that the worker can collect as cash —
  /// method-agnostic, mirroring the web WorkerBookings `cashDueFor` change
  /// (2026-07-03). Cash bookings AND unpaid card/online bookings the customer
  /// never captured are collectable; only wallet-prepaid or already-paid
  /// bookings are excluded. The backend's ONLINE_PAYMENT_COVERS_CASH guard
  /// still blocks a genuine double-collection if the status flag lags.
  bool get cashPending =>
      !cashCollected &&
      cashDue > 0 &&
      payment.toLowerCase() != 'wallet' &&
      !_kPaidStatuses.contains(paymentStatus.toLowerCase());

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
        payment: payment,
        paymentStatus: paymentStatus,
        cashDue: cashDue,
        cashCollected: cashCollected ?? this.cashCollected,
      );

  factory Assignment.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking']) : j;
    final cust = b['customer'] is Map ? Map<String, dynamic>.from(b['customer']) : const {};
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
      lat: j['lat'] == null ? null : _d(j['lat']),
      lng: j['lng'] == null ? null : _d(j['lng']),
      payment: _s(b['payment'] ?? b['paymentMethod'] ?? j['payment']),
      // Payment-receipt status. workers/me/bookings denormalizes the parent
      // Booking's `status` enum ('not received'|'pending'|'partial'|'complete');
      // prefer an explicit paymentStatus if a future endpoint sends one.
      paymentStatus: _s(b['paymentStatus'] ?? b['bookingPaymentStatus'] ?? b['status']),
      // The worker bookings response ships payment/cashCollected/totalPrice/
      // coinsApplied; cash owed at the door = total − coins (clamped) unless an
      // explicit due is provided.
      cashDue: () {
        final explicit = _d(b['cashDue'] ?? b['cashOwed'] ?? b['amountDue']);
        if (explicit > 0) return explicit;
        final owed = _d(b['totalPrice'] ?? b['price']) - _d(b['coinsApplied']);
        return owed > 0 ? owed : 0.0;
      }(),
      cashCollected: (b['cashCollected'] ?? j['cashCollected']) == true,
    );
  }

  String get fullAddress =>
      [address, area].where((s) => s.trim().isNotEmpty).join(', ');

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
  });

  /// Cap-aware take-home for this booking (net of CNC commission, cap-floor
  /// protected). Alias of [partnerCost] — mirrors the backend `partnerNet`.
  double get partnerNet => partnerCost;

  /// Money still owed on this booking that the partner can collect as cash —
  /// method-agnostic, mirroring the web partner-admin `cashDueFor` (2026-07-03
  /// merged form: skip already-collected, wallet-prepaid, and fully-paid
  /// bookings; anything else is collectable). Covers unpaid/partial bookings
  /// AND online bookings the customer never captured (COD fallback).
  bool get cashPending =>
      !cashCollected &&
      cashDue > 0 &&
      payment.toLowerCase() != 'wallet' &&
      !_kPaidStatuses.contains(paymentStatus.toLowerCase());

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
      );

  factory PartnerBooking.fromJson(Map<String, dynamic> j) {
    final cust = j['customer'] is Map ? Map<String, dynamic>.from(j['customer']) : const {};
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
      paymentStatus: _s(j['paymentStatus']),
      payment: _s(j['payment'] ?? j['paymentMethod']),
      // getPartnerBookings returns total/coins (no explicit cashDue), so derive
      // the cash owed at the door = total − coins, clamped.
      cashDue: () {
        final explicit = _d(j['cashDue'] ?? j['cashOwed'] ?? j['amountDue']);
        if (explicit > 0) return explicit;
        final owed =
            _d(j['totalPrice'] ?? j['cncChargesInclVat'] ?? j['price']) -
                _d(j['coinsApplied']);
        return owed > 0 ? owed : 0.0;
      }(),
      cashCollected: j['cashCollected'] == true,
      customerReviewed: _b(j['customerReviewed']),
      zoneId: _i(j['zoneId']),
    );
  }
}
