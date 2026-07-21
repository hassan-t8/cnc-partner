import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/main_app_bar.dart';

/// In-app account deletion (App Store guideline 5.1.1(v)).
///
/// This screen used to email a request via `mailto:`. Apple rejects that for
/// any app outside a highly-regulated industry — the guideline is explicit
/// that requiring a phone call or email to delete an account is not
/// sufficient. The backend already exposes a self-delete endpoint
/// (`DELETE /api/users/me/delete-account`, password-confirmed), so the
/// deletion now runs from inside the app and signs the user out on success.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password to confirm.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
            'This permanently deletes your account and cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiClientProvider).delete(
        '/api/users/me/delete-account',
        body: {'password': _password.text},
      );
      // Sign out on success — clears the token, tears down the socket and
      // returns to the login screen the same way a normal logout does. A
      // half-cleared session after deletion would leave the next sign-in
      // reading a deleted user's cached state.
      await ref.read(authControllerProvider.notifier).signOut();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not delete your account. '
            'Check your password and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Delete account'),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.rose, size: 44),
          const SizedBox(height: 14),
          const Text('Delete your account',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'This permanently deletes your profile and stops all future job '
            'offers. It cannot be undone.\n\n'
            'Bookings you have already completed are kept for legal and '
            'settlement records as required, no longer linked to your account.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          const Text('Confirm with your password',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _password,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              hintText: 'Your password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: AppColors.rose, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.rose,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _delete,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_outline),
            label: Text(_busy ? 'Deleting…' : 'Delete account'),
          ),
        ],
      ),
    );
  }
}
