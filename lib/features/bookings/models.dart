/// Shared helpers
int? _i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String _s(dynamic v) => v?.toString() ?? '';
DateTime? _dt(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// A worker's job assignment (crew/driver).
class Assignment {
  final int id;
  final int? bookingId;
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

  const Assignment({
    required this.id,
    this.bookingId,
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
  });

  factory Assignment.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking']) : j;
    final cust = b['customer'] is Map ? Map<String, dynamic>.from(b['customer']) : const {};
    return Assignment(
      id: _i(j['id']) ?? 0,
      bookingId: _i(j['bookingId'] ?? b['id']),
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
    );
  }

  String get fullAddress =>
      [address, area].where((s) => s.trim().isNotEmpty).join(', ');
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
  final double partnerCost;
  final bool requiresStartOtp;
  final String paymentStatus;

  const PartnerBooking({
    required this.id,
    this.ref = '',
    this.customerName = '',
    this.serviceName = '',
    this.area = '',
    this.status = '',
    this.scheduledStart,
    this.partnerCost = 0,
    this.requiresStartOtp = false,
    this.paymentStatus = '',
  });

  factory PartnerBooking.fromJson(Map<String, dynamic> j) {
    final cust = j['customer'] is Map ? Map<String, dynamic>.from(j['customer']) : const {};
    return PartnerBooking(
      id: _i(j['id']) ?? 0,
      ref: _s(j['ref'] ?? j['reference'] ?? j['bookingRef'] ?? j['id']),
      customerName: _s(cust['name'] ?? j['customerName']),
      serviceName: _s(j['serviceName'] ?? j['service']),
      area: _s(j['area'] ?? j['city']),
      status: _s(j['dispatchStatus'] ?? j['status']),
      scheduledStart: _dt(j['scheduledStart'] ?? j['date']),
      partnerCost: _d(j['partnerCost']),
      requiresStartOtp: j['requiresStartOtp'] == true,
      paymentStatus: _s(j['paymentStatus']),
    );
  }
}
