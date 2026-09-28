import '../../core/util/request_id.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_profile_screen.dart';
import 'partner_repository.dart';

/// Partner withdraw request — the app's port of the portal's `_WithdrawModal`.
///
/// 2026-09-25 (portal parity): no more typed-in bank fields. The partner picks
/// one of the bank accounts SAVED on their profile; its details are
/// snapshotted onto the request so admin pays the exact account even if the
/// profile is edited later. With no saved account, submit is blocked and the
/// sheet points to Profile → Bank Accounts.
///
/// Submitting immediately moves the amount out of `wallet.balance` and into
/// `wallet.heldBalance` server-side, inside a transaction, before the row is
/// written. The money is locked the moment this returns true.
///
/// Resolves `true` when a request was submitted, so the caller can refresh.
Future<bool> showWithdrawSheet(
  BuildContext context, {
  required double availableBalance,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _WithdrawSheet(availableBalance: availableBalance),
  );
  return ok ?? false;
}

class _WithdrawSheet extends ConsumerStatefulWidget {
  const _WithdrawSheet({required this.availableBalance});
  final double availableBalance;

  @override
  ConsumerState<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<_WithdrawSheet> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();

  List<BankAccount> _banks = const [];
  bool _banksLoading = true;
  String? _banksError;
  int _selectedIdx = -1;

  /// Minted ONCE per open, never per submit. The backend keys idempotency on
  /// `withdraw:<partnerId>:<clientRequestId>`; reusing it is what stops a retry
  /// after a network timeout from placing a second hold on the same money.
  late final String _clientRequestId = _newRequestId();

  bool _busy = false;
  String? _error;

  static String _newRequestId() => newRequestId('withdraw');

  @override
  void initState() {
    super.initState();
    for (final c in [_amount, _notes]) {
      c.addListener(_rebuild);
    }
    _loadBanks();
  }

  /// The partner's saved bank accounts (Profile → Bank Accounts). Rows with
  /// no account number are skipped — there is nothing to pay out to.
  Future<void> _loadBanks() async {
    setState(() {
      _banksLoading = true;
      _banksError = null;
    });
    final partnerId = ref.read(authControllerProvider).user?.partnerId;
    if (partnerId == null) {
      setState(() {
        _banksLoading = false;
        _banksError = 'Missing partner id — please sign in again.';
      });
      return;
    }
    try {
      final p =
          await ref.read(partnerRepositoryProvider).getPartner(partnerId);
      if (!mounted) return;
      // Any identifying field will do — account number, IBAN or bank name.
      // Some saved accounts carry only an IBAN, and dropping them left the
      // partner told they had no account (portal fix 2026-09-25).
      final clean = p.bankDetails
          .where((b) =>
              b.accountNumber.trim().isNotEmpty ||
              b.ibanNumber.trim().isNotEmpty ||
              b.bankName.trim().isNotEmpty)
          .toList();
      setState(() {
        _banks = clean;
        _banksLoading = false;
        _selectedIdx = clean.length == 1 ? 0 : -1;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _banksLoading = false;
        _banksError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _banksLoading = false;
        _banksError = 'Failed to load your bank accounts';
      });
    }
  }

  /// Open the profile editor to add a bank account, then reload the list.
  Future<void> _addBankAccount() async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PartnerProfileScreen(startInEdit: true)));
    if (mounted) _loadBanks();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_amount, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _exceedsBalance => _amountValue > widget.availableBalance + 0.001;

  BankAccount? get _picked =>
      _selectedIdx >= 0 && _selectedIdx < _banks.length
          ? _banks[_selectedIdx]
          : null;

  bool get _canSubmit =>
      !_busy && _amountValue > 0 && !_exceedsBalance && _picked != null;

  String _money(double n) => 'AED ${n.toStringAsFixed(2)}';

  Future<void> _submit() async {
    final bank = _picked;
    if (!_canSubmit || bank == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Snapshot the picked account onto the request.
      await ref.read(partnerRepositoryProvider).submitWithdraw(
            amount: _amountValue,
            clientRequestId: _clientRequestId,
            bankAccountName: bank.accountHolderName.trim(),
            bankAccountNumber: bank.accountNumber.trim(),
            bankName: bank.bankName.trim(),
            iban: bank.ibanNumber.trim(),
            notes: _notes.text.trim(),
          );
      if (!mounted) return;
      AppToast.success('Withdraw request submitted — funds are now on hold.');
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'INSUFFICIENT_BALANCE' => 'Amount exceeds your available balance.',
          'WALLET_FROZEN' => 'Your wallet is frozen. Contact support.',
          _ => e.message,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Failed to submit withdraw request.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    // Clear the system gesture / nav bar so the submit button isn't flush
    // against it. Skipped while the keyboard is up (the nav bar is behind it).
    final systemBottom = keyboard > 0 ? 0.0 : mq.viewPadding.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + systemBottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _holdNotice(),
                    const SizedBox(height: 16),
                    _field(
                      label: 'Amount (AED)',
                      required: true,
                      controller: _amount,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      hint: '0.00',
                      error: _exceedsBalance
                          ? 'Exceeds available balance of '
                              '${_money(widget.availableBalance)}'
                          : null,
                      trailing: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _amount.text =
                                widget.availableBalance.toStringAsFixed(2),
                        child: const Text('Max'),
                      ),
                    ),
                    _bankPicker(),
                    const SizedBox(height: 12),
                    _field(
                      label: 'Notes (optional)',
                      controller: _notes,
                      maxLength: 500,
                      maxLines: 2,
                      hint: 'Anything admin should know about this withdrawal',
                      showCounter: true,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: const TextStyle(
                            color: AppColors.rose,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _actions(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.south_rounded,
                  size: 18, color: AppColors.brand700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Withdraw funds',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text('Available ${_money(widget.availableBalance)}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54)),
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

  Widget _holdNotice() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 17, color: AppColors.amber),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'The amount is put on hold immediately. It leaves your '
                'available balance and waits for admin approval before landing '
                'in your bank.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      );

  /// "Deposit to" — the saved-account dropdown plus a details preview.
  Widget _bankPicker() {
    final Widget body;
    if (_banksLoading) {
      body = _notice(
        'Loading your bank accounts…',
        AppColors.textMuted,
        leading: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (_banksError != null) {
      body = _notice(
        _banksError!,
        AppColors.rose,
        trailing: TextButton(
            onPressed: _busy ? null : _loadBanks, child: const Text('Retry')),
      );
    } else if (_banks.isEmpty) {
      body = _notice(
        "You haven't added any bank accounts yet. Add one from "
        'Profile → Bank Accounts, then come back here.',
        AppColors.amber,
        trailing: TextButton(
            onPressed: _busy ? null : _addBankAccount,
            child: const Text('Add')),
      );
    } else {
      body = DropdownButtonFormField<int>(
        // Re-created when the list reloads, so it never holds a stale index.
        key: ValueKey(_banks),
        initialValue: _selectedIdx >= 0 ? _selectedIdx : null,
        isExpanded: true,
        hint: const Text('Select an account…'),
        decoration: InputDecoration(
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: [
          for (var i = 0; i < _banks.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                '${_banks[i].bankName.isEmpty ? 'Bank' : _banks[i].bankName}'
                ' · ${_tail(_banks[i], i)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
        onChanged:
            _busy ? null : (v) => setState(() => _selectedIdx = v ?? -1),
      );
    }

    final picked = _picked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text.rich(
          TextSpan(
            text: 'Deposit to',
            children: [
              TextSpan(text: ' *', style: TextStyle(color: AppColors.rose))
            ],
          ),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, height: 1.6),
        ),
        const SizedBox(height: 4),
        body,
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
                _detail('Account Holder', picked.accountHolderName),
                _detail('Account No', picked.accountNumber),
                _detail('IBAN', picked.ibanNumber),
                _detail('Branch', picked.branchName),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _last4(String s) =>
      s.length <= 4 ? s : s.substring(s.length - 4);

  /// Last 4 of the account number, else of the IBAN, else the branch — so
  /// two accounts at the same bank can still be told apart (portal parity).
  static String _tail(BankAccount b, int i) {
    final id = (b.accountNumber.trim().isNotEmpty
            ? b.accountNumber
            : b.ibanNumber)
        .trim();
    if (id.isNotEmpty) return '••••${_last4(id)}';
    return b.branchName.trim().isNotEmpty ? b.branchName.trim() : '#${i + 1}';
  }

  Widget _detail(String k, String v) => v.trim().isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: v),
            ]),
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        );

  Widget _notice(String text, Color color,
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
                  style: TextStyle(fontSize: 12, color: color, height: 1.35)),
            ),
            if (trailing != null) trailing,
          ],
        ),
      );

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool required = false,
    String? hint,
    String? error,
    int? maxLength,
    int maxLines = 1,
    bool monospace = false,
    bool showCounter = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: label,
              children: required
                  ? const [
                      TextSpan(
                          text: ' *', style: TextStyle(color: AppColors.rose))
                    ]
                  : null,
            ),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, height: 1.6),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            enabled: !_busy,
            maxLines: maxLines,
            maxLength: maxLength,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: TextStyle(
                fontSize: 14,
                fontFamily: monospace ? 'monospace' : null),
            decoration: InputDecoration(
              hintText: hint,
              isDense: true,
              counterText: showCounter ? null : '',
              errorText: error,
              suffixIcon: trailing,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    // The scroll body already clears the nav bar via `systemBottom`, but this
    // footer sits BELOW it and had a fixed 20px bottom — so on Android 15
    // (edge-to-edge) the Cancel / Request-withdraw buttons hid behind the
    // system nav bar. Add the same inset here. Zero while the keyboard is up
    // (the outer Padding has already lifted the sheet above it).
    final mq = MediaQuery.of(context);
    final systemBottom = mq.viewInsets.bottom > 0 ? 0.0 : mq.viewPadding.bottom;
    return Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + systemBottom),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.south_rounded, size: 16),
                label: Text(_busy ? 'Submitting…' : 'Withdraw'),
              ),
            ),
          ],
        ),
      );
  }
}

