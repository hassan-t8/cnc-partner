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

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _reason = TextEditingController();
  bool _busy = false;
  bool _loading = true;
  String? _error;

  /// The current request, if one exists. Drives the whole screen: pending
  /// shows the waiting state, rejected shows the outcome and lets them ask
  /// again, null shows the form.
  Map<String, dynamic>? _request;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.hourglass_top_rounded,
            color: AppColors.amber, size: 44),
        const SizedBox(height: 14),
        const Text('Your request is pending',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Text(
          'An administrator is reviewing your request to delete this account.'
          '${requestedAt != null ? '\n\nSent ${_shortDate(requestedAt)}.' : ''}'
          '\n\nYour account stays active in the meantime — keep working as '
          'normal until you hear back.',
          style: TextStyle(
              color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: _busy ? null : _withdraw,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Withdraw request'),
        ),
      ],
    );
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
