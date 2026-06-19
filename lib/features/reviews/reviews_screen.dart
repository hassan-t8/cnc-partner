import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../partner/partner_models.dart';
import '../partner/partner_repository.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';

/// Shared reviews screen for both partner ("partner") and worker ("worker").
class ReviewsScreen extends ConsumerStatefulWidget {
  final bool worker;
  const ReviewsScreen({super.key, this.worker = false});
  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  late Future<RatingSummary> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<RatingSummary> _load() async {
    if (widget.worker) {
      final res =
          await ref.read(apiClientProvider).get('/workers/me/rating-summary');
      return RatingSummary.fromJson(pickMap(res.data));
    }
    return ref.read(partnerRepositoryProvider).partnerRatingSummary();
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<RatingSummary>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList(height: 120);
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load reviews.', onRetry: _reload);
            }
            final s = snap.data!;
            if (s.count == 0) {
              return const EmptyState(
                  icon: Icons.reviews_outlined,
                  title: 'No reviews yet',
                  subtitle: 'Your first review is on the way.');
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(s),
                const SizedBox(height: 16),
                ...s.reviews.map(_reviewCard),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(RatingSummary s) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Column(
              children: [
                Text(s.avg.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 38, fontWeight: FontWeight.w900)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      5,
                      (i) => Icon(
                            i < s.avg.round()
                                ? Icons.star
                                : Icons.star_border,
                            size: 16,
                            color: AppColors.star,
                          )),
                ),
                Text('${s.count} reviews',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [5, 4, 3, 2, 1].map((star) {
                  final c = s.distribution[star] ?? 0;
                  final frac = s.count == 0 ? 0.0 : c / s.count;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text('$star',
                            style: const TextStyle(fontSize: 11)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: frac,
                              minHeight: 6,
                              backgroundColor: AppColors.border,
                              color: AppColors.star,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                            width: 22,
                            child: Text('$c',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 11))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );

  Widget _reviewCard(Review r) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.brand50,
                  child: Text(
                      (r.customerName.isNotEmpty ? r.customerName[0] : '?')
                          .toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.brand700,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      r.customerName.isEmpty ? 'Customer' : r.customerName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      5,
                      (i) => Icon(
                          i < r.stars ? Icons.star : Icons.star_border,
                          size: 14,
                          color: AppColors.star)),
                ),
              ],
            ),
            if (r.comment.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(r.comment,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
            if (r.createdAt != null) ...[
              const SizedBox(height: 4),
              Text(DateFormat('d MMM y').format(r.createdAt!),
                  style:
                      TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ],
        ),
      );
}
