import 'dart:convert';

/// How many workers, and for how long.
///
/// A Dart port of the partner web's `src/lib/crewHours.ts`.
///
/// A matrix (option-combo) booking carries the customer's picked `workers` and
/// `hours` on each `bookingServices` line. Other services do not set them: their
/// crew size lives in the CATALOGUE (`ServiceItem.staffRequired` →
/// `CatalogService.defaultStaffRequired`), never on the booking row — so a job
/// dispatch staffed to four read as "1 worker" until `staffRequired` was folded
/// in. We take the MAX of every known source, so a customer who picked MORE crew
/// than the catalogue default still sees their own pick.
class CrewHours {
  const CrewHours({required this.workers, required this.hours});

  final int workers;
  final double hours;
}

/// [staffRequiredHint] is the caller's own idea of the crew size — the real crew
/// rows on a booking, or an offer's `candidateSnapshot.staffRequired`.
CrewHours resolveCrewHours(
  Map<String, dynamic>? booking, {
  int? staffRequiredHint,
}) {
  final b = booking ?? const <String, dynamic>{};

  dynamic arr = b['bookingServices'];
  if (arr is String) {
    try {
      arr = jsonDecode(arr);
    } catch (_) {
      arr = null;
    }
  }
  final lines = (arr is List) ? arr : const [];

  double workers = 0;
  double hours = 0;
  for (final line in lines) {
    if (line is! Map) continue;
    final s = Map<String, dynamic>.from(line);
    final v2 = s['v2'] is Map
        ? Map<String, dynamic>.from(s['v2'] as Map)
        : const <String, dynamic>{};
    final w = _num(s['workers'] ?? v2['workers']);
    final h = _num(s['hours'] ?? v2['hours']);
    if (w > workers) workers = w;
    if (h > hours) hours = h;
  }

  // Booking-level crew (the matrix pick, stamped on the row).
  final bw = _num(b['workers']);
  if (bw > workers) workers = bw;

  // Catalogue-resolved crew size — what dispatch actually staffed the job to.
  for (final hint in [b['staffRequired'], staffRequiredHint]) {
    final n = _num(hint);
    if (n > workers) workers = n;
  }

  // Nothing configured anywhere — the CRM's own default.
  if (workers <= 0) workers = 1;

  if (hours <= 0) {
    // The scheduled window IS the catalogue duration: booking-create stamps
    // scheduledEnd = scheduledStart + the service's durationMinutes. That is
    // configured in MINUTES and routinely is not a whole hour, so rounding to
    // the nearest hour reported a 150-minute job as "3 hours" instead of 2.5.
    // Keep the fraction and let [formatHours] render it.
    final start = DateTime.tryParse('${b['scheduledStart'] ?? ''}');
    final end = DateTime.tryParse('${b['scheduledEnd'] ?? ''}');
    if (start != null && end != null && end.isAfter(start)) {
      final span = end.difference(start).inMilliseconds / 3600000;
      // Two decimals covers every catalogue duration in minutes (a minute is
      // 0.017h) and drops float noise like 2.4999999996.
      hours = (span * 100).round() / 100;
    }
    if (hours <= 0) hours = 1;
  }

  return CrewHours(workers: workers.round(), hours: hours);
}

/// "45 min" / "2.5 hours" / "3 hours" / "1 hour".
///
/// Under an hour a catalogue duration reads better in its native minutes than
/// as a fraction ("45 min", not "0.75 hours"). At an hour and above it stays in
/// hours: a fractional duration must not render as "2.5 hour", and a whole one
/// must not render as "3.0 hours".
String formatHours(double hours) {
  if (!hours.isFinite || hours <= 0) return '1 hour';
  if (hours < 1) return '${(hours * 60).round()} min';
  final rounded = (hours * 100).round() / 100;
  // Drop the trailing ".0" so 3 reads "3 hours", not "3.0 hours".
  final label =
      rounded % 1 == 0 ? rounded.toStringAsFixed(0) : rounded.toString();
  return '$label hour${rounded == 1 ? '' : 's'}';
}

double _num(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.isFinite ? v.toDouble() : 0;
  return double.tryParse(v.toString()) ?? 0;
}
