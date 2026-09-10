import 'dart:convert';

/// The REAL catalogue service name for a booking.
///
/// A Dart port of the partner web's `src/lib/serviceName.ts`, and it fixes the
/// same bug here.
///
/// The crew / driver / team projections denormalise a booking into `service`
/// (the VERTICAL bucket — "Cleaning") and `serviceName` (the combined
/// "Cleaning - 1 Bedroom"). The service the customer actually booked — "Holiday
/// Home / Airbnb Turnover Cleaning" — lives only in the `bookingServices` JSON,
/// on each line's own `serviceName`. That JSON IS in the projection, so there
/// is no excuse for reading round it.
///
/// Prefer the line's name and append the tier; fall back to the denormalised
/// fields only for legacy or CRM-made bookings that have no line name.
///
/// Why this matters: the app previously showed the tier as the headline (via
/// `ServiceTitle.specific`), so a job read "1 Bedroom" — a size, with no hint
/// of what was being done to it.
String resolveServiceName(Map<String, dynamic>? booking) {
  final b = booking ?? const <String, dynamic>{};

  dynamic arr = b['bookingServices'];
  // The column is JSON; some projections send it already decoded, others as a
  // string. Anything unparseable is simply not a list, and falls through.
  if (arr is String) {
    try {
      arr = jsonDecode(arr);
    } catch (_) {
      arr = null;
    }
  }

  Map<String, dynamic>? first;
  if (arr is List && arr.isNotEmpty && arr.first is Map) {
    first = Map<String, dynamic>.from(arr.first as Map);
  }

  final real = (first?['serviceName'] ?? '').toString().trim();
  final tier =
      (first?['subSubService'] ?? first?['subService'] ?? '').toString().trim();

  if (real.isNotEmpty) {
    // A tier equal to the name adds nothing but noise.
    return (tier.isNotEmpty && tier != real) ? '$real - $tier' : real;
  }
  return (b['service'] ?? b['serviceName'] ?? '').toString().trim();
}
