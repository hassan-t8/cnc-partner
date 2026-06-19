import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/status_badge.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerWorkersScreen extends ConsumerStatefulWidget {
  const PartnerWorkersScreen({super.key});
  @override
  ConsumerState<PartnerWorkersScreen> createState() =>
      _PartnerWorkersScreenState();
}

class _PartnerWorkersScreenState extends ConsumerState<PartnerWorkersScreen> {
  late Future<List<Worker>> _future;
  String _query = '';
  String _role = 'all';

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).workers();
  }

  void _reload() =>
      setState(() => _future = ref.read(partnerRepositoryProvider).workers());

  List<Worker> _filter(List<Worker> all) {
    final q = _query.toLowerCase();
    return all.where((w) {
      if (_role != 'all' && !w.roles.contains(_role)) return false;
      if (q.isEmpty) return true;
      return [w.name, w.code, w.phone, w.email]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name, code, phone…',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['all', 'crew', 'driver'].map((r) {
                    final on = _role == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r == 'all' ? 'All' : r),
                        selected: on,
                        onSelected: (_) => setState(() => _role = r),
                        selectedColor: AppColors.brand600,
                        labelStyle: TextStyle(
                            color: on ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Worker>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LoadingList();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(
                        message: 'Couldn\'t load workers.', onRetry: _reload);
                  }
                  final rows = _filter(snap.data ?? const []);
                  if (rows.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(
                          icon: Icons.groups_outlined,
                          title: 'No workers',
                          subtitle: 'Add workers from the web portal.'),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _card(rows[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Worker w) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.brand50,
              child: Text(
                (w.name.isNotEmpty ? w.name[0] : '?').toUpperCase(),
                style: const TextStyle(
                    color: AppColors.brand700, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.name.isEmpty ? 'Worker' : w.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14.5)),
                  const SizedBox(height: 2),
                  Text(
                      [w.roles.join(', '), w.phone]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 12.5)),
                  if (w.ratingCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(Icons.star,
                              size: 13, color: AppColors.star),
                          const SizedBox(width: 3),
                          Text(
                              '${w.ratingAvg.toStringAsFixed(1)} (${w.ratingCount})',
                              style: const TextStyle(fontSize: 11.5)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            StatusBadge(w.displayStatus, worker: true),
          ],
        ),
      );
}
