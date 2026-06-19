import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/password_rules.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';

/// Handles both password reset (mode=reset) and invite setup (mode=setup).
class SetPasswordScreen extends ConsumerStatefulWidget {
  final String token;
  final String email;
  final bool setup; // true = invite setup, false = reset
  const SetPasswordScreen(
      {super.key,
      required this.token,
      required this.email,
      this.setup = false});

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _pw.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  bool get _ok =>
      PasswordRules.isValid(_pw.text) && _pw.text == _pw2.text;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      if (widget.setup) {
        await repo.setupPassword(widget.token, widget.email, _pw.text);
      } else {
        await repo.applyPasswordReset(widget.token, widget.email, _pw.text);
      }
      setState(() => _done = true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.setup ? 'Set your password' : 'Reset password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _done ? _success() : _form(),
        ),
      ),
    );
  }

  Widget _form() => ListView(
        children: [
          Text(
              widget.setup
                  ? 'Create a password to activate your account.'
                  : 'Choose a new password for ${widget.email}.',
              style: TextStyle(color: AppColors.textMuted)),
          const SizedBox(height: 20),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw2,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
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
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Passwords don\'t match',
                  style: TextStyle(color: AppColors.rose, fontSize: 12.5)),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (_ok && !_busy) ? _submit : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white))
                  : Text(widget.setup ? 'Activate account' : 'Reset password'),
            ),
          ),
        ],
      );

  Widget _success() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: AppColors.brand50, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle,
                  color: AppColors.brand600, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('All set',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Your password is ready. Sign in to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 20),
            ElevatedButton(
                onPressed: () => context.go('/login'),
                child: const Text('Go to sign in')),
          ],
        ),
      );
}
