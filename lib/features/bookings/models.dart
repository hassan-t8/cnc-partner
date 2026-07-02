/// Shared helpers
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
String _s(dynamic v) => v?.toString() ?? '';
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
    this.cashDue = 0,
    this.cashCollected = false,
  });

  /// Cash booking with money still owed at the door.
  bool get cashPending =>
      payment.toLowerCase() == 'cash' && cashDue > 0 && !cashCollected;

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
  });

  /// Cap-aware take-home for this booking (net of CNC commission, cap-floor
  /// protected). Alias of [partnerCost] — mirrors the backend `partnerNet`.
  double get partnerNet => partnerCost;

  /// Cash booking with money still owed at the door.
  bool get cashPending =>
      payment.toLowerCase() == 'cash' && cashDue > 0 && !cashCollected;

  PartnerBooking copyWith({String? status, bool? cashCollected}) =>
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
      zoneId: _i(j['zoneId']),
    );
  }
}
