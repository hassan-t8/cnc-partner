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

  Future<void> _toggle(CatalogServiceNode s) async {
    setState(() => _busyServiceId = s.id);
    try {
      final existing = _linked[s.id];
      if (existing != null) {
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

  Future<void> _unlinkMine(MyService m) async {
    setState(() => _busyServiceId = m.catalogServiceId ?? -2);
    try {
      await _repo.unlinkService(m.id);
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
        appBar: AppBar(
          title: const Text('Services I provide'),
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
              children: [
                for (final v in tree)
                  ..._verticalSection(v, q),
                if (tree.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: EmptyState(
                        icon: Icons.category_outlined,
                        title: 'No services available'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _verticalSection(CatalogVertical v, String q) {
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
    if (cats.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(v.name.toUpperCase(),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: AppColors.textMuted)),
      ),
      for (final c in cats) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text('${c.name} · ${c.services.length}',
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700)),
        ),
        for (final s in c.services) _serviceTile(s),
      ],
    ];
  }

  Widget _serviceTile(CatalogServiceNode s) {
    final isLinked = _linked.containsKey(s.id);
    final busy = _busyServiceId == s.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _thumb(s.heroImage),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name.isEmpty ? 'Service' : s.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (s.shortDescription.isNotEmpty)
                  Text(s.shortDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2)),
                  )
                : isLinked
                    ? OutlinedButton.icon(
                        onPressed: () => _toggle(s),
                        icon: const Icon(Icons.check_rounded,
                            size: 16, color: AppColors.brand600),
                        label: const Text('Linked',
                            style: TextStyle(
                                color: AppColors.brand700,
                                fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                            side:
                                const BorderSide(color: AppColors.brand600)),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _toggle(s),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('I provide'),
                      ),
          ),
        ],
      ),
    );
  }

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
                        onPressed: () => _unlinkMine(m),
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
