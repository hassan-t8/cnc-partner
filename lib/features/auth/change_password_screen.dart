import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/password_rules.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _current.text.isNotEmpty &&
      PasswordRules.isValid(_pw.text) &&
      _pw.text == _pw2.text;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(_current.text, _pw.text);
      // The backend keeps the existing session valid, so no re-login is
      // needed — just confirm and go back.
      AppToast.success('Password changed');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      // Stay on the screen and show the reason inline (a wrong current
      // password must NOT log the user out).
      if (mounted) setState(() => _error = e.message);
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _field('Current password', _current),
          const SizedBox(height: 14),
          _field('New password', _pw),
          const SizedBox(height: 14),
          _field('Confirm new password', _pw2),
          const SizedBox(height: 16),
          ...PasswordRules.checklist(_pw.text).map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(r.$2 ? Icons.check_circle : Icons.circle_outlined,
                        size: 16,
                        color: r.$2 ? AppColors.brand600 : AppColors.textFaint),
                    const SizedBox(width: 8),
                    Text(r.$1,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: r.$2
                                ? AppColors.textSecondary
                                : AppColors.textMuted)),
                  ],
                ),
              )),
          if (_pw2.text.isNotEmpty && _pw.text != _pw2.text)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Passwords don\'t match',
                  style: TextStyle(color: AppColors.rose, fontSize: 12.5)),
            ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.rose.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.rose.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.rose, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.rose,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_canSubmit && !_busy) ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : const Text('Update password'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c) => TextField(
        controller: c,
        obscureText: _obscure,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.lock_outline),
          suffixIcon: IconButton(
            icon: Icon(_obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}
