import '../../core/util/request_id.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import 'partner_repository.dart';

/// Partner withdraw request — the app's port of the portal's `_WithdrawModal`.
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
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _bankName = TextEditingController();
  final _iban = TextEditingController();
  final _notes = TextEditingController();

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
    for (final c in [_amount, _accountName, _accountNumber]) {
      c.addListener(_rebuild);
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _amount,
      _accountName,
      _accountNumber,
      _bankName,
      _iban,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _exceedsBalance => _amountValue > widget.availableBalance + 0.001;

  bool get _canSubmit =>
      !_busy &&
      _amountValue > 0 &&
      !_exceedsBalance &&
      _accountName.text.trim().isNotEmpty &&
      _accountNumber.text.trim().isNotEmpty;

  String _money(double n) => 'AED ${n.toStringAsFixed(2)}';

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(partnerRepositoryProvider).submitWithdraw(
            amount: _amountValue,
            clientRequestId: _clientRequestId,
            bankAccountName: _accountName.text.trim(),
            bankAccountNumber: _accountNumber.text.trim(),
            bankName: _bankName.text.trim(),
            iban: _iban.text.trim(),
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
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
                    _field(
                      label: 'Account holder name',
                      required: true,
                      controller: _accountName,
                      maxLength: 120,
                    ),
                    _field(
                      label: 'Account number',
                      required: true,
                      controller: _accountNumber,
                      maxLength: 60,
                    ),
                    _field(
                      label: 'Bank name',
                      controller: _bankName,
                      maxLength: 120,
                    ),
                    _field(
                      label: 'IBAN',
                      controller: _iban,
                      maxLength: 60,
                      hint: 'AE07 0331 2345 6789 0123 456',
                      monospace: true,
                      // The backend stores it verbatim; upper-case it here so
                      // two partners don't file the same IBAN in two casings.
                      inputFormatters: [_UpperCaseFormatter()],
                    ),
                    _field(
                      label: 'Notes (optional)',
                      controller: _notes,
                      maxLength: 500,
                      maxLines: 2,
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

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool required = false,
    String? hint,
    String? error,
    int? maxLength,
    int maxLines = 1,
    bool monospace = false,
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
              counterText: '',
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

  Widget _actions() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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
                label: Text(_busy ? 'Submitting…' : 'Request withdraw'),
              ),
            ),
          ],
        ),
      );
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
