import 'package:jwt_decoder/jwt_decoder.dart';

/// The portal's three role areas.
enum RoleArea { partner, driver, crew }

/// Decoded partner-portal JWT + role helpers (mirrors auth.ts).
class JwtUser {
  final int id;
  final String? email;
  final String role; // partner | driver | worker
  final int? partnerId;
  final int? workerId;
  final List<String> workerRoles; // crew / driver (for role=worker)
  final String? firstName;
  final String? lastName;
  final int? exp;

  const JwtUser({
    required this.id,
    required this.role,
    this.email,
    this.partnerId,
    this.workerId,
    this.workerRoles = const [],
    this.firstName,
    this.lastName,
    this.exp,
  });

  factory JwtUser.fromClaims(Map<String, dynamic> j) {
    int? asInt(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
    final wr = j['workerRoles'];
    return JwtUser(
      id: asInt(j['id']) ?? 0,
      email: j['email']?.toString(),
      role: (j['role'] ?? '').toString(),
      partnerId: asInt(j['partnerId']),
      workerId: asInt(j['workerId']),
      workerRoles: wr is List ? wr.map((e) => '$e').toList() : const [],
      firstName: j['firstName']?.toString(),
      lastName: j['lastName']?.toString(),
      exp: asInt(j['exp']),
    );
  }

  /// Parse + validate a token. Returns null if invalid/expired/unknown-role.
  static JwtUser? tryParse(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      if (JwtDecoder.isExpired(token)) return null;
      final user = JwtUser.fromClaims(JwtDecoder.decode(token));
      if (user.areas.isEmpty) return null; // unrecognised role
      return user;
    } catch (_) {
      return null;
    }
  }

  bool get isPartner => role == 'partner';
  bool get isDriver =>
      role == 'driver' || (role == 'worker' && workerRoles.contains('driver'));
  bool get isCrew => role == 'worker' && workerRoles.contains('crew');

  /// Areas this user may enter.
  List<RoleArea> get areas {
    final out = <RoleArea>[];
    if (isPartner) out.add(RoleArea.partner);
    if (isDriver) out.add(RoleArea.driver);
    if (isCrew) out.add(RoleArea.crew);
    return out;
  }

  /// Where the user should land after login (mirrors landingForUser()).
  RoleArea get landingArea {
    if (isPartner) return RoleArea.partner;
    if (isDriver) return RoleArea.driver;
    return RoleArea.crew;
  }

  bool canEnter(RoleArea area) => areas.contains(area);

  /// The account holder's full name from the token (firstName + lastName).
  /// Empty when the token carries neither — callers show it only when present.
  String get fullName => [firstName, lastName]
      .where((s) => s != null && s.trim().isNotEmpty)
      .map((s) => s!.trim())
      .join(' ');

  /// Greeting name (firstName → email local-part → "there").
  String get greetingName {
    if (firstName != null && firstName!.trim().isNotEmpty) return firstName!;
    final e = email;
    if (e != null && e.contains('@')) {
      final local = e.split('@').first;
      if (local.isNotEmpty) {
        return local[0].toUpperCase() + local.substring(1);
      }
    }
    return 'there';
  }

  String get roleLabel {
    if (isPartner) return 'Partner';
    if (isDriver && isCrew) return 'Driver · Crew';
    if (isDriver) return 'Driver';
    return 'Crew';
  }
}
