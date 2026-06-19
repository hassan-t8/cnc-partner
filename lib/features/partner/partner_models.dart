int? _i(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String _s(dynamic v) => v?.toString() ?? '';
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class Zone {
  final int id;
  final String name;
  final String emirate;
  const Zone({required this.id, this.name = '', this.emirate = ''});
  factory Zone.fromJson(Map<String, dynamic> j) => Zone(
        id: _i(j['id']) ?? 0,
        name: _s(j['name'] ?? j['area']),
        emirate: _s(j['emirate'] ?? j['parentName']),
      );
  String get label => emirate.isEmpty ? name : '$name, $emirate';
}

class Worker {
  final int id;
  final String firstName;
  final String lastName;
  final String code;
  final String email;
  final String phone;
  final List<String> roles;
  final String status;
  final double ratingAvg;
  final int ratingCount;
  final double sotPct;
  final bool pendingActivation;

  const Worker({
    required this.id,
    this.firstName = '',
    this.lastName = '',
    this.code = '',
    this.email = '',
    this.phone = '',
    this.roles = const [],
    this.status = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.sotPct = 0,
    this.pendingActivation = false,
  });

  String get name => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
  String get displayStatus => pendingActivation ? 'pending' : status;

  factory Worker.fromJson(Map<String, dynamic> j) {
    final r = j['roles'];
    return Worker(
      id: _i(j['id']) ?? 0,
      firstName: _s(j['firstName']),
      lastName: _s(j['lastName']),
      code: _s(j['code']),
      email: _s(j['email']),
      phone: _s(j['phone']),
      roles: r is List ? r.map((e) => '$e').toList() : const [],
      status: _s(j['status']),
      ratingAvg: _d(j['ratingAvg']),
      ratingCount: _i(j['ratingCount']) ?? 0,
      sotPct: _d(j['sotPct'] ?? j['startOnTimePct']),
      pendingActivation: _b(j['pendingActivation']),
    );
  }
}

class Van {
  final int id;
  final String name;
  final String code;
  final String plate;
  final int seats;
  final String driverName;
  final String status;
  final double? parkingLat;
  final double? parkingLng;

  const Van({
    required this.id,
    this.name = '',
    this.code = '',
    this.plate = '',
    this.seats = 0,
    this.driverName = '',
    this.status = '',
    this.parkingLat,
    this.parkingLng,
  });

  factory Van.fromJson(Map<String, dynamic> j) {
    final drv = j['driver'] is Map ? Map<String, dynamic>.from(j['driver']) : const {};
    return Van(
      id: _i(j['id']) ?? 0,
      name: _s(j['name']),
      code: _s(j['code']),
      plate: _s(j['plate']),
      seats: _i(j['seats']) ?? 0,
      driverName: _s(drv['firstName'] ?? j['driverName']),
      status: _s(j['status']),
      parkingLat: j['parkingLat'] == null ? null : _d(j['parkingLat']),
      parkingLng: j['parkingLng'] == null ? null : _d(j['parkingLng']),
    );
  }
}

/// An incoming auto-dispatch offer (Requests inbox).
class Offer {
  final int id;
  final int? bookingId;
  final String serviceName;
  final String customerName;
  final String? customerPhone;
  final String address;
  final double earnings;
  final int rank;
  final DateTime? expiresAt;
  final int crewRequired;
  final String vanName;

  const Offer({
    required this.id,
    this.bookingId,
    this.serviceName = '',
    this.customerName = '',
    this.customerPhone,
    this.address = '',
    this.earnings = 0,
    this.rank = 1,
    this.expiresAt,
    this.crewRequired = 0,
    this.vanName = '',
  });

  factory Offer.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking']) : const {};
    final cust = b['customer'] is Map ? Map<String, dynamic>.from(b['customer']) : const {};
    return Offer(
      id: _i(j['id']) ?? 0,
      bookingId: _i(j['bookingId'] ?? b['id']),
      serviceName: _s(b['serviceName'] ?? j['serviceName']),
      customerName: _s(cust['name'] ?? j['customerName']),
      customerPhone: (cust['phone'])?.toString(),
      address: _s(b['address'] ?? j['address']),
      earnings: _d(j['earnings'] ?? j['partnerCost'] ?? b['partnerCost']),
      rank: _i(j['rank']) ?? 1,
      expiresAt: _dt(j['expiresAt'] ?? j['expiry']),
      crewRequired: _i(j['crewRequired'] ?? b['crewRequired']) ?? 0,
      vanName: _s(j['vanName']),
    );
  }
}

class WalletInfo {
  final double balance;
  final double lifetimeEarnings;
  final double lifetimePaidOut;
  const WalletInfo(
      {this.balance = 0, this.lifetimeEarnings = 0, this.lifetimePaidOut = 0});
  factory WalletInfo.fromJson(Map<String, dynamic> j) => WalletInfo(
        balance: _d(j['balance']),
        lifetimeEarnings: _d(j['lifetimeEarnings']),
        lifetimePaidOut: _d(j['lifetimePaidOut']),
      );
}

class Review {
  final int stars;
  final String comment;
  final String customerName;
  final String? bookingRef;
  final DateTime? createdAt;
  const Review(
      {this.stars = 0,
      this.comment = '',
      this.customerName = '',
      this.bookingRef,
      this.createdAt});
  factory Review.fromJson(Map<String, dynamic> j) => Review(
        stars: _i(j['stars'] ?? j['rating']) ?? 0,
        comment: _s(j['comment']),
        customerName: _s(j['customerName'] ?? j['customer']),
        bookingRef: (j['bookingId'] ?? j['bookingRef'])?.toString(),
        createdAt: _dt(j['createdAt']),
      );
}

class RatingSummary {
  final double avg;
  final int count;
  final Map<int, int> distribution; // stars 1..5 → count
  final List<Review> reviews;
  const RatingSummary(
      {this.avg = 0,
      this.count = 0,
      this.distribution = const {},
      this.reviews = const []});
  factory RatingSummary.fromJson(Map<String, dynamic> j) {
    final dist = <int, int>{};
    final rd = j['distribution'];
    if (rd is Map) {
      rd.forEach((k, v) => dist[int.tryParse('$k') ?? 0] = _i(v) ?? 0);
    }
    final revs = (j['reviews'] is List)
        ? (j['reviews'] as List)
            .whereType<Map>()
            .map((e) => Review.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <Review>[];
    return RatingSummary(
      avg: _d(j['ratingAvg'] ?? j['avg']),
      count: _i(j['ratingCount'] ?? j['count']) ?? 0,
      distribution: dist,
      reviews: revs,
    );
  }
}
