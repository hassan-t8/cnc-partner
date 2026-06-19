import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'worker_repository.dart';

/// Compact "today at a glance" banner. Silent on failure (mirrors the portal).
class TodaySummary extends ConsumerWidget {
  const TodaySummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(workerRepositoryProvider).todaySummary(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final s = snap.data!;
        int n(String k) =>
            (s[k] is num) ? (s[k] as num).toInt() : int.tryParse('${s[k]}') ?? 0;
        final rating = (s['ratingAvg'] is num)
            ? (s['ratingAvg'] as num).toDouble()
            : 0.0;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat('${n('total')}', 'Jobs'),
              _divider(),
              _stat('${n('done')}', 'Done'),
              _divider(),
              _stat('${n('pending')}', 'Pending'),
              if (rating > 0) ...[
                _divider(),
                _stat(rating.toStringAsFixed(1), 'Rating',
                    icon: Icons.star, color: AppColors.star),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: AppColors.border);

  Widget _stat(String value, String label,
          {IconData? icon, Color? color}) =>
      Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 3),
              ],
              Text(value,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: AppColors.textMuted)),
        ],
      );
}
