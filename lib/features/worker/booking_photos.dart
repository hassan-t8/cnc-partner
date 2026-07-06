import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/env.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/image_source_sheet.dart';
import 'worker_repository.dart';

/// Before / after job photos: an "Add" tile + a horizontal strip of uploaded
/// thumbnails (tap to preview full-screen), with an inline spinner tile while
/// an upload is in flight so the user can feel something is happening.
class BookingPhotos extends ConsumerStatefulWidget {
  final int assignmentId;
  final bool showAfter; // also show the "After photos" strip
  final bool canAdd;
  // Compact mode: render a one-line "Job photos (N)" header that expands to the
  // strips on tap — keeps list cards short. The full strips show inline
  // (non-collapsible) on the detail screen.
  final bool collapsible;
  const BookingPhotos({
    super.key,
    required this.assignmentId,
    this.showAfter = false,
    this.canAdd = true,
    this.collapsible = false,
  });

  @override
  ConsumerState<BookingPhotos> createState() => _BookingPhotosState();
}

class _BookingPhotosState extends ConsumerState<BookingPhotos> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _expanded = false; // collapsible mode only
  final Set<String> _uploading = {}; // 'before' | 'after'

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await ref
          .read(workerRepositoryProvider)
          .attachments(widget.assignmentId);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _url(dynamic f) {
    final s = (f ?? '').toString();
    if (s.isEmpty) return '';
    if (s.startsWith('http')) return s;
    if (s.startsWith('/')) return '${Env.apiUrl}$s';
    return '${Env.apiUrl}/uploads/$s';
  }

  Future<void> _add(String type) async {
    final picked = await pickProfileImage(context);
    if (picked == null) return;
    setState(() => _uploading.add(type));
    try {
      await ref
          .read(workerRepositoryProvider)
          .uploadAttachment(widget.assignmentId, picked.path, type);
      AppToast.success('Photo uploaded');
      await _load();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } catch (_) {
      AppToast.error('Upload failed.');
    } finally {
      if (mounted) setState(() => _uploading.remove(type));
    }
  }

  void _preview(String url) {
    if (url.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (c, w, p) => p == null
                    ? w
                    : const SizedBox(
                        height: 220,
                        child: Center(
                            child: CircularProgressIndicator(
                                color: Colors.white))),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    color: Colors.white54, size: 48),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsible) return _collapsible();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _strip('before', 'Before photos'),
        if (widget.showAfter) ...[
          const SizedBox(height: 12),
          _strip('after', 'After photos'),
        ],
      ],
    );
  }

  /// One-line header (icon + "Job photos" + count) that expands to the strips —
  /// keeps the crew job cards compact.
  Widget _collapsible() {
    final count = _items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 6),
                const Text('Job photos',
                    style:
                        TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('$count',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand700)),
                  ),
                ],
                const Spacer(),
                if (count == 0 && !_loading && widget.canAdd)
                  Text('Add',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand600)),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 24, color: AppColors.brand600),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          _strip('before', 'Before'),
          if (widget.showAfter) ...[
            const SizedBox(height: 12),
            _strip('after', 'After'),
          ],
        ],
      ],
    );
  }

  Widget _strip(String type, String label) {
    final imgs =
        _items.where((m) => (m['type'] ?? '').toString() == type).toList();
    final uploading = _uploading.contains(type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            if (imgs.isNotEmpty)
              Text('${imgs.length}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 66,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final m in imgs) _thumb(_url(m['fileUrl'] ?? m['url'])),
              if (uploading) _uploadingTile(),
              if (widget.canAdd) _addTile(type, uploading),
              if (_loading && imgs.isEmpty && !uploading) _skeletonTile(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _box({required Widget child, Color? border, Color? fill}) => Container(
        width: 64,
        height: 64,
        margin: const EdgeInsets.only(right: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: fill ?? AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border ?? AppColors.border),
        ),
        child: child,
      );

  Widget _thumb(String url) => GestureDetector(
        onTap: () => _preview(url),
        child: _box(
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (c, w, p) => p == null
                ? w
                : Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.brand600))),
            errorBuilder: (_, __, ___) =>
                Icon(Icons.broken_image, color: AppColors.textFaint, size: 22),
          ),
        ),
      );

  Widget _uploadingTile() => _box(
        fill: AppColors.brand50,
        border: AppColors.brand600.withValues(alpha: 0.4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: AppColors.brand600)),
            const SizedBox(height: 4),
            Text('Uploading',
                style: TextStyle(fontSize: 9.5, color: AppColors.brand700)),
          ],
        ),
      );

  Widget _skeletonTile() => _box(
        child: Center(
          child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.textFaint)),
        ),
      );

  Widget _addTile(String type, bool uploading) => GestureDetector(
        onTap: uploading ? null : () => _add(type),
        child: Container(
          width: 64,
          height: 64,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.brand600.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_a_photo_outlined,
                  size: 20, color: AppColors.brand700),
              const SizedBox(height: 3),
              Text('Add',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand700)),
            ],
          ),
        ),
      );
}
