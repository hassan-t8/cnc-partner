import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../worker/worker_repository.dart';

/// The signed-in worker's own profile. Worker details are managed by their
/// company (partner), so fields are read-only and editing is disabled.
class WorkerProfileScreen extends ConsumerStatefulWidget {
  const WorkerProfileScreen({super.key});
  @override
  ConsumerState<WorkerProfileScreen> createState() =>
      _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends ConsumerState<WorkerProfileScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(workerRepositoryProvider).myProfile();
  }

  void _reload() => setState(
      () => _future = ref.read(workerRepositoryProvider).myProfile());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar('My profile', actions: [
        IconButton(
          onPressed: null,
          icon: Icon(Icons.edit_off_outlined),
          tooltip: 'Managed by your company',
        ),
      ]),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 70);
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: 'Couldn\'t load your profile.', onRetry: _reload);
          }
          final data = snap.data ?? const {};
          final w = data['worker'] is Map
              ? Map<String, dynamic>.from(data['worker'])
              : <String, dynamic>{};
          final u = data['user'] is Map
              ? Map<String, dynamic>.from(data['user'])
              : <String, dynamic>{};
          final name = [w['firstName'], w['lastName']]
              .where((s) => '${s ?? ''}'.isNotEmpty)
              .join(' ');
          final roles = (w['roles'] is List)
              ? (w['roles'] as List).join(', ')
              : '';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.brand600,
                    child: Text(
                        (name.isNotEmpty ? name[0] : '?').toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'Worker' : name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        if (roles.isNotEmpty)
                          Text(roles,
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _row('Code', '${w['code'] ?? ''}'),
              _row('Email', '${u['email'] ?? w['email'] ?? ''}'),
              _row('Phone', '${w['phone'] ?? ''}'),
              _row('Status', '${w['status'] ?? ''}'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AppColors.brand700),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          'Your details are managed by your company. Ask your '
                          'partner admin to update your name, phone or role.',
                          style: TextStyle(
                              color: AppColors.brand700,
                              fontSize: 12.5,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
