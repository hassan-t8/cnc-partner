/// What a service does and does not cover.
///
/// A Dart port of the scope logic in the partner web's `BookingDetailModal.tsx`
/// (`SCOPE_SPLIT` / `splitScope`), which in turn mirrors the customer site's
/// `lib/serviceScope.ts`. The partner needs the same answer the customer was
/// given — "is the balcony in this job?" — and until now the app had no way to
/// show it.
class ServiceScope {
  const ServiceScope({
    this.description = '',
    this.included = const [],
    this.excluded = const [],
    this.equipment = const [],
  });

  final String description;
  final List<String> included;
  final List<String> excluded;
  final List<String> equipment;

  bool get isEmpty =>
      description.isEmpty &&
      included.isEmpty &&
      excluded.isEmpty &&
      equipment.isEmpty;

  /// Build from `GET /catalog/services/{slug}` → `data`.
  factory ServiceScope.fromService(Map<String, dynamic> svc) {
    final content = svc['content'] is Map
        ? Map<String, dynamic>.from(svc['content'] as Map)
        : const <String, dynamic>{};

    var included = splitScope(content['included']);
    var excluded = splitScope(content['excluded']);
    final equipment = splitScope(content['equipments']);

    // The CRM does not always fill the structured lists; older services keep
    // the same information as prose in longDescription under known headings.
    final long = (svc['longDescription'] ?? '').toString();
    if (included.isEmpty && long.isNotEmpty) {
      included = splitScope(_section(
          long, RegExp(r"What'?s included:\s*([\s\S]*?)(?:\n\s*\n|Not included:|Team:|$)",
              caseSensitive: false)));
    }
    if (excluded.isEmpty && long.isNotEmpty) {
      excluded = splitScope(_section(
          long, RegExp(r"Not included:\s*([\s\S]*?)(?:\n\s*\n|Team:|$)",
              caseSensitive: false)));
    }

    return ServiceScope(
      description: (svc['shortDescription'] ?? '').toString().trim(),
      included: included,
      excluded: excluded,
      equipment: equipment,
    );
  }

  static List<String>? _section(String source, RegExp re) {
    final m = re.firstMatch(source);
    return m == null ? null : [m.group(1) ?? ''];
  }
}

/// Split stored scope prose into points.
///
/// The CRM stores these as a handful of long strings rather than one entry per
/// point, so a faithful render is a bullet holding a paragraph. Splits on
/// semicolons and commas that are NOT inside brackets, on a full stop before a
/// capital, and on " + ".
final RegExp _scopeSplit = RegExp(r'[;,](?![^(]*\))\s*|\.\s+(?=[A-Z])|\s\+\s');

List<String> splitScope(dynamic raw) {
  if (raw is! List || raw.isEmpty) return const [];
  return raw
      .expand((chunk) => chunk.toString().split(_scopeSplit))
      .map((s) => s.trim().replaceAll(RegExp(r'\.$'), ''))
      .where((s) => s.length > 1)
      // Drop fragments that are neither a phrase nor a substantial word — the
      // split is deliberately aggressive, and this is what keeps stray
      // punctuation and initials out of the list.
      .where((s) => s.contains(RegExp(r'\s')) || s.length > 6)
      .toList();
}
