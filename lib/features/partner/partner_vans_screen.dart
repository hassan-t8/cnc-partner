import '../../widgets/main_app_bar.dart';
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
  String _query = '';
  String _status = 'all';
  // Optimistic local edits (status / auto-assign) for instant UI feedback.
  final Map<int, Van> _overrides = {};

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).vans();
  }

  Van _apply(Van v) => _overrides[v.id] ?? v;

  List<Van> _filter(List<Van> all) {
    final q = _query.toLowerCase();
    return all.map(_apply).where((v) {
      if (_status != 'all' && v.status != _status) return false;
      if (q.isEmpty) return true;
      return [v.name, v.plate, v.code, v.driverName]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  bool get _hasFilters => _status != 'all';

  void _clearFilters() => setState(() => _status = 'all');

  void _reload() => setState(() {
        _overrides.clear();
        _future = ref.read(partnerRepositoryProvider).vans();
      });

  Future<void> _openForm([Van? van]) async {
    await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => VanForm(van: van)));
    if (mounted) _reload();
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
    final prev = _overrides[v.id];
    setState(() => _overrides[v.id] = v.copyWith(status: picked));
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateVan(v.id, {'status': picked});
      AppToast.success('Status updated');
    } on ApiException catch (e) {
      setState(() {
        if (prev != null) {
          _overrides[v.id] = prev;
        } else {
          _overrides.remove(v.id);
        }
      });
      AppToast.error(e.message);
    }
  }

  Future<void> _toggleAutoAssign(Van v, bool value) async {
    final prev = _overrides[v.id];
    setState(() => _overrides[v.id] = v.copyWith(acceptAutoAssign: value));
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateVan(v.id, {'acceptAutoAssign': value});
      AppToast.success(value ? 'Auto-assign on' : 'Auto-assign off');
    } on ApiException catch (e) {
      setState(() {
        if (prev != null) {
          _overrides[v.id] = prev;
        } else {
          _overrides.remove(v.id);
        }
      });
      AppToast.error(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Vans'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.brand600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add van', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name, plate, driver…',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(
                        label: 'All statuses',
                        selected: _status == 'all',
                        onTap: () => setState(() => _status = 'all'),
                      ),
                      for (final e in _statusLabels.entries)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _filterChip(
                            label: e.value,
                            selected: _status == e.key,
                            onTap: () => setState(() => _status = e.key),
                          ),
                        ),
                    ],
                  ),
                ),
                _appliedFilters(),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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
                  final rows = _filter(snap.data ?? const []);
                  if (rows.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(
                          icon: Icons.local_shipping_outlined,
                          title: 'No vans',
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
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.brand600,
        labelStyle: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600),
        backgroundColor: AppColors.surface,
        side: BorderSide(color: AppColors.border),
      );

  // Applied-filter chip (status) with an × to clear it, plus a Clear-all
  // action. Shows nothing when no filters are active — mirrors the partner
  // web app's filter-summary UX.
  Widget _appliedFilters() {
    if (!_hasFilters) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_status != 'all')
                  _appliedChip(_statusLabels[_status] ?? _status,
                      () => setState(() => _status = 'all')),
              ],
            ),
          ),
          TextButton(
            onPressed: _clearFilters,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.rose,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32)),
            child: const Text('Clear',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _appliedChip(String label, VoidCallback onRemove) => Container(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: AppColors.brand600.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brand600.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.brand700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Icon(Icons.close, size: 15, color: AppColors.brand700),
            ),
          ],
        ),
      );

  Widget _card(Van v) {
    final hasParking = v.parkingLat != null && v.parkingLng != null;
    return TweenAnimationBuilder<double>(
      key: ValueKey(v.id),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child:
            Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand700.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openForm(v),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ─────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(15),
                        gradient: LinearGradient(
                          colors: [AppColors.brand600, AppColors.brand700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand600.withValues(alpha: 0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.local_shipping_rounded,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.name.isEmpty ? 'Van' : v.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 16)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.event_seat_outlined,
                                  size: 13, color: AppColors.textFaint),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                    [
                                      '${v.seats} seats',
                                      if (v.plate.isNotEmpty) v.plate,
                                      if (v.code.isNotEmpty) v.code,
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _changeStatus(v),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          StatusBadge(
                              v.status == 'active' ? 'completed' : v.status),
                          Icon(Icons.expand_more,
                              size: 16, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // ── Info block: driver · parking · auto-assign ─────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _infoRow(Icons.person_outline,
                          v.driverName.isEmpty ? 'No driver' : v.driverName),
                      if (hasParking)
                        InkWell(
                          onTap: () => launchUrl(
                            Uri.parse(
                                'https://www.google.com/maps?q=${v.parkingLat},${v.parkingLng}'),
                            mode: LaunchMode.externalApplication,
                          ),
                          child: _infoRow(Icons.place_outlined,
                              'Open parking in Maps',
                              link: true),
                        )
                      else
                        _infoRow(Icons.place_outlined, 'No parking set'),
                      Divider(height: 12, color: AppColors.border),
                      Row(
                        children: [
                          Icon(Icons.bolt_outlined,
                              size: 16, color: AppColors.brand600),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('Auto-assign new bookings',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                          SizedBox(
                            height: 28,
                            child: Switch(
                              value: v.acceptAutoAssign,
                              activeThumbColor: AppColors.brand600,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (val) => _toggleAutoAssign(v, val),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Actions ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                        child: _actionBtn(
                            Icons.edit_outlined, 'Edit', () => _openForm(v))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _actionBtn(Icons.delete_outline, 'Delete',
                            () => _delete(v),
                            danger: true)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {bool link = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon,
                size: 15,
                color: link ? AppColors.brand600 : AppColors.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: link ? AppColors.brand600 : AppColors.textMuted,
                      fontWeight: link ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? AppColors.rose : AppColors.textMuted,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
