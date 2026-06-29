import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/env.dart';

/// Single source of truth for the signed-in user's profile image, so the app
/// bar avatar, the profile hub header and the edit screen all stay in sync.
/// Holds the fully-qualified image URL (or null when there's no photo).
final profileImageProvider =
    NotifierProvider<ProfileImageNotifier, String?>(ProfileImageNotifier.new);

class ProfileImageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Set from a server filename or URL. Pass an empty/null value to clear.
  void setFromFilename(String? filename) => state = urlFor(filename);

  /// Build a fully-qualified image URL from a stored filename/path.
  static String? urlFor(String? f) {
    if (f == null || f.isEmpty) return null;
    if (f.startsWith('http')) return f;
    if (f.startsWith('/uploads/')) return '${Env.apiUrl}$f';
    return '${Env.apiUrl}/uploads/$f';
  }
}
