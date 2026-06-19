int? _i(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String _s(dynamic v) => v?.toString() ?? '';
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

class ServiceRequest {
  final int id;
  final String requestedName;
  final String description;
  final String targetPriceRange;
  final String status;
  final String adminNotes;
  final DateTime? createdAt;
  const ServiceRequest({
    required this.id,
    this.requestedName = '',
    this.description = '',
    this.targetPriceRange = '',
    this.status = '',
    this.adminNotes = '',
    this.createdAt,
  });
  factory ServiceRequest.fromJson(Map<String, dynamic> j) => ServiceRequest(
        id: _i(j['id']) ?? 0,
        requestedName: _s(j['requestedName'] ?? j['name']),
        description: _s(j['description']),
        targetPriceRange: _s(j['targetPriceRange']),
        status: _s(j['status']),
        adminNotes: _s(j['adminNotes']),
        createdAt: _dt(j['createdAt']),
      );

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'Pending review';
      case 'in_review':
        return 'In review';
      case 'approved_linked':
        return 'Approved (linked)';
      case 'approved_created':
        return 'Approved (created)';
      case 'declined':
        return 'Declined';
      default:
        return status.replaceAll('_', ' ');
    }
  }
}

/// A catalog service the partner has linked ("I provide this").
class MyService {
  final int id; // PartnerService id (used to unlink legacy whole-service rows)
  final int? catalogServiceId;
  final String name;
  final String? heroImage;
  final String shortDescription;
  final String categoryName;
  final String verticalName;
  final List<int> pickedItemIds; // ServiceItem ids the partner delivers
  const MyService({
    required this.id,
    this.catalogServiceId,
    this.name = '',
    this.heroImage,
    this.shortDescription = '',
    this.categoryName = '',
    this.verticalName = '',
    this.pickedItemIds = const [],
  });
  factory MyService.fromJson(Map<String, dynamic> j) {
    final c = j['catalog'] is Map ? Map<String, dynamic>.from(j['catalog']) : const {};
    final cat = c['category'] is Map ? Map<String, dynamic>.from(c['category']) : const {};
    final vert = cat['vertical'] is Map ? Map<String, dynamic>.from(cat['vertical']) : const {};
    final picked = (j['items'] is List)
        ? (j['items'] as List)
            .whereType<Map>()
            .map((e) => _i(e['serviceItemId'] ?? e['id']) ?? 0)
            .where((e) => e > 0)
            .toList()
        : <int>[];
    return MyService(
      id: _i(j['id']) ?? 0,
      catalogServiceId: _i(j['catalogServiceId'] ?? c['id']),
      name: _s(c['name'] ?? j['name']),
      heroImage: (c['heroImage'])?.toString(),
      shortDescription: _s(c['shortDescription']),
      categoryName: _s(cat['name']),
      verticalName: _s(vert['name']),
      pickedItemIds: picked,
    );
  }
}

/// One pickable item (sub-service) under a catalog service.
class CatalogItemNode {
  final int id; // ServiceItem id
  final String name;
  final double? unitPrice;
  const CatalogItemNode({required this.id, this.name = '', this.unitPrice});
  factory CatalogItemNode.fromJson(Map<String, dynamic> j) => CatalogItemNode(
        id: _i(j['id']) ?? 0,
        name: _s(j['name']),
        unitPrice: j['unitPrice'] == null ? null : _d(j['unitPrice']),
      );
}

/// A node in the catalog tree (Vertical -> Category -> Service).
class CatalogServiceNode {
  final int id; // CatalogService id (used to link)
  final String name;
  final String? heroImage;
  final String shortDescription;
  final List<CatalogItemNode> items;
  const CatalogServiceNode({
    required this.id,
    this.name = '',
    this.heroImage,
    this.shortDescription = '',
    this.items = const [],
  });
  factory CatalogServiceNode.fromJson(Map<String, dynamic> j) =>
      CatalogServiceNode(
        id: _i(j['id']) ?? 0,
        name: _s(j['name']),
        heroImage: (j['heroImage'])?.toString(),
        shortDescription: _s(j['shortDescription']),
        items: (j['items'] is List)
            ? (j['items'] as List)
                .whereType<Map>()
                .map((e) => CatalogItemNode.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
}

class CatalogCategory {
  final int id;
  final String name;
  final List<CatalogServiceNode> services;
  const CatalogCategory(
      {required this.id, this.name = '', this.services = const []});
  factory CatalogCategory.fromJson(Map<String, dynamic> j) => CatalogCategory(
        id: _i(j['id']) ?? 0,
        name: _s(j['name']),
        services: (j['services'] is List)
            ? (j['services'] as List)
                .whereType<Map>()
                .map((e) =>
                    CatalogServiceNode.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
}

class CatalogVertical {
  final int id;
  final String name;
  final List<CatalogCategory> categories;
  const CatalogVertical(
      {required this.id, this.name = '', this.categories = const []});
  factory CatalogVertical.fromJson(Map<String, dynamic> j) => CatalogVertical(
        id: _i(j['id']) ?? 0,
        name: _s(j['name']),
        categories: (j['categories'] is List)
            ? (j['categories'] as List)
                .whereType<Map>()
                .map((e) =>
                    CatalogCategory.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
}

class BankAccount {
  final String bankName;
  final String branchName;
  final String accountNumber;
  final String ibanNumber;
  const BankAccount({
    this.bankName = '',
    this.branchName = '',
    this.accountNumber = '',
    this.ibanNumber = '',
  });
  factory BankAccount.fromJson(Map<String, dynamic> j) => BankAccount(
        bankName: _s(j['bankName']),
        branchName: _s(j['branchName']),
        accountNumber: _s(j['accountNumber']),
        ibanNumber: _s(j['ibanNumber']),
      );
  Map<String, dynamic> toJson() => {
        'bankName': bankName,
        'branchName': branchName,
        'accountNumber': accountNumber,
        'ibanNumber': ibanNumber,
      };
  bool get isEmpty =>
      bankName.isEmpty && accountNumber.isEmpty && ibanNumber.isEmpty;
}

class Partner {
  final int id;
  final String name;
  final String contactPerson;
  final String email;
  final String website;
  final String status;
  final String code;
  final double ratingAvg;
  final int ratingCount;
  final double commissionPct;
  final List<String> phones;
  final double sotPct;
  final int bufferMinutes;
  final int priority;
  final String kind;
  final DateTime? createdAt;
  final bool hasTRN;
  final String trn;
  final double maxDiscountPercent;
  final double annualRevenueLimit;
  final bool availableOnline;
  final bool acceptAutoAssign;
  final int? primaryZoneId;
  final List<int> serviceZoneIds;
  final List<BankAccount> bankDetails;

  const Partner({
    required this.id,
    this.name = '',
    this.contactPerson = '',
    this.email = '',
    this.website = '',
    this.status = '',
    this.code = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.commissionPct = 0,
    this.phones = const [],
    this.sotPct = 0,
    this.bufferMinutes = 0,
    this.priority = 0,
    this.kind = '',
    this.createdAt,
    this.hasTRN = false,
    this.trn = '',
    this.maxDiscountPercent = 0,
    this.annualRevenueLimit = 0,
    this.availableOnline = true,
    this.acceptAutoAssign = true,
    this.primaryZoneId,
    this.serviceZoneIds = const [],
    this.bankDetails = const [],
  });

  factory Partner.fromJson(Map<String, dynamic> j) {
    final ph = j['partnerPhones'] ?? j['phones'];
    final phones = <String>[];
    if (ph is List) {
      for (final e in ph) {
        if (e is Map && e['number'] != null) {
          phones.add(e['number'].toString());
        } else if (e != null) {
          phones.add(e.toString());
        }
      }
    }
    final banks = (j['bankDetails'] is List)
        ? (j['bankDetails'] as List)
            .whereType<Map>()
            .map((e) => BankAccount.fromJson(Map<String, dynamic>.from(e)))
            .where((b) => !b.isEmpty)
            .toList()
        : <BankAccount>[];
    final zones = (j['serviceZoneIds'] is List)
        ? (j['serviceZoneIds'] as List)
            .map((e) => _i(e) ?? 0)
            .where((e) => e > 0)
            .toList()
        : <int>[];
    return Partner(
      id: _i(j['id']) ?? 0,
      name: _s(j['partnerName'] ?? j['name']),
      contactPerson: _s(j['contactPerson']),
      email: _s(j['partnerEmail'] ?? j['email']),
      website: _s(j['partnerWebsite'] ?? j['website']),
      status: _s(j['status']),
      code: _s(j['partnerCode'] ?? j['code']),
      ratingAvg: _d(j['ratingAvg']),
      ratingCount: _i(j['ratingCount']) ?? 0,
      commissionPct: _d(j['commissionPct'] ?? j['defaultCommissionPct']),
      phones: phones,
      sotPct: _d(j['sotPct']),
      bufferMinutes: _i(j['bufferMinutes']) ?? 0,
      priority: _i(j['priority']) ?? 0,
      kind: _s(j['kind']),
      createdAt: _dt(j['createdAt']),
      hasTRN: _b(j['hasTRN']),
      trn: _s(j['trn']),
      maxDiscountPercent: _d(j['maxDiscountPercent']),
      annualRevenueLimit: _d(j['annualRevenueLimit']),
      availableOnline:
          j['availableOnline'] == null ? true : _b(j['availableOnline']),
      acceptAutoAssign:
          j['acceptAutoAssign'] == null ? true : _b(j['acceptAutoAssign']),
      primaryZoneId: _i(j['primaryZoneId']),
      serviceZoneIds: zones,
      bankDetails: banks,
    );
  }
}

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
  final bool acceptAutoAssign;
  final String homeAddress;
  final int? primaryZoneId;

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
    this.acceptAutoAssign = true,
    this.homeAddress = '',
    this.primaryZoneId,
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
      acceptAutoAssign: j['acceptAutoAssign'] == null
          ? true
          : _b(j['acceptAutoAssign']),
      homeAddress: _s(j['homeAddress']),
      primaryZoneId: _i(j['primaryZoneId']),
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
  final String parkingAddress;
  final int? homeZoneId;
  final bool acceptAutoAssign;
  final int? driverWorkerId;

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
    this.parkingAddress = '',
    this.homeZoneId,
    this.acceptAutoAssign = true,
    this.driverWorkerId,
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
      parkingAddress: _s(j['parkingAddress']),
      homeZoneId: _i(j['homeZoneId']),
      acceptAutoAssign:
          j['acceptAutoAssign'] == null ? true : _b(j['acceptAutoAssign']),
      driverWorkerId: _i(j['driverWorkerId'] ?? drv['id']),
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

/// One row from the partner wallet statement (/settlement/wallet/:id/statement).
class WalletTransaction {
  final int id;
  final String type; // earning | payout | adjustment | reversal | ...
  final String direction; // credit | debit
  final double amount;
  final String description;
  final String? bookingRef;
  final String status; // pending | completed | reversed | failed
  final double balanceAfter;
  final DateTime? createdAt;

  const WalletTransaction({
    required this.id,
    this.type = '',
    this.direction = 'credit',
    this.amount = 0,
    this.description = '',
    this.bookingRef,
    this.status = '',
    this.balanceAfter = 0,
    this.createdAt,
  });

  bool get isCredit => direction == 'credit';

  factory WalletTransaction.fromJson(Map<String, dynamic> j) =>
      WalletTransaction(
        id: _i(j['id']) ?? 0,
        type: _s(j['type']),
        direction: _s(j['direction']).isEmpty ? 'credit' : _s(j['direction']),
        amount: _d(j['amount']),
        description: _s(j['description']),
        bookingRef: (j['bookingId'] ?? j['referenceId'])?.toString(),
        status: _s(j['status']),
        balanceAfter: _d(j['balanceAfter']),
        createdAt: _dt(j['createdAt']),
      );
}

class WalletStatement {
  final WalletInfo wallet;
  final List<WalletTransaction> transactions;
  const WalletStatement(
      {this.wallet = const WalletInfo(), this.transactions = const []});
}

class Review {
  final double stars;
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
        stars: _d(j['stars'] ?? j['rating']),
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
    // The API doesn't send a histogram — derive it from the reviews so the
    // distribution bars render.
    if (dist.isEmpty && revs.isNotEmpty) {
      for (final r in revs) {
        final bucket = r.stars.round().clamp(1, 5);
        dist[bucket] = (dist[bucket] ?? 0) + 1;
      }
    }
    return RatingSummary(
      avg: _d(j['ratingAvg'] ?? j['avg']),
      count: _i(j['ratingCount'] ?? j['count']) ?? 0,
      distribution: dist,
      reviews: revs,
    );
  }
}

/// A worker (or driver) assigned to a booking, from /booking-assignments.
class BookingAssignment {
  final int id;
  final String workerName;
  final String role;
  final String status;

  const BookingAssignment({
    required this.id,
    this.workerName = '',
    this.role = '',
    this.status = '',
  });

  factory BookingAssignment.fromJson(Map<String, dynamic> j) {
    final w = j['worker'] is Map ? Map<String, dynamic>.from(j['worker']) : const {};
    final dw = j['driverWorker'] is Map
        ? Map<String, dynamic>.from(j['driverWorker'])
        : const {};
    final who = w.isNotEmpty ? w : dw;
    final name = [who['firstName'], who['lastName']]
        .where((s) => '${s ?? ''}'.isNotEmpty)
        .join(' ');
    return BookingAssignment(
      id: _i(j['id']) ?? 0,
      workerName: name.isNotEmpty ? name : _s(j['workerName'] ?? who['name']),
      role: _s(j['role'] ?? (dw.isNotEmpty ? 'driver' : 'crew')),
      status: _s(j['status'] ?? j['acceptanceStatus']),
    );
  }
}
