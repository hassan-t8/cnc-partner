import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../bookings/models.dart';
import 'worker_repository.dart';

/// Compact "today at a glance" banner. Silent on failure (mirrors the portal).
///
/// When [jobs] is supplied (crew Jobs screen) the Done / Pending / Jobs counts
/// are computed from that list, so they always reflect the freshly-loaded data
/// (incl. pull-to-refresh): a completed job moves to "Done", everything still
/// active (accepted / in-progress / pending / confirmed) counts as "Pending".
/// When [jobs] is null (driver) it falls back to the /today-summary endpoint.
class TodaySummary extends ConsumerStatefulWidget {
  final List<Assignment>? jobs;
  const TodaySummary({super.key, this.jobs});

  @override
  ConsumerState<TodaySummary> createState() => _TodaySummaryState();
}

class _TodaySummaryState extends ConsumerState<TodaySummary> {
  // Active, not-yet-done statuses → "Pending".
  static const _pending = {
    'accepted',
    'in_progress',
    'pending_acceptance',
    'confirmed',
    'pending',
  };
  static const _dead = {'cancelled', 'declined', 'no_show'};

  Map<String, dynamic>? _summary; // endpoint data (rating + driver fallback)

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    try {
      final s = await ref.read(workerRepositoryProvider).todaySummary();
      if (mounted) setState(() => _summary = s);
    } catch (_) {}
  }

  int _n(String k) {
    final v = _summary?[k];
    return (v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the endpoint summary (rating + driver counts) fresh on refresh.
    ref.listen(tabRefreshProvider, (_, __) => _fetchSummary());

    int total, done, pending;
    final jobs = widget.jobs;
    if (jobs != null) {
      final active = jobs.where((j) => !_dead.contains(j.status)).toList();
      done = active.where((j) => j.status == 'completed').length;
      pending = active.where((j) => _pending.contains(j.status)).length;
      total = done + pending;
    } else {
      if (_summary == null) return const SizedBox.shrink();
      total = _n('total');
      done = _n('done');
      pending = _n('pending');
    }

    final rating = (_summary?['ratingAvg'] is num)
        ? (_summary!['ratingAvg'] as num).toDouble()
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
          _stat('$total', 'Jobs'),
          _divider(),
          _stat('$done', 'Done'),
          _divider(),
          _stat('$pending', 'Pending'),
          if (rating > 0) ...[
            _divider(),
            _stat(rating.toStringAsFixed(1), 'Rating',
                icon: Icons.star, color: AppColors.star),
          ],
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 28, color: AppColors.border);

  Widget _stat(String value, String label, {IconData? icon, Color? color}) =>
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
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ],
      );
}
