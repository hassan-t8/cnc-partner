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
          final maxH = MediaQuery.of(ctx).size.height * 0.55;
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
                              return ListTile(
                                dense: true,
                                title: Text(labelOf(it),
                                    overflow: TextOverflow.ellipsis),
                                trailing: sel
                                    ? Icon(Icons.check_circle,
                                        color: AppColors.brand600, size: 20)
                                    : null,
                                onTap: () => Navigator.pop(ctx, it),
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
