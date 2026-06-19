import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'network/api_client.dart';
import 'storage/auth_storage.dart';

/// Singletons shared across the app.
final authStorageProvider = Provider<AuthStorage>((ref) => AuthStorage());

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/// Selected bottom-nav tab for RoleShell. Setting a large value lands on the
/// last (Profile) tab via the shell's clamp — used by the app-bar avatar.
final shellIndexProvider = StateProvider<int>((ref) => 0);
