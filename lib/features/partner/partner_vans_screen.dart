import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'van_form.dart';

class PartnerVansScreen extends ConsumerStatefulWidget {
  const PartnerVansScreen({super.key});
  @override
  ConsumerState<PartnerVansScreen> createState() => _PartnerVansScreenState();
}

class _PartnerVansScreenState extends ConsumerState<PartnerVansScreen> {
  late Future<List<Van>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).vans();
  }

  void _reload() =>
      setState(() => _future = ref.read(partnerRepositoryProvider).vans());

  Future<void> _openForm([Van? van]) async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => VanForm(van: van)));
    if (saved == true) _reload();
  }

  Future<void> _delete(Van v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete van?'),
        content: Text('Remove "${v.name}"? This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(partnerRepositoryProvider).deleteVan(v.id);
      AppToast.success('Van deleted');
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    }
  }

  static const _statusLabels = {
    'active': 'Active',
    'maintenance': 'Maintenance',
    'retired': 'Retired',
  };

  Future<void> _changeStatus(Van v) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Set status · ${v.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final e in _statusLabels.entries)
              ListTile(
                title: Text(e.value),
                trailing: v.status == e.key
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.brand600)
                    : null,
                onTap: () => Navigator.pop(context, e.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == v.status) return;
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateVan(v.id, {'status': picked});
      AppToast.success('Status updated');
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.brand600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add van', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Van>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList();
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load vans.', onRetry: _reload);
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'No vans yet',
                    subtitle: 'Add vans from the web portal.'),
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
    );
  }

  Widget _card(Van v) {
    final hasParking = v.parkingLat != null && v.parkingLng != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openForm(v),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.local_shipping_rounded,
                        color: AppColors.brand600, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(v.name.isEmpty ? 'Van' : v.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _changeStatus(v),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusBadge(v.status == 'active'
                                      ? 'completed'
                                      : v.status),
                                  Icon(Icons.expand_more,
                                      size: 15, color: AppColors.textFaint),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (v.plate.isNotEmpty)
                              _pill(Icons.pin_outlined, v.plate),
                            if (v.code.isNotEmpty)
                              _pill(Icons.badge_outlined, v.code),
                            _pill(Icons.event_seat_outlined, '${v.seats} seats'),
                            if (v.driverName.isNotEmpty)
                              _pill(Icons.person_outline, v.driverName),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (hasParking)
                    InkWell(
                      onTap: () => launchUrl(
                        Uri.parse(
                            'https://www.google.com/maps?q=${v.parkingLat},${v.parkingLng}'),
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.place_outlined,
                              size: 14, color: AppColors.brand600),
                          const SizedBox(width: 4),
                          Text('Parking',
                              style: TextStyle(
                                  color: AppColors.brand600,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                  else
                    Text('No parking set',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 12.5)),
                  const Spacer(),
                  _miniAction(Icons.edit_outlined, 'Edit', () => _openForm(v)),
                  _miniAction(Icons.delete_outline, 'Delete', () => _delete(v),
                      danger: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _miniAction(IconData icon, String tip, VoidCallback onTap,
          {bool danger = false}) =>
      IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        tooltip: tip,
        icon: Icon(icon,
            size: 18, color: danger ? AppColors.rose : AppColors.textMuted),
      );
}
