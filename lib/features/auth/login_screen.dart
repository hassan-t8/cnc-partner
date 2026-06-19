import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/biometric_service.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/storage/auth_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/brand_logo.dart';
import '../onboarding/onboarding_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;
  bool _busy = false;
  List<SavedAccount> _accounts = const [];
  bool _bioReady = false;
  String _bioLabel = 'biometrics';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final storage = ref.read(authStorageProvider);
      final seen = await storage.seenOnboarding();
      if (!seen && mounted) {
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const OnboardingScreen()));
      }
      // Set up biometric quick-login if there are saved accounts.
      final accounts = await storage.savedAccounts();
      final bio = ref.read(biometricServiceProvider);
      final available = accounts.isNotEmpty &&
          await storage.biometricEnabled() &&
          await bio.isAvailable();
      final label = available ? await bio.label() : 'biometrics';
      if (mounted) {
        setState(() {
          _accounts = accounts;
          _bioReady = available;
          _bioLabel = label;
        });
      }
    });
  }

  Future<void> _biometricLogin() async {
    final bio = ref.read(biometricServiceProvider);
    final ok = await bio.authenticate('Sign in to CNC Partner');
    if (!ok) return;
    SavedAccount? account = _accounts.length == 1 ? _accounts.first : null;
    if (account == null && mounted) account = await _pickAccount();
    if (account == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authControllerProvider.notifier).loginWithSaved(account);
    } catch (e) {
      AppToast.error('Saved session expired — please sign in.');
      final fresh = await ref.read(authStorageProvider).savedAccounts();
      if (mounted) {
        setState(() {
          _accounts = fresh;
          _bioReady = _bioReady && fresh.isNotEmpty;
          _email.text = account!.email;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<SavedAccount?> _pickAccount() {
    return showModalBottomSheet<SavedAccount>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text('Choose an account',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final a in _accounts)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.brand50,
                  child: Text(
                      (a.name.isNotEmpty ? a.name[0] : a.email[0])
                          .toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.brand700,
                          fontWeight: FontWeight.w800)),
                ),
                title: Text(a.name.isEmpty ? a.email : a.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    [a.email, if (a.role.isNotEmpty) a.role].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, a),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .login(_email.text, _password.text);
      // Router redirect takes over on auth state change.
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } catch (e) {
      AppToast.error('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(size: 64)),
                    const SizedBox(height: 18),
                    const Text('Welcome back',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Sign in to the CNC Partner portal',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'Please enter your email';
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) {
                          return 'Please enter a valid email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Please enter your password' : null,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          final e = _email.text.trim();
                          context.push('/forgot-password'
                              '${e.isNotEmpty ? '?email=${Uri.encodeComponent(e)}' : ''}');
                        },
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    if (_bioReady) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: Divider(color: AppColors.border)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('or',
                                style: TextStyle(
                                    color: AppColors.textFaint, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: AppColors.border)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _biometricLogin,
                          icon: const Icon(Icons.fingerprint,
                              color: AppColors.brand600),
                          label: Text(
                              _accounts.length > 1
                                  ? 'Sign in with $_bioLabel'
                                  : 'Sign in with $_bioLabel',
                              style: const TextStyle(
                                  color: AppColors.brand700,
                                  fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: AppColors.brand600)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
