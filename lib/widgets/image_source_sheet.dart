import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/theme/app_colors.dart';

/// Bottom sheet offering Camera / Gallery / Cancel, then returns the picked
/// image (or null if the user backed out). Centralises the picker so every
/// place that changes the profile photo behaves identically.
///
/// [title] / [maxWidth] let other flows reuse it (e.g. a deposit receipt,
/// which needs more resolution than an avatar to stay legible).
///
/// [allowPdf] adds a third option that picks a PDF (or an image file) from
/// the device's files — the portal's deposit proof accepts "image or PDF".
/// The result is still an [XFile]; check [isPdfPath] before previewing it.
Future<XFile?> pickProfileImage(
  BuildContext context, {
  String title = 'Update photo',
  double maxWidth = 1024,
  bool allowPdf = false,
}) async {
  final source = await showModalBottomSheet<_PickSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined,
                color: AppColors.brand600),
            title: const Text('Take photo'),
            onTap: () => Navigator.pop(ctx, _PickSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.brand600),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, _PickSource.gallery),
          ),
          if (allowPdf)
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined,
                  color: AppColors.brand600),
              title: const Text('Choose PDF or file'),
              onTap: () => Navigator.pop(ctx, _PickSource.document),
            ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.close, color: AppColors.textMuted),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(ctx),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  if (source == _PickSource.document) {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    final f = (res == null || res.files.isEmpty) ? null : res.files.single;
    if (f?.path == null) return null;
    return XFile(f!.path!, name: f.name);
  }
  return ImagePicker().pickImage(
    source: source == _PickSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: maxWidth,
    imageQuality: 85,
  );
}

enum _PickSource { camera, gallery, document }

/// True when [path] names a PDF — the caller shows a document tile instead of
/// an image preview, which `Image.file` cannot render.
bool isPdfPath(String path) => path.trim().toLowerCase().endsWith('.pdf');
