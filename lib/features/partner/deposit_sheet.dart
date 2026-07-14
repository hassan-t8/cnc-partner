import '../../core/util/request_id.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import 'deposit_checkout_screen.dart';
import 'partner_repository.dart';

/// Top up the partner wallet by card — the app's port of the portal's
/// `_DepositModal`. Collects an amount + method, calls
/// `POST /partner-deposit/initiate`, then pushes the HyperPay WebView.
///
/// Resolves `true` when a deposit succeeded (so the caller refreshes the
/// wallet). The hold/credit happens server-side on the callback, so a success
/// means the balance is already updated.
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
  final _amount = TextEditingController();
  String _method = 'card'; // card | apple_pay
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;
  bool get _canSubmit => !_busy && _amountValue > 0;

  /// Idempotency key for this deposit attempt.
  ///
  /// It must be STABLE so that retrying after a network drop re-opens the same
  /// checkout instead of starting a second one (it used to be minted inline at
  /// the request site, so every retry looked like a new intent and could open a
  /// second pending deposit + a second HyperPay checkout).
  ///
  /// But it must also track the AMOUNT and METHOD: the server's dedup branch
  /// returns the EXISTING deposit, old amount and all. Reusing one key across an
  /// amount change would silently charge the previous amount. So the key is
  /// re-minted whenever either changes — same amount+method = same intent =
  /// dedupe; different amount = genuinely new intent.
  String _clientRequestId = newRequestId('deposit');
  double? _keyAmount;
  String? _keyMethod;

  String _requestIdFor(double amount, String method) {
    if (_keyAmount != amount || _keyMethod != method) {
      _clientRequestId = newRequestId('deposit');
      _keyAmount = amount;
      _keyMethod = method;
    }
    return _clientRequestId;
  }

  Future<void> _start() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Stable across retries: if the network drops after the server created
      // the checkout, resending the SAME id re-opens that one (deduped) rather
      // than starting a second.
      final init = await ref
          .read(partnerRepositoryProvider)
          .initiateDeposit(
            amount: _amountValue,
            paymentMethod: _method,
            clientRequestId: _requestIdFor(_amountValue, _method),
          );
      if (!mounted) return;

      // Hand off to the WebView; it resolves with the outcome.
      final outcome = await Navigator.of(context).push<DepositOutcome>(
        MaterialPageRoute(
          builder: (_) => DepositCheckoutScreen(init: init),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) return;

      if (outcome == null || outcome.isCancelled) {
        // Nothing charged; let them adjust and try again.
        setState(() => _busy = false);
        return;
      }
      if (outcome.isSuccess) {
        AppToast.success(
          outcome.pendingCredit
              ? 'Paid — your balance will update shortly.'
              : 'Deposit added to your wallet.',
        );
        Navigator.of(context).pop(true);
      } else if (outcome.status == 'pending') {
        AppToast.success('Payment is processing — check back shortly.');
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = outcome.error.isEmpty
              ? 'Payment failed. No money was taken.'
              : outcome.error;
        });
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'WALLET_FROZEN'
            ? 'Your wallet is frozen. Contact support.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not start the payment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The body must SCROLL. This was a fixed Column, so opening the keyboard
    // shrank the available height (viewInsets) while the content stayed the same
    // size — a guaranteed bottom overflow. Pin the header, scroll the rest, and
    // cap the sheet, exactly as the withdraw sheet already does.
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
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
                    child: Text(
                      'Add funds',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.black45,
                    ),
                    onPressed: _busy
                        ? null
                        : () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Amount (AED)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _amount,
                      enabled: !_busy,
                      autofocus: true,
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
                    const Text(
                      'Pay with',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _methodTile(
                            'card',
                            'Card',
                            Icons.credit_card_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _methodTile(
                            'apple_pay',
                            'Apple Pay',
                            Icons.apple_rounded,
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: AppColors.rose,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _canSubmit ? _start : null,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.lock_rounded, size: 16),
                        label: Text(
                          _busy ? 'Starting…' : 'Continue to payment',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Payments are processed securely by HyperPay.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
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
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: on ? AppColors.brand700 : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
