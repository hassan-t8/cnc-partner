import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Renders a booking's `serviceName` — which arrives as a single string like
/// "AC Cleaning & Repair - Bestsellers — Basic AC Cleaning (Filter + Vent)"
/// (service - sub-service — specific item) — as a clean label instead of the
/// raw dash-joined string:
///
///   AC Cleaning & Repair · Bestsellers     ← small category breadcrumb
///   Basic AC Cleaning (Filter + Vent)      ← the specific service (title)
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

  /// The specific service (last segment) — for places that only want a string.
  static String specific(String raw) {
    final p = parts(raw);
    return p.isEmpty ? (raw.trim().isEmpty ? 'Service' : raw.trim()) : p.last;
  }

  /// The "Category · Sub-service" breadcrumb (everything but the last segment).
  static String breadcrumb(String raw) {
    final p = parts(raw);
    return p.length > 1 ? p.sublist(0, p.length - 1).join(' · ') : '';
  }

  @override
  Widget build(BuildContext context) {
    final crumb = breadcrumb(serviceName);
    final title = specific(serviceName);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crumb.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
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
      ],
    );
  }
}
