import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../core/theme/app_colors.dart';

/// A shimmering placeholder list of cards for loading states.
///
/// Standalone (the default) it is the page's own scroll view — it scrolls and
/// fills the space. Set [nested] when placing it INSIDE another scroll view
/// (e.g. as one item of an outer `ListView`): it then shrink-wraps, gives up
/// the [PrimaryScrollController], and stops scrolling on its own. Without that,
/// two vertical scrollables fight over the primary controller and Flutter
/// throws "A GlobalKey was used multiple times ... _ScrollSemantics".
class LoadingList extends StatelessWidget {
  final int count;
  final double height;
  final bool nested;
  const LoadingList({
    super.key,
    this.count = 6,
    this.height = 84,
    this.nested = false,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: count,
        shrinkWrap: nested,
        primary: nested ? false : null,
        physics: nested ? const NeverScrollableScrollPhysics() : null,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Loading placeholder shaped like the Partner dashboard.
///
/// The dashboard used a generic `LoadingList(count: 4, height: 96)` — four
/// identical rows, which matched nothing on the real screen and left the lower
/// half blank. This mirrors the actual layout (greeting → KPI row → earnings
/// card → offers) so the transition to real content doesn't jump.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget box(double h, {double? w, double r = 12}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(r),
          ),
        );

    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting
          box(24, w: 180, r: 8),
          const SizedBox(height: 18),
          // KPI row (Today / Week / Earnings)
          Row(
            children: [
              Expanded(child: box(84)),
              const SizedBox(width: 12),
              Expanded(child: box(84)),
            ],
          ),
          const SizedBox(height: 12),
          // Weekly earnings card
          box(104),
          const SizedBox(height: 22),
          // "Pending offers" section heading
          box(16, w: 140, r: 8),
          const SizedBox(height: 12),
          // Offer cards — enough to fill the rest of the screen.
          for (var i = 0; i < 3; i++) ...[
            box(96),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState(
      {super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: AppColors.brand50, shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.brand600, size: 34),
            ),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, color: AppColors.textFaint, size: 44),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
