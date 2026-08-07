import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Door-cash collection with extras — parity with the web portal's
/// CashCollectionPanel / CashExtrasPanel (2026-08-06).
///
/// The flow is two steps:
///   1. Confirm the amount actually taken. Default is the full amount due;
///      the partner can record less (partial) or more (extra).
///   2. If more was taken, the backend parks the surplus as a pending cash
///      extra and we immediately ask where it should go — tip, customer
///      wallet, or a split — with cancel as the escape hatch.
///
/// Both repositories expose the same three calls, so they are passed in as
/// [CashCollectApi] rather than coupling this widget to either one.
class CashCollectApi {
  const CashCollectApi({
    required this.collect,
    required this.allocate,
    required this.cancel,
  });

  final Future<CashCollectResult> Function(
    int bookingId, {
    String? notes,
    double? collectedAmount,
  }) collect;

  final Future<void> Function(
    int bookingId,
    String pendingId,
    CashExtraDestination destination, {
    double? tipAmount,
    double? walletAmount,
  }) allocate;

  final Future<void> Function(int bookingId, String pendingId) cancel;
}

/// Runs the whole flow. Returns true when the cash was recorded (regardless
/// of how any extra was resolved), false if the partner backed out.
Future<bool> runCashCollectFlow(
  BuildContext context, {
  required CashCollectApi api,
  required int bookingId,
  required double cashDue,
  required bool hasAgent,
}) async {
  final amount = await _askAmount(context, cashDue: cashDue);
  if (amount == null) return false;
  if (!context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  CashCollectResult result;
  try {
    result = await api.collect(
      bookingId,
      // Only send the amount when it differs from the due, so an untouched
      // confirmation keeps the pre-cash-extras behaviour on the server.
      collectedAmount: _sameMoney(amount, cashDue) ? null : amount,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(
      content: Text(_clean(e)),
      backgroundColor: Colors.red.shade600,
    ));
    return false;
  }

  if (result.needsAllocation && context.mounted) {
    await _resolveExtra(
      context,
      api: api,
      bookingId: bookingId,
      extra: result.pendingCashExtra!,
      hasAgent: hasAgent,
    );
  } else if (result.message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(result.message)));
  }
  return true;
}

bool _sameMoney(double a, double b) =>
    a.toStringAsFixed(2) == b.toStringAsFixed(2);

String _clean(Object e) => e.toString().replaceFirst('Exception: ', '');

String _aed(double v) => 'AED ${v.toStringAsFixed(2)}';

// ─── Step 1: how much was actually taken ────────────────────────────────────

Future<double?> _askAmount(BuildContext context,
    {required double cashDue}) async {
  final controller =
      TextEditingController(text: cashDue.toStringAsFixed(2));
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AmountSheet(controller: controller, cashDue: cashDue),
    ),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.controller, required this.cashDue});

  final TextEditingController controller;
  final double cashDue;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  String? _error;

  double? get _value => double.tryParse(widget.controller.text.trim());

  /// Difference vs the amount due: negative = partial, positive = extra.
  double get _delta => (_value ?? widget.cashDue) - widget.cashDue;

  @override
  Widget build(BuildContext context) {
    final v = _value;
    final short = v != null && _delta < -0.004;
    final over = v != null && _delta > 0.004;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.payments_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Collect cash',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            Text('Amount due ${_aed(widget.cashDue)}',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextField(
              controller: widget.controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Amount taken (AED)',
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            if (short)
              _Banner(
                icon: Icons.info_outline,
                color: Colors.orange.shade800,
                text:
                    'Partial — ${_aed(-_delta)} will stay outstanding on this booking.',
              ),
            if (over)
              _Banner(
                icon: Icons.savings_outlined,
                color: Colors.teal.shade700,
                text:
                    'Extra ${_aed(_delta)} — you will choose where it goes next.',
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final val = _value;
                  if (val == null) {
                    setState(() => _error = 'Enter an amount');
                    return;
                  }
                  if (val <= 0) {
                    setState(() => _error = 'Must be greater than 0');
                    return;
                  }
                  Navigator.pop(context, val);
                },
                child: const Text('Confirm',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─── Step 2: where does the surplus go ──────────────────────────────────────

Future<void> _resolveExtra(
  BuildContext context, {
  required CashCollectApi api,
  required int bookingId,
  required PendingCashExtra extra,
  required bool hasAgent,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _AllocateSheet(
        api: api,
        bookingId: bookingId,
        extra: extra,
        hasAgent: hasAgent,
      ),
    ),
  );
}

class _AllocateSheet extends StatefulWidget {
  const _AllocateSheet({
    required this.api,
    required this.bookingId,
    required this.extra,
    required this.hasAgent,
  });

  final CashCollectApi api;
  final int bookingId;
  final PendingCashExtra extra;
  final bool hasAgent;

  @override
  State<_AllocateSheet> createState() => _AllocateSheetState();
}

class _AllocateSheetState extends State<_AllocateSheet> {
  late CashExtraDestination _dest =
      widget.hasAgent ? CashExtraDestination.tip : CashExtraDestination.wallet;
  late final TextEditingController _tip = TextEditingController(text: '0.00');
  bool _busy = false;
  String? _error;

  double get _amount => widget.extra.amount;
  double get _tipValue => double.tryParse(_tip.text.trim()) ?? 0;
  double get _walletValue =>
      double.parse((_amount - _tipValue).toStringAsFixed(2));

  @override
  void dispose() {
    _tip.dispose();
    super.dispose();
  }

  /// Tip and split need an agent to pay the tip to; the backend rejects them
  /// with TIP_REQUIRES_AGENT, so unassigned bookings only see "wallet".
  List<CashExtraDestination> get _options => widget.hasAgent
      ? CashExtraDestination.values
      : [CashExtraDestination.wallet];

  Future<void> _submit() async {
    if (_dest == CashExtraDestination.split) {
      if (_tipValue <= 0 || _tipValue >= _amount) {
        setState(() => _error =
            'Tip must be between 0 and ${_amount.toStringAsFixed(2)}');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.allocate(
        widget.bookingId,
        widget.extra.id,
        _dest,
        tipAmount: _dest == CashExtraDestination.split ? _tipValue : null,
        walletAmount:
            _dest == CashExtraDestination.split ? _walletValue : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _clean(e);
        });
      }
    }
  }

  Future<void> _cancelExtra() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.cancel(widget.bookingId, widget.extra.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _clean(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.savings_outlined,
                  size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Extra ${_aed(_amount)}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ]),
            const SizedBox(height: 2),
            Text(
              widget.hasAgent
                  ? 'Choose where this goes. Tips are paid to the assigned agent.'
                  : 'No agent is assigned, so this can only go to the customer wallet.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 10),
            for (final d in _options)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _dest == d
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: _dest == d ? Colors.teal.shade700 : Colors.grey,
                ),
                title: Text(d.label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            _dest == d ? FontWeight.w700 : FontWeight.w500)),
                onTap: _busy ? null : () => setState(() => _dest = d),
              ),
            if (_dest == CashExtraDestination.split) ...[
              const SizedBox(height: 4),
              TextField(
                controller: _tip,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Tip (AED)',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 6),
              // The split must total the pending amount exactly, so the
              // wallet leg is derived rather than typed.
              Text('Wallet gets ${_aed(_walletValue)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700])),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700)),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2))
                    : const Text('Allocate',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _cancelExtra,
              child: Text('Money handed back — cancel extra',
                  style: TextStyle(color: Colors.red.shade600, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
