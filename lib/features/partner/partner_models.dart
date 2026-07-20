import 'dart:convert' show jsonDecode;

import '../bookings/models.dart' show PartnerBooking;

int? _i(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
double _d(dynamic v) =>
    v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String _s(dynamic v) => v?.toString() ?? '';
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
// First value that parses to a positive number (skips null AND 0), else 0.
double _firstPositive(List<dynamic> vs) {
  for (final v in vs) {
    final d = _d(v);
    if (d > 0) return d;
  }
  return 0;
}

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

/// One available item (sub-service) under a partner's linked service, carrying
/// the ServiceItem id + display name + price. Mirrors the web's `catalogItems`
/// (the FULL item universe) so the worker picker can render checkboxes + prices.
class MyServiceItem {
  final int serviceItemId; // ServiceItem id — what worker_services links to
  final String name;
  final double? unitPrice;
  const MyServiceItem({
    required this.serviceItemId,
    this.name = '',
    this.unitPrice,
  });
  factory MyServiceItem.fromJson(Map<String, dynamic> j) => MyServiceItem(
        serviceItemId: _i(j['serviceItemId'] ?? j['id']) ?? 0,
        name: _s(j['name']),
        unitPrice: j['unitPrice'] == null ? null : _d(j['unitPrice']),
      );
}

/// A catalog service the partner has linked ("I provide this").
class MyService {
  final int id; // PartnerService id (used to unlink legacy whole-service rows)
  final int? catalogServiceId;
  final int? basePriceId; // links a worker/van to this service row
  final String name;
  final String? heroImage;
  final String shortDescription;
  final String categoryName;
  final String verticalName;
  final bool isActive;
  final List<int> pickedItemIds; // ServiceItem ids the partner delivers
  final List<MyServiceItem> items; // FULL item universe (catalogItems) w/ prices
  const MyService({
    required this.id,
    this.catalogServiceId,
    this.basePriceId,
    this.name = '',
    this.heroImage,
    this.shortDescription = '',
    this.categoryName = '',
    this.verticalName = '',
    this.isActive = true,
    this.pickedItemIds = const [],
    this.items = const [],
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
    // Item universe: prefer `catalogItems` (FULL set the partner offers), fall
    // back to the linked `items` for older backend responses. Mirrors the web.
    final rawItems = (j['catalogItems'] is List && (j['catalogItems'] as List).isNotEmpty)
        ? j['catalogItems']
        : (j['items'] is List ? j['items'] : const []);
    final items = (rawItems as List)
        .whereType<Map>()
        .map((e) => MyServiceItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.serviceItemId > 0)
        .toList();
    return MyService(
      id: _i(j['id']) ?? 0,
      catalogServiceId: _i(j['catalogServiceId'] ?? c['id']),
      basePriceId: _i(j['basePriceId']),
      name: _s(c['name'] ?? j['name']),
      heroImage: (c['heroImage'])?.toString(),
      shortDescription: _s(c['shortDescription']),
      categoryName: _s(cat['name']),
      verticalName: _s(vert['name']),
      isActive: j['isActive'] == null ? true : _b(j['isActive']),
      pickedItemIds: picked,
      items: items,
    );
  }
}

/// A worker's linked services, split into legacy anchor rows (`basePriceIds`)
/// and per-item picks bucketed by basePriceId (`itemsByBp`).
class WorkerServicesLink {
  final List<int> basePriceIds;
  final Map<int, List<int>> itemsByBp;
  const WorkerServicesLink({
    this.basePriceIds = const [],
    this.itemsByBp = const {},
  });
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
  final String uploadFile; // image filename or URL
  // Self-unassign penalty as a PERCENT of partnerCost. null = legacy (no
  // penalty), 0 = explicitly waived, > 0 = active penalty config.
  final double? unassignPenaltyPct;
  // Penalty mode: 'percent' (of partnerCost) | 'fixed' (flat AED) | 'none'/''.
  final String unassignPenaltyType;
  final double? unassignPenaltyAmount; // flat AED when type == 'fixed'

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
    this.uploadFile = '',
    this.unassignPenaltyPct,
    this.unassignPenaltyType = '',
    this.unassignPenaltyAmount,
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
      uploadFile: _s(j['uploadFile']),
      unassignPenaltyPct: j['unassignPenaltyPct'] == null
          ? null
          : _d(j['unassignPenaltyPct']),
      unassignPenaltyType: _s(j['unassignPenaltyType']),
      unassignPenaltyAmount: j['unassignPenaltyAmount'] == null
          ? null
          : _d(j['unassignPenaltyAmount']),
    );
  }
}

/// One page of partner bookings plus the pagination envelope, for
/// infinite-scroll. Mirrors the `{ data, pagination:{ totalRecords,
/// currentPage, totalPages, pageSize } }` shape from getPartnerBookings.
class PartnerBookingsPage {
  final List<PartnerBooking> rows;
  final int totalRecords;
  final int totalPages;
  final int currentPage;
  const PartnerBookingsPage({
    this.rows = const [],
    this.totalRecords = 0,
    this.totalPages = 1,
    this.currentPage = 1,
  });

  bool get hasMore => currentPage < totalPages;
}

/// Aggregated dashboard KPIs from `GET /partner/me/dashboard-stats`.
/// Server-side counting replaces the old "fetch 500 bookings + count on the
/// client" pattern (which truncated at the list cap). Response shape:
///   { success, data: { counts:{ bookingsToday, bookingsWeek, pendingCount,
///     workersCount, vansCount }, earningsWeek, pendingBookings:[...],
///     window:{ todayISO, weekStartISO, weekEndISO } } }
class DashboardStats {
  final int bookingsToday;
  final int bookingsWeek;
  final int pendingCount;
  final int workersCount;
  final int vansCount;
  final double earningsWeek;
  final List<PartnerBooking> pendingBookings;

  const DashboardStats({
    this.bookingsToday = 0,
    this.bookingsWeek = 0,
    this.pendingCount = 0,
    this.workersCount = 0,
    this.vansCount = 0,
    this.earningsWeek = 0,
    this.pendingBookings = const [],
  });

  factory DashboardStats.fromJson(Map<String, dynamic> j) {
    final counts =
        j['counts'] is Map ? Map<String, dynamic>.from(j['counts']) : const {};
    final pending = (j['pendingBookings'] is List)
        ? (j['pendingBookings'] as List)
            .whereType<Map>()
            .map((e) => PartnerBooking.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <PartnerBooking>[];
    return DashboardStats(
      bookingsToday: _i(counts['bookingsToday']) ?? 0,
      bookingsWeek: _i(counts['bookingsWeek']) ?? 0,
      pendingCount: _i(counts['pendingCount']) ?? 0,
      workersCount: _i(counts['workersCount']) ?? 0,
      vansCount: _i(counts['vansCount']) ?? 0,
      earningsWeek: _d(j['earningsWeek']),
      pendingBookings: pending,
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
  final double? homeLat;
  final double? homeLng;
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
    this.homeLat,
    this.homeLng,
    this.primaryZoneId,
  });

  String get name => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
  String get displayStatus => pendingActivation ? 'pending' : status;

  Worker copyWith({String? status, bool? acceptAutoAssign}) => Worker(
        id: id,
        firstName: firstName,
        lastName: lastName,
        code: code,
        email: email,
        phone: phone,
        roles: roles,
        status: status ?? this.status,
        ratingAvg: ratingAvg,
        ratingCount: ratingCount,
        sotPct: sotPct,
        pendingActivation: pendingActivation,
        acceptAutoAssign: acceptAutoAssign ?? this.acceptAutoAssign,
        homeAddress: homeAddress,
        primaryZoneId: primaryZoneId,
      );

  factory Worker.fromJson(Map<String, dynamic> j) {
    final r = j['roles'] ?? j['workerRoles'];
    // Name: prefer firstName/lastName; else split a single name field.
    var fn = _s(j['firstName'] ?? j['first_name']);
    var ln = _s(j['lastName'] ?? j['last_name']);
    if (fn.isEmpty && ln.isEmpty) {
      final full = _s(j['name'] ?? j['fullName'] ?? j['workerName']);
      if (full.isNotEmpty) {
        final parts = full.trim().split(RegExp(r'\s+'));
        fn = parts.first;
        ln = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
    }
    // Phone: combine dial code + number when stored separately.
    var phone = _s(j['phone'] ?? j['phoneNumber'] ?? j['mobile']);
    final dial = _s(j['dialCode'] ?? j['phoneDialCode']);
    if (dial.isNotEmpty && phone.isNotEmpty && !phone.startsWith('+')) {
      phone = '$dial $phone';
    }
    return Worker(
      id: _i(j['id']) ?? 0,
      firstName: fn,
      lastName: ln,
      code: _s(j['code'] ?? j['workerCode'] ?? j['employeeCode']),
      email: _s(j['email']),
      phone: phone,
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
      homeLat: j['homeLat'] == null ? null : _d(j['homeLat']),
      homeLng: j['homeLng'] == null ? null : _d(j['homeLng']),
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
  final List<int> serviceZoneIds; // additional zones beyond the primary

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
    this.serviceZoneIds = const [],
  });

  Van copyWith({String? status, bool? acceptAutoAssign}) => Van(
        id: id,
        name: name,
        code: code,
        plate: plate,
        seats: seats,
        driverName: driverName,
        status: status ?? this.status,
        parkingLat: parkingLat,
        parkingLng: parkingLng,
        parkingAddress: parkingAddress,
        homeZoneId: homeZoneId,
        acceptAutoAssign: acceptAutoAssign ?? this.acceptAutoAssign,
        driverWorkerId: driverWorkerId,
        serviceZoneIds: serviceZoneIds,
      );

  factory Van.fromJson(Map<String, dynamic> j) {
    final drv = j['driver'] is Map ? Map<String, dynamic>.from(j['driver']) : const {};
    final szRaw = j['serviceZoneIds'] ?? j['serviceZones'];
    final serviceZones = szRaw is List
        ? szRaw
            .map((e) => e is Map ? _i(e['zoneId'] ?? e['id']) : _i(e))
            .whereType<int>()
            .toList()
        : <int>[];
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
      serviceZoneIds: serviceZones,
    );
  }
}

/// An incoming auto-dispatch offer (Requests inbox).
class Offer {
  final int id;
  final int? bookingId;
  final String ref; // human booking code e.g. CNC-B-2275
  final String serviceName;
  final String customerName;
  final String? customerPhone;
  final String address;
  final double earnings;
  final double? commissionPct;
  final int rank;
  final DateTime? expiresAt;
  final DateTime? scheduledStart;
  final int crewRequired;
  final String vanName;
  // Auto-assigned team from the dispatch snapshot (web parity — shown, not
  // editable, on accept).
  final List<String> workerNames;
  final String driverName;

  // Per-service lines for a package booking (a booking can bundle several
  // services). Was ignored, so a package offer showed only its first service.
  final List<String> serviceNames;
  // True when the discount cap floor protected the partner's payout — surfaced
  // as a trust badge on the offer card (web parity: Requests page).
  final bool capApplied;
  // Payout split the web shows in the offer breakdown.
  final double onlineDue;
  final double cashHeld;

  const Offer({
    required this.id,
    this.bookingId,
    this.ref = '',
    this.serviceName = '',
    this.customerName = '',
    this.customerPhone,
    this.address = '',
    this.earnings = 0,
    this.commissionPct,
    this.rank = 1,
    this.expiresAt,
    this.scheduledStart,
    this.crewRequired = 0,
    this.vanName = '',
    this.workerNames = const [],
    this.driverName = '',
    this.serviceNames = const [],
    this.capApplied = false,
    this.onlineDue = 0,
    this.cashHeld = 0,
  });

  /// Extra service lines beyond the primary [serviceName], for the "+N more".
  int get extraServiceCount =>
      serviceNames.length > 1 ? serviceNames.length - 1 : 0;

  factory Offer.fromJson(Map<String, dynamic> j) {
    final b = j['booking'] is Map ? Map<String, dynamic>.from(j['booking']) : const {};
    final cust = b['customer'] is Map ? Map<String, dynamic>.from(b['customer']) : const {};
    final snap = j['snapshotHydrated'] is Map
        ? Map<String, dynamic>.from(j['snapshotHydrated'])
        : const {};
    String personName(dynamic w) {
      if (w is! Map) return '';
      final n =
          ('${w['firstName'] ?? ''} ${w['lastName'] ?? ''}').trim();
      return n.isNotEmpty ? n : _s(w['name']);
    }

    return Offer(
      id: _i(j['id']) ?? 0,
      bookingId: _i(j['bookingId'] ?? b['id']),
      ref: _s(b['bookingId'] ?? j['bookingRef']),
      serviceName: _s(b['serviceName'] ?? j['serviceName']),
      // Customer name/phone are on the booking row directly (booking.customerName),
      // not nested under booking.customer.
      customerName: _s(b['customerName'] ?? cust['name'] ?? j['customerName']),
      customerPhone:
          (b['customerPhone'] ?? cust['phone'] ?? j['customerPhone'])
              ?.toString(),
      address: _s(b['address'] ?? j['address']),
      // Partner take-home: prefer the first POSITIVE figure — partnerEarnings
      // can be 0 (cap edge / not yet computed), in which case we show the
      // booking amount rather than a misleading "AED 0.00".
      // Partner take-home, EXCL VAT — matching the partner web portal exactly
      // (`admin/requests/page.tsx`): prefer the server-computed, cap-aware
      // `partnerEarnings`, and fall back to `cncChargesExclVat` only for older
      // deploys that predate it.
      //
      // Deliberately does NOT fall through to cncChargesInclVat / totalPrice.
      // Those are the CUSTOMER price on a different VAT basis — showing them
      // under "Your earnings" overstates what the partner is actually paid,
      // and disagrees with the wallet ledger that eventually gets written.
      earnings: _firstPositive([
        b['partnerEarnings'],
        j['partnerEarnings'],
        b['partnerCost'],
        j['partnerCost'],
        b['cncChargesExclVat'],
      ]),
      commissionPct: b['commissionPct'] == null ? null : _d(b['commissionPct']),
      rank: _i(j['rank']) ?? 1,
      expiresAt: _dt(j['expiresAt'] ?? j['expiry']),
      scheduledStart: _dt(b['scheduledStart'] ?? j['scheduledStart']),
      crewRequired: _i(j['crewRequired'] ?? b['crewRequired']) ?? 0,
      vanName: _s((snap['van'] is Map
              ? (snap['van']['name'] ?? snap['van']['label'])
              : null) ??
          j['vanName']),
      workerNames: (snap['workers'] is List)
          ? (snap['workers'] as List)
              .map(personName)
              .where((s) => s.isNotEmpty)
              .toList()
          : const [],
      driverName: personName(snap['driver']),
      serviceNames: _parseServiceNames(b['bookingServices']),
      capApplied: _b(b['capApplied']),
      onlineDue: _d(b['onlineDue']),
      cashHeld: _d(b['cashHeld']),
    );
  }

  /// bookingServices is a per-service array (or a JSON string of one). Pull each
  /// service's display name so a package offer can list every line.
  static List<String> _parseServiceNames(dynamic raw) {
    dynamic v = raw;
    if (v is String && v.trim().isNotEmpty) {
      try {
        v = jsonDecode(v);
      } catch (_) {
        return const [];
      }
    }
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((m) =>
            _s(m['serviceName'] ?? m['name'] ?? m['service'] ?? m['title']))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// True once the acceptance window has closed.
  ///
  /// An expired offer can no longer be accepted — the server has already passed
  /// it to the next partner — so it must not sit in "New requests" pretending to
  /// be actionable. Time-based, so it also becomes true while the screen is open
  /// and the countdown runs out, without needing a refetch.
  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now());
}

class WalletInfo {
  final double balance;
  final double pendingBalance; // awaiting clearance

  /// Funds locked in a pending withdraw request. Submitting a withdraw moves
  /// the amount out of [balance] and into here immediately; approval pays it
  /// out, rejection or cancellation returns it to [balance].
  final double heldBalance;

  final double lifetimeEarnings;
  final double lifetimePaidOut;

  /// `active` | `frozen`. A frozen wallet rejects withdraw requests (409).
  final String status;
  final String frozenReason;

  const WalletInfo({
    this.balance = 0,
    this.pendingBalance = 0,
    this.heldBalance = 0,
    this.lifetimeEarnings = 0,
    this.lifetimePaidOut = 0,
    this.status = 'active',
    this.frozenReason = '',
  });

  bool get isFrozen => status.toLowerCase() == 'frozen';

  factory WalletInfo.fromJson(Map<String, dynamic> j) => WalletInfo(
        balance: _d(j['balance']),
        pendingBalance: _d(j['pendingBalance'] ?? j['pendingClearance']),
        heldBalance: _d(j['heldBalance']),
        lifetimeEarnings: _d(j['lifetimeEarnings']),
        lifetimePaidOut: _d(j['lifetimePaidOut']),
        status: j['status'] == null ? 'active' : _s(j['status']),
        frozenReason: _s(j['frozenReason']),
      );
}

/// A partner-submitted cash request — `/partner-cash-requests`.
///
/// Only `withdraw` can be created now: the backend rejects new `deposit`
/// submissions with `USE_HYPERPAY_DEPOSIT`, because deposits moved to the
/// payment gateway. Historical deposit rows still come back from `/me`.
class PartnerCashRequest {
  final int id;
  final String type; // withdraw | deposit
  final double amount;
  final String currency;
  final String status; // pending | approved | rejected | cancelled

  final String bankAccountName;
  final String bankAccountNumber;
  final String bankName;
  final String iban;

  final String paymentMethod;
  final String externalRef;
  final String notes;
  final String rejectionReason;

  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const PartnerCashRequest({
    required this.id,
    required this.type,
    required this.amount,
    required this.currency,
    required this.status,
    required this.bankAccountName,
    required this.bankAccountNumber,
    required this.bankName,
    required this.iban,
    required this.paymentMethod,
    required this.externalRef,
    required this.notes,
    required this.rejectionReason,
    required this.createdAt,
    required this.reviewedAt,
  });

  bool get isPending => status.toLowerCase() == 'pending';
  bool get isWithdraw => type.toLowerCase() == 'withdraw';

  /// Only a pending row can be cancelled; the server answers 409 otherwise.
  bool get canCancel => isPending;

  factory PartnerCashRequest.fromJson(Map<String, dynamic> j) =>
      PartnerCashRequest(
        id: j['id'] is num ? (j['id'] as num).toInt() : 0,
        type: _s(j['type']),
        amount: _d(j['amount']),
        currency: j['currency'] == null ? 'AED' : _s(j['currency']),
        status: j['status'] == null ? 'pending' : _s(j['status']),
        bankAccountName: _s(j['bankAccountName']),
        bankAccountNumber: _s(j['bankAccountNumber']),
        bankName: _s(j['bankName']),
        iban: _s(j['iban']),
        paymentMethod: _s(j['paymentMethod']),
        externalRef: _s(j['externalRef']),
        notes: _s(j['notes']),
        rejectionReason: _s(j['rejectionReason']),
        createdAt: _dt(j['createdAt']),
        reviewedAt: _dt(j['reviewedAt']),
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
  final String status; // pending_clearance | completed | reversed | failed
  final double balanceAfter;
  final DateTime? createdAt;
  final DateTime? clearedAt;
  final int? reversesId; // pairs a reversal debit with the earning it undid
  final double? grossAmount; // cash collected at the door
  final double? commissionAmount; // what the partner owes CNC on cash

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
    this.clearedAt,
    this.reversesId,
    this.grossAmount,
    this.commissionAmount,
  });

  bool get isCredit => direction == 'credit';
  bool get isPendingClearance => status == 'pending_clearance';
  bool get isReversed => status == 'reversed';
  bool get isReversal => reversesId != null;

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
        clearedAt: _dt(j['clearedAt']),
        reversesId: _i(j['reversesId'] ?? j['reversalOf']),
        grossAmount:
            j['grossAmount'] == null ? null : _d(j['grossAmount']),
        commissionAmount:
            j['commissionAmount'] == null ? null : _d(j['commissionAmount']),
      );
}

class WalletStatement {
  final WalletInfo wallet;
  final List<WalletTransaction> transactions;
  const WalletStatement(
      {this.wallet = const WalletInfo(), this.transactions = const []});
}

/// Canonical cap-aware partner settlement for one booking — the Flutter mirror
/// of the backend's `computePartnerSettlement(...)` return shape
/// (services/catalog/partnerSettlementMath.js).
///
/// INVARIANTS (guaranteed by the backend helper):
///   * onlineDue >= 0 AND cashCommission >= 0, mutually exclusive
///   * partnerNet ≈ cashHeld + onlineDue − cashCommission
///
/// `partnerNet` is the cap-aware take-home (net of CNC commission, protected
/// by the discount cap). This is the ONLY number that should be shown as the
/// partner's earnings for a booking — never the raw list price or full
/// customer-paid amount, which would OVERSTATE earnings.
class PartnerSettlement {
  final double listPrice;
  final double customerPaid;
  final double partnerNet; // cap-aware take-home
  final double partnerFloor; // protected minimum
  final double cashHeld; // cash physically held by partner (excl-VAT)
  final double onlineDue; // CNC owes partner (top-up credit)
  final double cashCommission; // partner owes CNC on cash collected
  final bool capApplied; // cap floor kicked in
  final double? commissionPct;
  final double? maxDiscountPct;

  const PartnerSettlement({
    this.listPrice = 0,
    this.customerPaid = 0,
    this.partnerNet = 0,
    this.partnerFloor = 0,
    this.cashHeld = 0,
    this.onlineDue = 0,
    this.cashCommission = 0,
    this.capApplied = false,
    this.commissionPct,
    this.maxDiscountPct,
  });

  factory PartnerSettlement.fromJson(Map<String, dynamic> j) =>
      PartnerSettlement(
        listPrice: _d(j['listPrice']),
        customerPaid: _d(j['customerPaid']),
        partnerNet: _d(j['partnerNet'] ?? j['partnerCost']),
        partnerFloor: _d(j['partnerFloor']),
        cashHeld: _d(j['cashHeld']),
        onlineDue: _d(j['onlineDue']),
        cashCommission: _d(j['cashCommission']),
        capApplied: _b(j['capApplied']),
        commissionPct:
            j['commissionPct'] == null ? null : _d(j['commissionPct']),
        maxDiscountPct:
            j['maxDiscountPct'] == null ? null : _d(j['maxDiscountPct']),
      );
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
  final int? workerId;
  final String workerName;
  final String role;
  final String status;
  final int? vanId;
  final String vanLabel; // e.g. "cli · 234"

  const BookingAssignment({
    required this.id,
    this.workerId,
    this.workerName = '',
    this.role = '',
    this.status = '',
    this.vanId,
    this.vanLabel = '',
  });

  factory BookingAssignment.fromJson(Map<String, dynamic> j) {
    final w = j['worker'] is Map ? Map<String, dynamic>.from(j['worker']) : const {};
    final dw = j['driverWorker'] is Map
        ? Map<String, dynamic>.from(j['driverWorker'])
        : const {};
    final van = j['van'] is Map ? Map<String, dynamic>.from(j['van']) : const {};
    final who = w.isNotEmpty ? w : dw;
    final name = [who['firstName'], who['lastName']]
        .where((s) => '${s ?? ''}'.isNotEmpty)
        .join(' ');
    return BookingAssignment(
      id: _i(j['id']) ?? 0,
      workerId: _i(who['id'] ?? j['workerId'] ?? j['driverWorkerId']),
      workerName: name.isNotEmpty ? name : _s(j['workerName'] ?? who['name']),
      role: _s(j['role'] ?? (dw.isNotEmpty ? 'driver' : 'crew')),
      status: _s(j['status'] ?? j['acceptanceStatus']),
      vanId: _i(van['id'] ?? j['vanId']),
      vanLabel: van.isEmpty
          ? ''
          : [van['name'], van['plate']]
              .where((s) => '${s ?? ''}'.isNotEmpty)
              .join(' · '),
    );
  }
}

/// A recurring weekly availability window (working hours).
class AvailabilityRule {
  final int id;
  final int dayOfWeek; // 0=Sun .. 6=Sat
  final String startTime; // HH:MM:SS
  final String endTime;
  final bool isActive;
  const AvailabilityRule({
    required this.id,
    this.dayOfWeek = 0,
    this.startTime = '09:00:00',
    this.endTime = '18:00:00',
    this.isActive = true,
  });
  factory AvailabilityRule.fromJson(Map<String, dynamic> j) => AvailabilityRule(
        id: _i(j['id']) ?? 0,
        dayOfWeek: _i(j['dayOfWeek']) ?? 0,
        startTime: _s(j['startTime']).isEmpty ? '09:00:00' : _s(j['startTime']),
        endTime: _s(j['endTime']).isEmpty ? '18:00:00' : _s(j['endTime']),
        isActive: j['isActive'] == null ? true : _b(j['isActive']),
      );
}

/// A one-off override on the recurring schedule for a specific date.
///   type='off'   → owner is NOT available that date (leave, sick, holiday).
///   type='extra' → owner IS available that date despite the recurring rule.
/// A null start/end pair means the whole day; a set window is a partial block.
/// dayOfWeek convention (for rules) is 0=Sun..6=Sat, matching JS getDay().
class AvailabilityException {
  final int id;
  final String date; // YYYY-MM-DD
  final String type; // 'off' | 'extra'
  final String? startTime; // HH:MM:SS or null (whole day)
  final String? endTime;
  final String reason;
  const AvailabilityException({
    required this.id,
    this.date = '',
    this.type = 'off',
    this.startTime,
    this.endTime,
    this.reason = '',
  });
  factory AvailabilityException.fromJson(Map<String, dynamic> j) {
    final st = _s(j['startTime']);
    final et = _s(j['endTime']);
    // date can arrive as "YYYY-MM-DD" or a full ISO timestamp — keep the day.
    final rawDate = _s(j['date']);
    return AvailabilityException(
      id: _i(j['id']) ?? 0,
      date: rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate,
      type: _s(j['type']).isEmpty ? 'off' : _s(j['type']),
      startTime: st.isEmpty ? null : st,
      endTime: et.isEmpty ? null : et,
      reason: _s(j['reason']),
    );
  }

  bool get isOff => type == 'off';
  bool get isWholeDay => startTime == null && endTime == null;
}

/// A customer tip on a booking (partner-scope). From GET /tips/partner/me.
class Tip {
  final int id;
  final int? bookingId;
  final double amount;
  final String status; // pending | approved | refunded | failed
  final DateTime? createdAt;
  final DateTime? paidAt;
  const Tip({
    required this.id,
    this.bookingId,
    this.amount = 0,
    this.status = '',
    this.createdAt,
    this.paidAt,
  });

  factory Tip.fromJson(Map<String, dynamic> j) => Tip(
        id: _i(j['id']) ?? 0,
        bookingId: _i(j['bookingId']),
        amount: _d(j['amount']),
        status: _s(j['status']),
        createdAt: _dt(j['createdAt']),
        paidAt: _dt(j['paidAt']),
      );

  bool get isApproved => status.toLowerCase() == 'approved';
}

/// Result of `POST /partner-deposit/initiate` — everything the WebView needs
/// to render the HyperPay COPYandPAY widget.
///
/// The widget script must be loaded from `eu-test`/`eu-prod.oppwa.com`, which
/// the response doesn't state directly. But `checkoutUrl` points at the API
/// host (`test.oppwa.com` for test, `eu-prod.oppwa.com` for prod), so
/// [widgetBase] derives the environment from it — no extra env var needed.
class DepositInit {
  final int depositId;
  final String checkoutId;
  final String checkoutUrl;

  /// The backend callback the widget POSTs the result to; it credits the
  /// wallet, then 302-redirects to the portal's /admin/deposit/result page.
  final String shopperResultUrl;

  /// e.g. 'VISA MASTER AMEX' (card) or 'APPLEPAY'.
  final String brands;

  /// HyperPay Sub-Resource Integrity hash for the widget script, when present.
  final String integrity;

  final double amount;
  final String paymentMethod; // card | apple_pay

  /// True when the same clientRequestId reused a still-pending deposit — the
  /// funds/checkout already exist, so we just re-open the widget.
  final bool deduped;

  const DepositInit({
    required this.depositId,
    required this.checkoutId,
    required this.checkoutUrl,
    required this.shopperResultUrl,
    required this.brands,
    required this.integrity,
    required this.amount,
    required this.paymentMethod,
    required this.deduped,
  });

  bool get isTest => checkoutUrl.contains('test.oppwa.com');

  /// Origin the paymentWidgets.js script loads from.
  String get widgetBase =>
      isTest ? 'https://eu-test.oppwa.com' : 'https://eu-prod.oppwa.com';

  factory DepositInit.fromJson(Map<String, dynamic> j) => DepositInit(
        depositId: (j['depositId'] is num)
            ? (j['depositId'] as num).toInt()
            : int.tryParse('${j['depositId']}') ?? 0,
        checkoutId: _s(j['checkoutId']),
        checkoutUrl: _s(j['checkoutUrl']),
        shopperResultUrl: _s(j['shopperResultUrl']),
        brands: _s(j['brands']).isEmpty ? 'VISA MASTER AMEX' : _s(j['brands']),
        integrity: _s(j['integrity']),
        amount: _d(j['amount']),
        paymentMethod: _s(j['paymentMethod']).isEmpty
            ? 'card'
            : _s(j['paymentMethod']),
        deduped: j['deduped'] == true,
      );
}

/// One row from `GET /partner-deposit/me` — a past top-up attempt.
class PartnerDepositRow {
  final int id;
  final double amount;
  final String currency;
  final String status; // pending | approved | failed | ...
  final String paymentMethod; // card | apple_pay
  final DateTime? createdAt;

  const PartnerDepositRow({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.createdAt,
  });

  bool get isApproved => status.toLowerCase() == 'approved';
  bool get isPending => status.toLowerCase() == 'pending';

  factory PartnerDepositRow.fromJson(Map<String, dynamic> j) =>
      PartnerDepositRow(
        id: _i(j['id']) ?? 0,
        amount: _d(j['amount']),
        currency: _s(j['currency']).isEmpty ? 'AED' : _s(j['currency']),
        status: _s(j['status']).isEmpty ? 'pending' : _s(j['status']),
        paymentMethod:
            _s(j['paymentMethod']).isEmpty ? 'card' : _s(j['paymentMethod']),
        createdAt: _dt(j['createdAt']),
      );
}
