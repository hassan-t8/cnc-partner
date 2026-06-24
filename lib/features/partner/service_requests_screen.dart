import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Catalog services I provide + new-service requests — mirrors the web's
/// three-section page (Catalog, My services, Requests).
class ServiceRequestsScreen extends ConsumerStatefulWidget {
  const ServiceRequestsScreen({super.key});
  @override
  ConsumerState<ServiceRequestsScreen> createState() =>
      _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState extends ConsumerState<ServiceRequestsScreen> {
  List<CatalogVertical>? _tree;
  List<MyService> _mine = const [];
  List<ServiceRequest> _requests = const [];
  bool _loading = true;
  bool _error = false;
  String _query = '';
  int? _busyServiceId; // catalog service id currently linking/unlinking
  final Set<int> _collapsedVerticals = {}; // verticals expanded by default
  final Set<int> _expandedCategories = {}; // categories collapsed by default
  final Set<int> _expandedItems = {}; // services whose item picker is open

  /// catalogServiceId -> set of ServiceItem ids the partner delivers.
  Map<int, Set<int>> get _pickedItems => {
        for (final m in _mine)
          if (m.catalogServiceId != null)
            m.catalogServiceId!: m.pickedItemIds.toSet()
      };

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  /// catalogServiceId -> PartnerService id (so we can unlink).
  Map<int, int> get _linked => {
        for (final m in _mine)
          if (m.catalogServiceId != null) m.catalogServiceId!: m.id
      };

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final results = await Future.wait([
        _repo.catalogTree(),
        _repo.myServices(),
        _repo.serviceRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _tree = results[0] as List<CatalogVertical>;
        _mine = results[1] as List<MyService>;
        _requests = results[2] as List<ServiceRequest>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshLinks() async {
    try {
      final mine = await _repo.myServices();
      if (mounted) setState(() => _mine = mine);
    } catch (_) {}
  }

  /// Tick/untick items under a service. Empty list auto-unlinks (web parity).
  Future<void> _syncItems(int catalogServiceId, Set<int> itemIds) async {
    setState(() => _busyServiceId = catalogServiceId);
    try {
      await _repo.syncItems(catalogServiceId, itemIds.toList());
      await _refreshLinks();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busyServiceId = -1);
    }
  }

  /// Whole-service toggle for catalog services that have no sub-items.
  Future<void> _toggleWhole(CatalogServiceNode s) async {
    setState(() => _busyServiceId = s.id);
    try {
      final existing = _linked[s.id];
      if (existing != null && existing > 0) {
        await _repo.unlinkService(existing);
        AppToast.success('Removed from your services');
      } else {
        await _repo.linkService(s.id);
        AppToast.success('Added to your services');
      }
      await _refreshLinks();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busyServiceId = -1);
    }
  }

  Future<void> _removeMine(MyService m) async {
    final csid = m.catalogServiceId;
    setState(() => _busyServiceId = csid ?? -2);
    try {
      // Item-based links must be cleared via syncItems([]) — the synthetic
      // PartnerService id can't be DELETEd directly (returns "not found").
      if (csid != null && m.pickedItemIds.isNotEmpty) {
        await _repo.syncItems(csid, const []);
      } else {
        await _repo.unlinkService(m.id);
      }
      AppToast.success('Removed from your services');
      await _refreshLinks();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busyServiceId = -1);
    }
  }

  Future<void> _newRequest() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _RequestForm(),
    );
    if (saved == true) {
      final r = await _repo.serviceRequests().catchError((_) => _requests);
      if (mounted) setState(() => _requests = r);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: MainAppBar('Service requests',
          bottom: TabBar(
            labelColor: AppColors.brand600,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.brand600,
            tabs: [
              const Tab(text: 'Catalog'),
              Tab(text: 'Mine (${_mine.length})'),
              Tab(text: 'Requests (${_requests.length})'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _newRequest,
          backgroundColor: AppColors.brand600,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New request',
              style: TextStyle(color: Colors.white)),
        ),
        body: _loading
            ? const LoadingList()
            : _error
                ? ErrorRetry(
                    message: 'Couldn\'t load the catalog.', onRetry: _loadAll)
                : TabBarView(
                    children: [_catalogTab(), _mineTab(), _requestsTab()],
                  ),
      ),
    );
  }

  // ---------- Catalog tab ----------
  Widget _catalogTab() {
    final tree = _tree ?? const <CatalogVertical>[];
    final q = _query.toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
                hintText: 'Search services…',
                prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              children: _catalogChildren(tree, q),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _catalogChildren(List<CatalogVertical> tree, String q) {
    final searching = q.isNotEmpty;
    final out = <Widget>[];
    for (final v in tree) {
      final cats = v.categories
          .map((c) => CatalogCategory(
                id: c.id,
                name: c.name,
                services: c.services
                    .where((s) =>
                        q.isEmpty ||
                        s.name.toLowerCase().contains(q) ||
                        s.shortDescription.toLowerCase().contains(q) ||
                        c.name.toLowerCase().contains(q) ||
                        v.name.toLowerCase().contains(q))
                    .toList(),
              ))
          .where((c) => c.services.isNotEmpty)
          .toList();
      if (cats.isEmpty) continue;
      final vOpen = searching || !_collapsedVerticals.contains(v.id);
      out.add(_verticalHeader(v, vOpen,
          cats.fold<int>(0, (s, c) => s + c.services.length)));
      if (!vOpen) continue;
      for (final c in cats) {
        final cOpen = searching || _expandedCategories.contains(c.id);
        out.add(_categoryHeader(c, cOpen));
        if (cOpen) out.addAll(c.services.map(_serviceTile));
      }
    }
    if (out.isEmpty) {
      out.add(const Padding(
        padding: EdgeInsets.only(top: 80),
        child: EmptyState(
            icon: Icons.category_outlined, title: 'No services found'),
      ));
    }
    return out;
  }

  Widget _verticalHeader(CatalogVertical v, bool open, int count) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 2),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => open
              ? _collapsedVerticals.add(v.id)
              : _collapsedVerticals.remove(v.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(open ? Icons.expand_more : Icons.chevron_right,
                    size: 22, color: AppColors.brand600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(v.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                ),
                Text('$count',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );

  Widget _categoryHeader(CatalogCategory c, bool open) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => open
            ? _expandedCategories.remove(c.id)
            : _expandedCategories.add(c.id)),
        child: Container(
          margin: const EdgeInsets.only(left: 8, bottom: 6, top: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(c.name,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${c.services.length}',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 6),
              Icon(open ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      );

  Widget _serviceTile(CatalogServiceNode s) {
    final picked = _pickedItems[s.id] ?? const <int>{};
    final isLinked = picked.isNotEmpty || _linked.containsKey(s.id);
    final busy = _busyServiceId == s.id;
    final itemsOpen = _expandedItems.contains(s.id);
    final hasItems = s.items.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isLinked ? AppColors.brand50.withValues(alpha: 0.4) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isLinked ? AppColors.brand600 : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                _thumb(s.heroImage),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(s.name.isEmpty ? 'Service' : s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5)),
                          ),
                          if (isLinked) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: AppColors.brand600,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded,
                                      size: 11, color: Colors.white),
                                  SizedBox(width: 2),
                                  Text('Linked',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (s.shortDescription.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(s.shortDescription,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5)),
                        ),
                    ],
                  ),
                ),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2)),
                  )
                else if (!hasItems)
                  _wholeToggle(s, isLinked),
              ],
            ),
          ),
          if (hasItems)
            InkWell(
              onTap: () => setState(() => itemsOpen
                  ? _expandedItems.remove(s.id)
                  : _expandedItems.add(s.id)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Icon(itemsOpen ? Icons.expand_less : Icons.expand_more,
                        size: 16, color: AppColors.brand700),
                    const SizedBox(width: 4),
                    Text('${s.items.length} item'
                        '${s.items.length == 1 ? '' : 's'} available',
                        style: const TextStyle(
                            color: AppColors.brand700,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                    if (picked.isNotEmpty)
                      Text('  · ${picked.length} picked',
                          style: const TextStyle(
                              color: AppColors.brand700,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          if (hasItems && itemsOpen) _itemPicker(s, picked, busy),
        ],
      ),
    );
  }

  Widget _wholeToggle(CatalogServiceNode s, bool isLinked) => Material(
        color: isLinked ? AppColors.brand50 : AppColors.brand600,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _toggleWhole(s),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: isLinked ? Border.all(color: AppColors.brand600) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isLinked ? Icons.check_rounded : Icons.add,
                    size: 16,
                    color: isLinked ? AppColors.brand700 : Colors.white),
                const SizedBox(width: 5),
                Text(isLinked ? 'Linked' : 'I provide',
                    style: TextStyle(
                        color: isLinked ? AppColors.brand700 : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
              ],
            ),
          ),
        ),
      );

  Widget _itemPicker(CatalogServiceNode s, Set<int> picked, bool busy) =>
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(12)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('PICK THE ITEMS YOU DELIVER',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                        color: AppColors.textMuted)),
                const Spacer(),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => _syncItems(
                          s.id, s.items.map((e) => e.id).toSet()),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: const Text('Select all',
                      style: TextStyle(fontSize: 11.5)),
                ),
                TextButton(
                  onPressed: busy ? null : () => _syncItems(s.id, const {}),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  child: Text('Clear',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
                ),
              ],
            ),
            for (final it in s.items)
              InkWell(
                onTap: busy
                    ? null
                    : () {
                        final next = {...picked};
                        if (next.contains(it.id)) {
                          next.remove(it.id);
                        } else {
                          next.add(it.id);
                        }
                        _syncItems(s.id, next);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                          picked.contains(it.id)
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 20,
                          color: picked.contains(it.id)
                              ? AppColors.brand600
                              : AppColors.textFaint),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(it.name.isEmpty ? 'Item' : it.name,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      if (it.unitPrice != null && it.unitPrice! > 0)
                        Text('AED ${it.unitPrice!.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );

  // ---------- My services tab ----------
  Widget _mineTab() {
    if (_mine.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
            icon: Icons.handyman_outlined,
            title: 'No linked services',
            subtitle: 'Add services you provide from the Catalog tab.'),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
        itemCount: _mine.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final m = _mine[i];
          final busy = _busyServiceId == m.catalogServiceId;
          return Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _thumb(m.heroImage),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name.isEmpty ? 'Service' : m.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13.5)),
                      Text(
                          [m.verticalName, m.categoryName]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 11.5)),
                    ],
                  ),
                ),
                busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2))
                    : TextButton(
                        onPressed: () => _removeMine(m),
                        child: const Text('Remove',
                            style: TextStyle(color: AppColors.rose))),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- Requests tab ----------
  Widget _requestsTab() {
    if (_requests.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: 'No requests yet',
            subtitle: 'Ask CNC to add a service that isn\'t in the catalog.'),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _requestCard(_requests[i]),
    );
  }

  (Color, Color) _statusColor(String s) {
    switch (s) {
      case 'approved_linked':
      case 'approved_created':
        return (const Color(0xFFD1FAE5), const Color(0xFF065F46));
      case 'in_review':
        return (const Color(0xFFE0F2FE), const Color(0xFF075985));
      case 'declined':
        return (const Color(0xFFFFE4E6), const Color(0xFF9F1239));
      default:
        return (const Color(0xFFF3F4F6), const Color(0xFF374151));
    }
  }

  Widget _requestCard(ServiceRequest r) {
    final (bg, fg) = _statusColor(r.status);
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
              Expanded(
                child: Text(
                    r.requestedName.isEmpty ? 'Request' : r.requestedName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(r.statusLabel.toUpperCase(),
                    style: TextStyle(
                        color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (r.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.description,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12.5)),
          ],
          if (r.targetPriceRange.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Target: ${r.targetPriceRange}',
                style: const TextStyle(
                    color: AppColors.brand700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
          if (r.adminNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(r.adminNotes,
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
          if (r.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(DateFormat('d MMM y').format(r.createdAt!),
                style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ],
        ],
      ),
    );
  }

  Widget _thumb(String? url) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
          image: (url != null && url.isNotEmpty)
              ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
              : null,
        ),
        child: (url == null || url.isEmpty)
            ? Icon(Icons.cleaning_services,
                size: 18, color: AppColors.textFaint)
            : null,
      );
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm();
  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      AppToast.error('Service name is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(partnerRepositoryProvider).submitServiceRequest({
        'requestedName': _name.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        if (_price.text.trim().isNotEmpty)
          'targetPriceRange': _price.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      AppToast.success('Request submitted');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New service request',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Ask CNC to add a service you provide that isn\'t listed.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              const SizedBox(height: 14),
              TextField(
                  controller: _name,
                  decoration:
                      const InputDecoration(labelText: 'Service name *')),
              const SizedBox(height: 10),
              TextField(
                  controller: _desc,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'What does it include?')),
              const SizedBox(height: 10),
              TextField(
                  controller: _price,
                  decoration: const InputDecoration(
                      labelText: 'Target price range (e.g. 200-350 AED)')),
              const SizedBox(height: 10),
              TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Notes for CNC')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white))
                      : const Text('Submit request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
