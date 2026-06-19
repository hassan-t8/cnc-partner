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
    return Container(
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
              const Icon(Icons.local_shipping,
                  color: AppColors.brand600, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(v.name.isEmpty ? 'Van' : v.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              StatusBadge(v.status == 'active' ? 'completed' : v.status),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 18, color: AppColors.textFaint),
                onSelected: (s) => s == 'edit' ? _openForm(v) : _delete(v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              [
                if (v.plate.isNotEmpty) v.plate,
                if (v.code.isNotEmpty) v.code,
                '${v.seats} seats',
                if (v.driverName.isNotEmpty) 'Driver: ${v.driverName}',
              ].join(' · '),
              style:
                  TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          if (hasParking) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => launchUrl(
                Uri.parse(
                    'https://www.google.com/maps?q=${v.parkingLat},${v.parkingLng}'),
                mode: LaunchMode.externalApplication,
              ),
              child: const Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 14, color: AppColors.brand600),
                  SizedBox(width: 4),
                  Text('Parking location',
                      style: TextStyle(
                          color: AppColors.brand600,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
