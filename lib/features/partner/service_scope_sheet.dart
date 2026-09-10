import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'partner_repository.dart';
import 'service_scope.dart';

/// What a service covers — included, not included, and the equipment brought.
///
/// The partner portal added this so a crew arrives knowing the same scope the
/// customer was sold. Before it, the only answer to "is the balcony in this
/// job?" was to call the office.
class ServiceScopeSheet extends StatefulWidget {
  const ServiceScopeSheet({
    super.key,
    required this.repo,
    required this.slug,
    required this.name,
  });

  final PartnerRepository repo;
  final String slug;
  final String name;

  static Future<void> show(
    BuildContext context, {
    required PartnerRepository repo,
    required String slug,
    required String name,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServiceScopeSheet(repo: repo, slug: slug, name: name),
    );
  }

  @override
  State<ServiceScopeSheet> createState() => _ServiceScopeSheetState();
}

class _ServiceScopeSheetState extends State<ServiceScopeSheet> {
  bool _loading = true;
  ServiceScope? _scope;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await widget.repo.serviceScope(widget.slug);
    if (!mounted) return;
    setState(() {
      _scope = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(child: _body(controller)),
          ],
        ),
      ),
    );
  }

  Widget _body(ScrollController controller) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2.4, color: AppColors.brand600),
      );
    }
    final s = _scope;
    if (s == null || s.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No scope details recorded for this service yet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ),
      );
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        if (s.description.isNotEmpty) ...[
          Text(
            s.description,
            style: TextStyle(
                fontSize: 13.5, height: 1.45, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
        ],
        // Ticks and crosses rather than plain bullets: an "included" list and
        // an "excluded" list read identically as two columns of dots, and
        // mistaking one for the other is the argument this sheet exists to
        // prevent.
        _list("What's included", s.included, Icons.check_circle,
            AppColors.brand600),
        _list("What's not included", s.excluded, Icons.cancel, AppColors.rose),
        _list('Equipment we bring', s.equipment, Icons.handyman, AppColors.sky),
      ],
    );
  }

  Widget _list(String title, List<String> items, IconData icon, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          ...items.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 9),
                    child: Icon(icon, size: 15, color: color),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
