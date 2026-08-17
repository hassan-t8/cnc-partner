import 'dart:async';

import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/search_filter_bar.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'van_form.dart';

class PartnerVansScreen extends ConsumerStatefulWidget {
  const PartnerVansScreen({super.key});
  @override
  ConsumerState<PartnerVansScreen> createState() => _PartnerVansScreenState();
}

class _PartnerVansScreenState extends ConsumerState<PartnerVansScreen> {
  String _query = '';
  String _status = 'all';
  // Optimistic local edits (status / auto-assign) for instant UI feedback.
  final Map<int, Van> _overrides = {};
  // driverWorkerId → name. The van LIST endpoint returns driverWorkerId but no
  // driver object/name (no include), so a van with an assigned driver showed
  // "No driver". We load the workers once and resolve the name from this map.
  Map<int, String> _driverNames = {};

  // ----- infinite-scroll pagination -----
  // Was an unbounded fetch of the whole fleet on every open; search now runs
  // server-side so matches aren't limited to the pages already loaded.
  static const _pageSize = 30;
  final ScrollController _scroll = ScrollController();
  final List<Van> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  Object? _error;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
    _loadDriverNames();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || !_hasMore) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _overrides.clear();
    });
    try {
      final page = await ref
          .read(partnerRepositoryProvider)
          .vansPage(page: 1, limit: _pageSize, q: _query, status: _status);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.rows);
        _page = 1;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final page = await ref
          .read(partnerRepositoryProvider)
          .vansPage(page: next, limit: _pageSize, q: _query, status: _status);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.rows);
        _page = next;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearch(String v) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _query = v);
      _load();
    });
  }

  bool get _hasSearchOrFilter =>
      _query.trim().isNotEmpty || _status != 'all';

  Widget _loadMoreFooter() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: _loadingMore
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : TextButton(onPressed: _loadMore, child: const Text('Load more')),
        ),
      );

  Future<void> _loadDriverNames() async {
    try {
      // Drivers only — the label this feeds resolves a van's driverWorkerId, and
      // the web's equivalent fetch is scoped the same way.
      final ws =
          await ref.read(partnerRepositoryProvider).workers(role: 'driver');
      if (!mounted) return;
      setState(() => _driverNames = {for (final w in ws) w.id: w.name});
    } catch (_) {
      // Non-fatal: falls back to "Driver #<id>" when the name is unknown.
    }
  }

  /// Driver label for a van: the row's own name, else the resolved worker
  /// name, else `Driver #id` when only the id is known, else "No driver".
  String _driverLabel(Van v) {
    if (v.driverName.isNotEmpty) return v.driverName;
    final id = v.driverWorkerId;
    if (id == null) return 'No driver';
    final name = _driverNames[id];
    return (name != null && name.isNotEmpty) ? name : 'Driver #$id';
  }

  Van _apply(Van v) => _overrides[v.id] ?? v;

  List<Van> _filter(List<Van> all) {
    final q = _query.toLowerCase();
    return all.map(_apply).where((v) {
      if (_status != 'all' && v.status != _status) return false;
      if (q.isEmpty) return true;
      return [v.name, v.plate, v.code, _driverLabel(v)]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  void _reload() => _load();

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
            child: SearchFilterBar(
              hint: 'Search name, plate, driver…',
              onSearch: _onSearch,
              values: {'status': _status},
              onApply: (m) {
                setState(() => _status = m['status'] ?? 'all');
                // Status is a server filter, so the list has to be refetched —
                // filtering locally would only search the pages loaded so far.
                _load();
              },
              groups: const [
                FilterGroup(key: 'status', label: 'Status', options: [
                  FilterOption('all', 'All statuses'),
                  FilterOption('active', 'Active'),
                  FilterOption('maintenance', 'Maintenance'),
                  FilterOption('retired', 'Retired'),
                ]),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: Builder(builder: (context) {
                if (_loading) return const LoadingList();
                if (_error != null && _items.isEmpty) {
                  return ErrorRetry(
                      message: 'Couldn\'t load vans.', onRetry: _reload);
                }
                final rows = _filter(_items);
                if (rows.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 80),
                    EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: _hasSearchOrFilter
                          ? 'No matching vans'
                          : 'No vans yet',
                      subtitle: _hasSearchOrFilter
                          ? 'Try a different name, plate or status.'
                          : 'Add your first van to plan daily routes.',
                      actionLabel: _hasSearchOrFilter ? null : 'Add van',
                      onAction: _hasSearchOrFilter ? null : _openForm,
                    ),
                  ]);
                }
                return ListView.separated(
                  controller: _scroll,
                  // Clear the Android system nav bar so the last van isn't
                  // hidden behind it at the end (edge-to-edge on Android 15).
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
                  itemCount: rows.length + (_hasMore ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      i >= rows.length ? _loadMoreFooter() : _card(rows[i]),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

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
                      _infoRow(Icons.person_outline, _driverLabel(v)),
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
