import 'dart:io';

import '../../core/util/request_id.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/image_source_sheet.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Deposit to the partner wallet — the app's port of the portal's
/// `_DepositModal` (2026-09-25 rewrite).
///
/// The partner states HOW they paid CNC (Cash / Bank Transfer), which CNC bank
/// account a transfer went into, and can attach a photo or PDF of the bank slip / cash
/// receipt. Submitting calls `POST /partner-cash-requests` (`type: 'deposit'`);
/// the row lands `pending` and the wallet is credited only when an admin
/// approves it. The HyperPay card path is frozen server-side — legacy
/// in-flight checkouts can still be resumed from the Deposits tab.
///
/// Resolves `true` when a request was submitted, so the caller can refresh.
Future<bool> showDepositSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _DepositSheet(),
  );
  return ok ?? false;
}

class _DepositSheet extends ConsumerStatefulWidget {
  const _DepositSheet();
  @override
  ConsumerState<_DepositSheet> createState() => _DepositSheetState();
}

class _DepositSheetState extends ConsumerState<_DepositSheet> {
  /// Matches the backend multer limit.
  static const _maxProofBytes = 50 * 1024 * 1024;

  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'cash'; // cash | bank_transfer
  int? _bankId;
  String? _proofPath;
  bool _busy = false;
  String? _error;

  List<CncBankAccount> _banks = const [];
  bool _banksLoading = true;
  String? _banksError;

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _notes]) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
    _loadBanks();
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    setState(() {
      _banksLoading = true;
      _banksError = null;
    });
    try {
      final banks =
          await ref.read(partnerRepositoryProvider).cncBankAccounts();
      if (!mounted) return;
      setState(() {
        _banks = banks;
        _banksLoading = false;
        // A reload (after BANK_NOT_FOUND) may have dropped the picked bank.
        if (!banks.any((b) => b.id == _bankId)) _bankId = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _banksError = e.message;
        _banksLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _banksError = 'Failed to load bank accounts';
        _banksLoading = false;
      });
    }
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _bankMissing => _method == 'bank_transfer' && _bankId == null;
  bool get _canSubmit => !_busy && _amountValue > 0 && !_bankMissing;

  CncBankAccount? get _pickedBank {
    for (final b in _banks) {
      if (b.id == _bankId) return b;
    }
    return null;
  }

  /// Idempotency key for this deposit attempt.
  ///
  /// STABLE across retries of the same intent, so resending after a network
  /// drop returns the row the server already created (deduped) instead of
  /// filing a second request. Re-minted when the amount, method or bank
  /// changes: the dedup branch returns the EXISTING row, old amount and all,
  /// so reusing a key across an edit would silently keep the old values.
  String _clientRequestId = newRequestId('deposit');
  String? _keyIntent;

  String _requestIdFor(double amount, String method, int? bankId) {
    final intent = '$amount|$method|$bankId';
    if (_keyIntent != intent) {
      _clientRequestId = newRequestId('deposit');
      _keyIntent = intent;
    }
    return _clientRequestId;
  }

  Future<void> _pickProof() async {
    final picked = await pickProfileImage(
      context,
      title: 'Bank slip / cash receipt',
      maxWidth: 2048,
      // Portal parity: the proof is "image or PDF".
      allowPdf: true,
    );
    if (picked == null || !mounted) return;
    if (await File(picked.path).length() > _maxProofBytes) {
      AppToast.error('File too large — max 50 MB.');
      return;
    }
    if (mounted) setState(() => _proofPath = picked.path);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final amount = _amountValue;
    final bankId = _method == 'bank_transfer' ? _bankId : null;
    try {
      await ref.read(partnerRepositoryProvider).submitDeposit(
            amount: amount,
            clientRequestId: _requestIdFor(amount, _method, bankId),
            paymentMethod: _method,
            cncBankId: bankId,
            notes: _notes.text.trim(),
            proofFilePath: _proofPath,
          );
      if (!mounted) return;
      AppToast.success(_method == 'cash'
          ? 'Cash deposit request for AED ${amount.toStringAsFixed(2)} '
              'submitted — awaiting admin approval.'
          : 'Bank transfer deposit for AED ${amount.toStringAsFixed(2)} '
              'submitted — awaiting admin approval.');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'WALLET_FROZEN' => 'Your wallet is frozen. Contact support.',
          'BANK_ACCOUNT_REQUIRED' =>
            'Please pick which CNC bank account you paid into.',
          'BANK_NOT_FOUND' || 'INVALID_BANK_ACCOUNT' =>
            'That CNC bank account is no longer active. Please pick another.',
          _ => e.message,
        };
      });
      // A bank that went inactive must be dropped from the list.
      if (e.code == 'BANK_NOT_FOUND') _loadBanks();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed to submit deposit request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // Clearance for the system gesture / navigation bar, so the Submit button
    // isn't flush against it. Skipped while the keyboard is up — the nav bar sits
    // behind the keyboard then, and adding both would leave a dead gap.
    final systemBottom = keyboard > 0 ? 0.0 : mq.viewPadding.bottom;

    // Pin the header, scroll the rest, and cap the sheet — a fixed Column
    // overflows as soon as the keyboard opens.
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + systemBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _infoBanner(),
                    const SizedBox(height: 16),
                    _label('Amount (AED)', required: true),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _amount,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'),
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: '0.00',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final v in const [50, 100, 250, 500])
                          ActionChip(
                            label: Text('AED $v'),
                            onPressed: _busy
                                ? null
                                : () => _amount.text = v.toString(),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _label('Payment method', required: true),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _methodTile(
                            'cash',
                            'Cash',
                            Icons.payments_outlined,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _methodTile(
                            'bank_transfer',
                            'Bank Transfer',
                            Icons.account_balance_outlined,
                          ),
                        ),
                      ],
                    ),
                    if (_method == 'bank_transfer') ...[
                      const SizedBox(height: 16),
                      _label('Which CNC bank did you pay into?',
                          required: true),
                      const SizedBox(height: 6),
                      _bankPicker(),
                    ],
                    const SizedBox(height: 16),
                    _label('Proof attachment',
                        hint: ' (optional but recommended)'),
                    const SizedBox(height: 6),
                    _proofPicker(),
                    const SizedBox(height: 4),
                    Text(
                      'Upload your bank transfer receipt / cash slip so admin '
                      'can verify quickly.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 16),
                    _label('Notes', hint: ' (optional)'),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _notes,
                      enabled: !_busy,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText:
                            'Any details that help admin verify this deposit',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.rose,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _canSubmit ? _submit : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded, size: 16),
                        label: Text(
                          _busy ? 'Submitting…' : 'Submit for approval',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_card_rounded,
                size: 18,
                color: AppColors.brand700,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Deposit to wallet',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Submit for admin approval. Wallet credits once approved.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.black45),
              onPressed: _busy ? null : () => Navigator.pop(context, false),
            ),
          ],
        ),
      );

  Widget _infoBanner() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 17, color: AppColors.amber),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Submit a deposit request with proof (bank slip or cash '
                'receipt). An admin will review + approve, then your wallet '
                'balance updates.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );

  Widget _label(String text, {bool required = false, String? hint}) =>
      Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                  text: ' *', style: TextStyle(color: AppColors.rose)),
            if (hint != null)
              TextSpan(
                text: hint,
                style: TextStyle(
                    fontWeight: FontWeight.w400, color: AppColors.textMuted),
              ),
          ],
        ),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      );

  Widget _bankPicker() {
    if (_banksLoading) {
      return _bankNotice(
        'Loading bank accounts…',
        AppColors.textMuted,
        leading: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_banksError != null) {
      return _bankNotice(
        _banksError!,
        AppColors.rose,
        leading: const Icon(Icons.warning_amber_rounded,
            size: 16, color: AppColors.rose),
        trailing: TextButton(
          onPressed: _busy ? null : _loadBanks,
          child: const Text('Retry'),
        ),
      );
    }
    if (_banks.isEmpty) {
      return _bankNotice(
        'No active CNC bank accounts. Please contact admin.',
        AppColors.amber,
      );
    }
    final picked = _pickedBank;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          // Re-created when the list reloads, so it never holds an id that is
          // no longer among its items.
          key: ValueKey(_banks),
          initialValue: picked?.id,
          isExpanded: true,
          hint: const Text('Select bank account…'),
          decoration: InputDecoration(
            isDense: true,
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          items: [
            for (final b in _banks)
              DropdownMenuItem(
                value: b.id,
                child: Text(b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5)),
              ),
          ],
          onChanged: _busy ? null : (v) => setState(() => _bankId = v),
        ),
        if (picked != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('Bank', picked.bankName),
                _detail('Account Title', picked.accountTitle),
                _detail('Account No', picked.accountNo),
                _detail('IBAN', picked.iban),
                _detail('Branch', picked.branchName),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _detail(String k, String v) => v.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableText.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: v),
            ]),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        );

  Widget _bankNotice(String text, Color color,
          {Widget? leading, Widget? trailing}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 8)],
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 12, color: color)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _docThumb(IconData icon) => Container(
        width: 48,
        height: 48,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.rose, size: 26),
      );

  Widget _proofPicker() {
    final path = _proofPath;
    if (path == null) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy ? null : _pickProof,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border, width: 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_rounded, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(
                'Choose bank slip / cash receipt (image or PDF)',
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.brand600.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: isPdfPath(path)
                ? _docThumb(Icons.picture_as_pdf_outlined)
                : Image.file(File(path),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    // A format the platform cannot decode still uploads
                    // fine; show a file glyph rather than a broken box.
                    errorBuilder: (_, __, ___) =>
                        _docThumb(Icons.insert_drive_file_outlined)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              path.split(RegExp(r'[\\/]')).last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Remove file',
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.rose),
            onPressed: _busy ? null : () => setState(() => _proofPath = null),
          ),
        ],
      ),
    );
  }

  Widget _methodTile(String value, String label, IconData icon) {
    final on = _method == value;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _busy ? null : () => setState(() => _method = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: on ? AppColors.brand50 : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: on ? AppColors.brand600 : AppColors.border,
            width: on ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: on ? AppColors.brand700 : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: on ? AppColors.brand700 : AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
