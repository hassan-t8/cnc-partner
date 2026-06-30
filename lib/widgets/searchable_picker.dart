import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A compact, searchable, bounded bottom-sheet picker for API-backed lists
/// (zones, drivers, workers, vans). Replaces full-page dropdown popups.
///
/// Filtering is client-side over the already-loaded [items] (the lists are
/// per-partner and small); pass a pre-filtered list if the API supports search.
Future<T?> showSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  T? selected,
  bool Function(T a, T b)? equals,
  String hint = 'Search…',
  // Optional: items for which this returns false are shown but greyed out and
  // not tappable (e.g. a van already assigned to another driver). The reason
  // string (if any) is shown as a subtitle.
  bool Function(T)? enabledOf,
  String Function(T)? disabledReasonOf,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      String query = '';
      return StatefulBuilder(
        builder: (ctx, setS) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items
                  .where((it) => labelOf(it).toLowerCase().contains(q))
                  .toList();
          // Keyboard-aware: shrink the list so the sheet never overflows when
          // the search keyboard is open.
          final mq = MediaQuery.of(ctx);
          final maxH = (mq.size.height - mq.viewInsets.bottom - 200)
              .clamp(120.0, mq.size.height * 0.55);
          // Size the list area to the FULL list (not the filtered one) so the
          // sheet height stays CONSTANT while the user types/searches.
          final listH = (items.length * 50.0).clamp(120.0, maxH).toDouble();
          return SafeArea(
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setS(() => query = v),
                      decoration: InputDecoration(
                        hintText: hint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Fixed height (sized to the full list) → the sheet does NOT
                  // grow/shrink as search results change.
                  SizedBox(
                    height: listH,
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 38, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text('No matches',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final it = filtered[i];
                              final sel = selected != null &&
                                  (equals?.call(it, selected as T) ??
                                      it == selected);
                              final enabled = enabledOf?.call(it) ?? true;
                              final reason = disabledReasonOf?.call(it) ?? '';
                              return ListTile(
                                dense: true,
                                enabled: enabled,
                                title: Text(labelOf(it),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: enabled
                                            ? null
                                            : AppColors.textFaint)),
                                subtitle: (!enabled && reason.isNotEmpty)
                                    ? Text(reason,
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: AppColors.textFaint))
                                    : null,
                                trailing: sel
                                    ? Icon(Icons.check_circle,
                                        color: AppColors.brand600, size: 20)
                                    : (!enabled
                                        ? Icon(Icons.block,
                                            size: 16,
                                            color: AppColors.textFaint)
                                        : null),
                                onTap:
                                    enabled ? () => Navigator.pop(ctx, it) : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// Multi-select variant: search + checkboxes + a Done button. Returns the
/// chosen items (or null if dismissed without confirming).
Future<List<T>?> showMultiSearchablePicker<T>({
  required BuildContext context,
  required String title,
  required List<T> items,
  required String Function(T) labelOf,
  required Object Function(T) keyOf,
  List<T> selected = const [],
  String hint = 'Search…',
  // Optional: groups items under section headers (e.g. zones by emirate,
  // services by category).
  String Function(T)? groupOf,
}) {
  return showModalBottomSheet<List<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      String query = '';
      final chosen = {for (final s in selected) keyOf(s)};
      return StatefulBuilder(
        builder: (ctx, setS) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? items
              : items
                  .where((it) => labelOf(it).toLowerCase().contains(q))
                  .toList();
          // When grouped, build a flat list of section-header strings + items,
          // ordered by group then label.
          final rows = <dynamic>[];
          if (groupOf != null) {
            final byGroup = <String, List<T>>{};
            for (final it in filtered) {
              byGroup.putIfAbsent(groupOf(it), () => []).add(it);
            }
            final groups = byGroup.keys.toList()..sort();
            for (final g in groups) {
              rows.add(g); // header (String)
              rows.addAll(byGroup[g]!);
            }
          } else {
            rows.addAll(filtered);
          }
          final mq = MediaQuery.of(ctx);
          final maxH = (mq.size.height - mq.viewInsets.bottom - 240)
              .clamp(120.0, mq.size.height * 0.55);
          final listH = (items.length * 52.0).clamp(120.0, maxH).toDouble();
          return SafeArea(
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Text('${chosen.length} selected',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12.5)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setS(() => query = v),
                      decoration: InputDecoration(
                        hintText: hint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: listH,
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded,
                                    size: 38, color: Colors.grey.shade400),
                                const SizedBox(height: 8),
                                Text('No matches',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 8),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final row = rows[i];
                              if (row is String) {
                                // section header
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 4),
                                  child: Text(row.toUpperCase(),
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.5,
                                          color: AppColors.textMuted)),
                                );
                              }
                              final it = row as T;
                              final k = keyOf(it);
                              final sel = chosen.contains(k);
                              return CheckboxListTile(
                                dense: true,
                                value: sel,
                                activeColor: AppColors.brand600,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(labelOf(it),
                                    overflow: TextOverflow.ellipsis),
                                onChanged: (_) => setS(() {
                                  sel ? chosen.remove(k) : chosen.add(k);
                                }),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(
                            ctx,
                            items
                                .where((it) => chosen.contains(keyOf(it)))
                                .toList()),
                        child: const Text('Done'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

/// A read-only field that looks like a dropdown but opens [onTap]. Use with
/// [showSearchablePicker].
class PickerField extends StatelessWidget {
  final String value;
  final String hint;
  final VoidCallback onTap;
  const PickerField(
      {super.key, required this.value, required this.onTap, this.hint = 'Select'});

  @override
  Widget build(BuildContext context) {
    final empty = value.trim().isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(empty ? hint : value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: empty ? AppColors.textMuted : null,
                      fontSize: 15)),
            ),
            const Icon(Icons.keyboard_arrow_down, size: 22),
          ],
        ),
      ),
    );
  }
}
