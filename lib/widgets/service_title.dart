import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Renders a booking's resolved `serviceName` — "Holiday Home / Airbnb Turnover
/// Cleaning - 1 Bedroom" (service, then the tier) — as a clean label:
///
///   Holiday Home / Airbnb Turnover Cleaning   ← the SERVICE (title)
///   1 Bedroom                                 ← the tier, underneath
///
/// The service leads. It used to be the other way round: this widget took the
/// LAST dash-separated segment as the headline, so a job read "1 Bedroom" — a
/// size, with no hint of what was being done to it. The partner web fixed the
/// same bug by leading with the catalogue name (see resolveServiceName), and
/// this follows it.
///
/// Used in every booking/job card + detail header across all roles so the
/// presentation is consistent.
class ServiceTitle extends StatelessWidget {
  final String serviceName;
  final double titleSize;
  final int maxLines;
  final Color? titleColor;
  final Color? crumbColor;
  const ServiceTitle(
    this.serviceName, {
    super.key,
    this.titleSize = 15,
    this.maxLines = 2,
    this.titleColor,
    this.crumbColor,
  });

  // Split on a dash that is surrounded by spaces ("A - B", "A — B") so we don't
  // break hyphenated names like "E-11" or "Add-on".
  static final RegExp _sep = RegExp(r'\s+[—–-]\s+');

  static List<String> parts(String raw) => raw
      .split(_sep)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// The SERVICE (first segment) — for places that only want one string.
  static String primary(String raw) {
    final p = parts(raw);
    return p.isEmpty ? (raw.trim().isEmpty ? 'Service' : raw.trim()) : p.first;
  }

  /// The tier / item detail (everything after the service).
  static String detail(String raw) {
    final p = parts(raw);
    return p.length > 1 ? p.sublist(1).join(' · ') : '';
  }

  @override
  Widget build(BuildContext context) {
    final title = primary(serviceName);
    final crumb = detail(serviceName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: titleSize,
            color: titleColor,
            height: 1.2,
          ),
        ),
        if (crumb.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              crumb,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: crumbColor ?? AppColors.textMuted,
                fontSize: (titleSize - 3).clamp(10, 13),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
