import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// One selectable value inside a [FilterGroup].
class FilterOption {
  final String value;
  final String label;
  const FilterOption(this.value, this.label);
}

/// A single-select filter shown as a dropdown in the filter sheet. The FIRST
/// option is treated as the "no filter" sentinel (e.g. value 'all').
class FilterGroup {
  final String key;
  final String label;
  final List<FilterOption> options;
  const FilterGroup(
      {required this.key, required this.label, required this.options});

  String get sentinel => options.first.value;
  String labelFor(String value) =>
      options.firstWhere((o) => o.value == value, orElse: () => options.first)
          .label;
}

/// Search bar with a filter icon (opens a bottom sheet of dropdown filters),
/// plus removable applied-filter chips + Clear all. Mirrors the CRM booking
/// search bar UX. Parent owns the selected values and the search text.
class SearchFilterBar extends StatefulWidget {
  final String hint;
  final ValueChanged<String> onSearch;
  final List<FilterGroup> groups;

  /// Current selection per group key. Missing keys default to the sentinel.
  final Map<String, String> values;
  final ValueChanged<Map<String, String>> onApply;
  final Duration debounce;

  const SearchFilterBar({
    super.key,
    required this.hint,
    required this.onSearch,
    required this.groups,
    required this.values,
    required this.onApply,
    this.debounce = const Duration(milliseconds: 350),
  });

  @override
  State<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends State<SearchFilterBar> {
  final _search = TextEditingController();
  Timer? _debounce;

  String _valueFor(String key) {
    final g = widget.groups.firstWhere((g) => g.key == key);
    return widget.values[key] ?? g.sentinel;
  }

  bool _isApplied(FilterGroup g) => _valueFor(g.key) != g.sentinel;
  bool get _anyApplied => widget.groups.any(_isApplied);
  int get _appliedCount => widget.groups.where(_isApplied).length;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(widget.debounce, () => widget.onSearch(v.trim()));
  }

  void _setValue(String key, String value) {
    final next = Map<String, String>.from(widget.values);
    next[key] = value;
    widget.onApply(next);
  }

  void _clearAll() {
    final next = <String, String>{};
    for (final g in widget.groups) {
      next[g.key] = g.sentinel;
    }
    widget.onApply(next);
  }

  Future<void> _openSheet() async {
    // Local working copy so nothing changes until "Apply".
    final temp = <String, String>{
      for (final g in widget.groups) g.key: _valueFor(g.key),
    };
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              top: 20,
              left: 20,
              right: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Filters',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setSheet(() {
                          for (final g in widget.groups) {
                            temp[g.key] = g.sentinel;
                          }
                        });
                      },
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final g in widget.groups) ...[
                  Text(g.label.toUpperCase(),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMuted,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: temp[g.key],
                        items: [
                          for (final o in g.options)
                            DropdownMenuItem(
                                value: o.value, child: Text(o.label)),
                        ],
                        onChanged: (v) =>
                            setSheet(() => temp[g.key] = v ?? g.sentinel),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(temp);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand600),
                    child: const Text('Apply filters',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Matches the bookings search bar for a consistent look app-wide.
        TextField(
          controller: _search,
          onChanged: (v) {
            _onSearchChanged(v);
            setState(() {}); // refresh the clear/tune affordances
          },
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _search.clear();
                      widget.onSearch('');
                      setState(() {});
                    },
                    icon: Icon(Icons.clear,
                        size: 18, color: AppColors.textFaint),
                  ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: _openSheet,
                      icon: Icon(Icons.tune,
                          color: _anyApplied
                              ? AppColors.brand600
                              : AppColors.textMuted),
                      tooltip: 'Filters',
                    ),
                    if (_appliedCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.brand600,
                              shape: BoxShape.circle),
                          child: Text('$_appliedCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_anyApplied)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in widget.groups)
                        if (_isApplied(g))
                          _chip('${g.label}: ${g.labelFor(_valueFor(g.key))}',
                              () => _setValue(g.key, g.sentinel)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _clearAll,
                  child: Text('Clear all',
                      style: TextStyle(
                          color: AppColors.brand600,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _chip(String label, VoidCallback onRemove) => Container(
        padding: const EdgeInsets.only(left: 10, right: 4, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.brand600,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            GestureDetector(
              onTap: onRemove,
              child: Icon(Icons.close, size: 15, color: AppColors.brand600),
            ),
          ],
        ),
      );
}
