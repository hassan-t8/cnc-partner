import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/main_app_bar.dart';

/// In-app account deletion (App Store guideline 5.1.1(v)).
///
/// A partner account is not deleted on the spot. Bookings, workers, vans and
/// settlements hang off it, so removing one silently would take other
/// people's work with it — including money still owed. The request goes to an
/// administrator, and the account stays fully usable until they act on it.
///
/// The guideline is satisfied: the request is initiated and tracked inside
/// the app. What it rejects is being sent away to an email or a phone call,
/// which is what this screen used to do.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() =>
      _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen>
    with WidgetsBindingObserver {
  final _reason = TextEditingController();
  bool _busy = false;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  /// The current request, if one exists. Drives the whole screen: pending
  /// shows the waiting state, rejected shows the outcome and lets them ask
  /// again, null shows the form.
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // An admin can decide at any moment, and the answer arriving only when
    // the screen is reopened is how someone sits looking at "pending" long
    // after it was refused. Quiet, so the screen does not flash.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load(quiet: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the notification that says it was decided should show
    // the decision, not the state the screen held when it was backgrounded.
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet && mounted) setState(() => _loading = true);
    try {
      // ApiClient wraps the body in Response, so the payload is res.data.
      final body = (await ref
              .read(apiClientProvider)
              .get('/api/users/me/deletion-request'))
          .data;
      if (!mounted) return;
      setState(() {
        _request = (body is Map && body['request'] is Map)
            ? Map<String, dynamic>.from(body['request'] as Map)
            : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Not fatal — the form is still usable, and submitting twice is handled
      // server-side by returning the existing request.
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'Your account stays active until an administrator reviews this.\n\n'
          'They may contact you first if there are outstanding jobs or '
          'payouts to settle.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send request'),
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
      final body = (await ref.read(apiClientProvider).post(
        '/api/users/me/deletion-request',
        body: {'reason': _reason.text.trim()},
      ))
          .data;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _request = {
          'status': 'pending',
          'createdAt': (body is Map ? body['requestedAt'] : null) ??
              DateTime.now().toIso8601String(),
          'id': body is Map ? body['requestId'] : null,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not send the request. Please try again.';
      });
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/api/users/me/deletion-request/cancel', body: const {});
      if (!mounted) return;
      setState(() {
        _busy = false;
        _request = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not withdraw the request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Delete account'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_request?['status'] == 'pending')
                  _pending()
                else ...[
                  if (_request?['status'] == 'rejected') _rejected(),
                  _form(),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!,
                      style: const TextStyle(
                          color: AppColors.rose, fontSize: 13)),
                ],
              ],
            ),
    );
  }

  Widget _pending() {
    final requestedAt = _request?['createdAt']?.toString();
    final reason = _request?['reason']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The status is the whole point of this screen, so it gets a card of
        // its own rather than sitting as a heading above body text.
        Container(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
          ),
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded,
                    color: AppColors.amber, size: 26),
              ),
              const SizedBox(height: 14),
              const Text('Waiting for review',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'An administrator will decide on your request. You will be '
                'notified either way.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              // Three steps, so "pending" reads as a stage in something with
              // an end rather than an open-ended wait.
              _progress(),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Reassurance placed where it is read, not buried in the paragraph
        // above: the fear at this moment is that the account is already gone.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.brand100),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.brand700),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Your account is still active. Keep accepting jobs as '
                  'normal until you hear back.',
                  style: TextStyle(
                      fontSize: 12.5, height: 1.4, color: AppColors.brand700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detail('Submitted',
                  requestedAt != null ? _shortDate(requestedAt) : '—'),
              if (reason != null && reason.isNotEmpty) ...[
                const SizedBox(height: 10),
                _detail('Your reason', reason),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),

        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _confirmWithdraw,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.undo_rounded, size: 18),
            label: Text(_busy ? 'Withdrawing…' : 'Withdraw request'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Changed your mind? Withdrawing cancels the request and nothing '
          'happens to your account.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, height: 1.4, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  /// Submitted → Under review → Decision, with the current stage filled.
  Widget _progress() => Row(
        children: [
          _step('Sent', done: true),
          _bar(active: true),
          _step('Reviewing', done: true, current: true),
          _bar(active: false),
          _step('Decision', done: false),
        ],
      );

  Widget _step(String label, {required bool done, bool current = false}) {
    final color = done ? AppColors.amber : AppColors.border;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: current
              ? const Icon(Icons.more_horiz, size: 10, color: Colors.white)
              : done
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
        ),
        const SizedBox(height: 5),
        Text(label,
            style: TextStyle(
                fontSize: 10.5,
                fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                color: done ? AppColors.amber : AppColors.textSecondary)),
      ],
    );
  }

  Widget _bar({required bool active}) => Expanded(
        child: Container(
          height: 2,
          margin: const EdgeInsets.only(bottom: 18),
          color: active ? AppColors.amber : AppColors.border,
        ),
      );

  Widget _detail(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
      );

  /// Withdrawing is easy to tap by accident on a screen whose other button
  /// is destructive, so it asks first.
  Future<void> _confirmWithdraw() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Withdraw your request?'),
        content: const Text(
          'The request is cancelled and your account carries on unchanged. '
          'You can ask again at any time.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep waiting')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Withdraw')),
        ],
      ),
    );
    if (go == true) await _withdraw();
  }

  Widget _rejected() {
    final note = _request?['reviewNote']?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.rose.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.rose.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Your last request was declined',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(note,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Text('You can send another request below.',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded,
            color: AppColors.rose, size: 44),
        const SizedBox(height: 14),
        const Text('Request account deletion',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          'Partner accounts are deleted by an administrator, because jobs, '
          'workers and settlements are attached to them.\n\n'
          'Your account stays active until the request is approved. Completed '
          'bookings are kept for legal and settlement records as required, no '
          'longer linked to your account.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 22),
        const Text('Reason (optional)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _reason,
          enabled: !_busy,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(
            hintText: 'Tell us why, so we can help if something is wrong',
            hintStyle: const TextStyle(fontSize: 13.5),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.rose,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Send deletion request'),
          ),
        ),
      ],
    );
  }

  String _shortDate(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.day}/${d.month}/${d.year}';
  }
}
