import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/main_app_bar.dart';
import 'partner_models.dart';

/// The result of the worker-services picker: the legacy anchor rows
/// (`basePriceIds`) plus the per-item picks bucketed by basePriceId
/// (`itemsByBp`). Both persist via `syncWorkerServices`.
class WorkerServicesSelection {
  final List<int> basePriceIds;
  final Map<int, List<int>> itemsByBp;
  const WorkerServicesSelection(this.basePriceIds, this.itemsByBp);
}

/// A rich, hierarchical services picker for the worker form — Vertical →
/// Category → Service → Items, with picked/total counts, Linked/active
/// badges, per-item checkboxes + prices, per-service Select all/Clear, and a
/// search box. Mirrors the partner WEB portal's "SERVICES ATTACHED" section.
///
/// Identity mirrors the backend contract exactly: services are keyed on
/// `basePriceId`; items are `serviceItemId`s. Picking any item auto-links the
/// parent service (adds its basePriceId to the anchor set); clearing all items
/// drops the anchor (when the service has items).
Future<WorkerServicesSelection?> showWorkerServicesPicker({
  required BuildContext context,
  required List<MyService> services,
  required List<int> selectedBasePriceIds,
  required Map<int, List<int>> itemsByBp,
}) {
  return Navigator.of(context).push<WorkerServicesSelection>(
    MaterialPageRoute(
      builder: (_) => _WorkerServicesPickerPage(
        services: services,
        initialBasePriceIds: selectedBasePriceIds,
        initialItemsByBp: itemsByBp,
      ),
    ),
  );
}

class _Cat {
  final String key;
  final String name;
  final List<MyService> services = [];
  _Cat(this.key, this.name);
}

class _Vert {
  final String key;
  final String name;
  final Map<String, _Cat> cats = {};
  _Vert(this.key, this.name);
}

class _WorkerServicesPickerPage extends StatefulWidget {
  final List<MyService> services;
  final List<int> initialBasePriceIds;
  final Map<int, List<int>> initialItemsByBp;
  const _WorkerServicesPickerPage({
    required this.services,
    required this.initialBasePriceIds,
    required this.initialItemsByBp,
  });

  @override
  State<_WorkerServicesPickerPage> createState() =>
      _WorkerServicesPickerPageState();
}

class _WorkerServicesPickerPageState extends State<_WorkerServicesPickerPage> {
  late final Set<int> _basePriceIds;
  late final Map<int, List<int>> _itemsByBp;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final Set<String> _collapsedVerts = {};
  final Map<int, bool> _openItems = {}; // basePriceId -> expanded

  @override
  void initState() {
    super.initState();
    _basePriceIds = {...widget.initialBasePriceIds};
    _itemsByBp = {
      for (final e in widget.initialItemsByBp.entries) e.key: [...e.value],
    };
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<int> _itemsFor(int bp) => _itemsByBp[bp] ?? const [];

  bool _isLinked(MyService s) {
    final bp = s.basePriceId;
    if (bp == null) return false;
    return _basePriceIds.contains(bp) || _itemsFor(bp).isNotEmpty;
  }

  bool _matches(MyService s) {
    if (_query.isEmpty) return true;
    return s.name.toLowerCase().contains(_query) ||
        '${s.basePriceId}'.contains(_query);
  }

  // Item toggle — picking any item auto-links the service; removing the last
  // item drops the anchor (when the service has items). Mirrors the web.
  void _toggleItem(MyService s, int serviceItemId) {
    final bp = s.basePriceId;
    if (bp == null) return;
    setState(() {
      final current = [..._itemsFor(bp)];
      if (current.contains(serviceItemId)) {
        current.remove(serviceItemId);
      } else {
        current.add(serviceItemId);
      }
      if (current.isEmpty) {
        _itemsByBp.remove(bp);
      } else {
        _itemsByBp[bp] = current;
      }
      final hasItems = s.items.isNotEmpty;
      if (current.isNotEmpty) {
        _basePriceIds.add(bp);
      } else if (hasItems) {
        _basePriceIds.remove(bp);
      }
    });
  }

  void _selectAll(MyService s) {
    final bp = s.basePriceId;
    if (bp == null) return;
    setState(() {
      _itemsByBp[bp] = s.items.map((it) => it.serviceItemId).toList();
      _basePriceIds.add(bp);
    });
  }

  void _clearService(MyService s) {
    final bp = s.basePriceId;
    if (bp == null) return;
    setState(() {
      _itemsByBp.remove(bp);
      _basePriceIds.remove(bp);
    });
  }

  void _clearAll() {
    setState(() {
      _basePriceIds.clear();
      _itemsByBp.clear();
    });
  }

  List<_Vert> _buildGroups() {
    final byVert = <String, _Vert>{};
    for (final s in widget.services) {
      final hasVert = s.verticalName.isNotEmpty;
      final hasCat = s.categoryName.isNotEmpty;
      final vertKey = hasVert ? 'v:${s.verticalName}' : (hasCat ? 'v:__uncat' : 'v:__legacy');
      final vertName = hasVert ? s.verticalName : (hasCat ? 'Uncategorized' : 'Other services');
      final catKey = hasCat ? 'c:${s.categoryName}' : 'c:__none';
      final catName = hasCat ? s.categoryName : '—';
      final vert = byVert.putIfAbsent(vertKey, () => _Vert(vertKey, vertName));
      final cat = vert.cats.putIfAbsent(catKey, () => _Cat(catKey, catName));
      cat.services.add(s);
    }
    final verts = byVert.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return verts;
  }

  int get _totalPicked => _basePriceIds.length;

  @override
  Widget build(BuildContext context) {
    final groups = _buildGroups();
    final anyShown = widget.services.any(_matches);
    return Scaffold(
      appBar: MainAppBar('Services attached ($_totalPicked)'),
      body: widget.services.isEmpty
          ? _emptyState()
          : Column(
              children: [
                _searchBar(),
                Expanded(
                  child: !anyShown
                      ? _noMatches()
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          children: [
                            for (final vert in groups)
                              ..._buildVertical(vert),
                          ],
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(
              context,
              WorkerServicesSelection(
                _basePriceIds.toList(),
                {for (final e in _itemsByBp.entries) e.key: [...e.value]},
              ),
            ),
            child: const Text('Done'),
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search services…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          TextButton(
            onPressed: (_basePriceIds.isEmpty && _itemsByBp.isEmpty)
                ? null
                : _clearAll,
            style: TextButton.styleFrom(foregroundColor: AppColors.rose),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildVertical(_Vert vert) {
    final visibleCats = <_Cat>[];
    for (final c in vert.cats.values) {
      final shown = c.services.where(_matches).toList();
      if (shown.isEmpty) continue;
      final nc = _Cat(c.key, c.name)..services.addAll(shown);
      visibleCats.add(nc);
    }
    if (visibleCats.isEmpty) return const [];
    visibleCats.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final vertServices = visibleCats.expand((c) => c.services).toList();
    final vertLinked = vertServices.where(_isLinked).length;
    final collapsed = _collapsedVerts.contains(vert.key);
    return [
      Container(
        margin: const EdgeInsets.only(top: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                collapsed
                    ? _collapsedVerts.remove(vert.key)
                    : _collapsedVerts.add(vert.key);
              }),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    Icon(
                      collapsed
                          ? Icons.chevron_right
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        vert.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    Text('$vertLinked/${vertServices.length}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted)),
                  ],
                ),
              ),
            ),
            if (!collapsed)
              for (final cat in visibleCats) _buildCategory(cat),
          ],
        ),
      ),
    ];
  }

  Widget _buildCategory(_Cat cat) {
    final linked = cat.services.where(_isLinked).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(cat.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                Text('$linked/${cat.services.length}',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textFaint)),
              ],
            ),
          ),
          for (final s in cat.services) _buildService(s),
        ],
      ),
    );
  }

  Widget _buildService(MyService s) {
    final bp = s.basePriceId;
    final linked = _isLinked(s);
    final picked = bp == null ? const <int>[] : _itemsFor(bp);
    final items = s.items;
    final open = bp != null &&
        (_openItems[bp] ?? picked.isNotEmpty);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: linked ? AppColors.brand50 : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: linked ? AppColors.brand100 : AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(s.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
                if (linked) ...[
                  const SizedBox(width: 6),
                  _linkedBadge(),
                ],
                if (!s.isActive) ...[
                  const SizedBox(width: 6),
                  Text('INACTIVE',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textFaint)),
                ],
                const SizedBox(width: 6),
                if (items.isNotEmpty && bp != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _openItems[bp] = !open),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                              open
                                  ? Icons.keyboard_arrow_down
                                  : Icons.chevron_right,
                              size: 14,
                              color: AppColors.textMuted),
                          const SizedBox(width: 2),
                          Text(
                            '${items.length} items'
                            '${picked.isNotEmpty ? ' · ${picked.length} picked' : ''}',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Text('No items',
                      style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textFaint)),
              ],
            ),
          ),
          if (open && items.isNotEmpty) _buildItems(s, picked),
        ],
      ),
    );
  }

  Widget _buildItems(MyService s, List<int> picked) {
    final items = s.items;
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('ITEMS THIS WORKER HANDLES',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: AppColors.textMuted)),
              ),
              InkWell(
                onTap: () => _selectAll(s),
                child: Text('Select all',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand700)),
              ),
              Text('  ·  ',
                  style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
              InkWell(
                onTap: () => _clearService(s),
                child: Text('Clear',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.rose)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (final it in items)
            _itemRow(s, it, picked.contains(it.serviceItemId)),
          const SizedBox(height: 4),
          Text('${items.length} items · ${picked.length} picked',
              style: TextStyle(fontSize: 10.5, color: AppColors.textFaint)),
        ],
      ),
    );
  }

  Widget _itemRow(MyService s, MyServiceItem it, bool checked) {
    return InkWell(
      onTap: () => _toggleItem(s, it.serviceItemId),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Checkbox(
                value: checked,
                visualDensity: VisualDensity.compact,
                activeColor: AppColors.brand600,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (_) => _toggleItem(s, it.serviceItemId),
              ),
            ),
            Expanded(
              child: Text(it.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: AppColors.textPrimary)),
            ),
            if (it.unitPrice != null) ...[
              const SizedBox(width: 8),
              Text('AED ${it.unitPrice!.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linkedBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.brand100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 10, color: AppColors.brand700),
            const SizedBox(width: 2),
            Text('Linked',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand700)),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Your partner does not have any approved catalog services yet. '
            'Link the services you provide, then assign them to this worker.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );

  Widget _noMatches() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('No services match "$_query"',
                style: TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
