import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// 6-digit OTP entry. Returns the code, or null if cancelled.
Future<String?> showOtpDialog(BuildContext context,
    {required String bookingRef, String? customerName}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _OtpDialog(bookingRef: bookingRef, customerName: customerName),
  );
}

class _OtpDialog extends StatefulWidget {
  final String bookingRef;
  final String? customerName;
  const _OtpDialog({required this.bookingRef, this.customerName});
  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  final _nodes = List.generate(6, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      // paste
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (var k = 0; k < 6; k++) {
        _controllers[k].text = k < digits.length ? digits[k] : '';
      }
      setState(() {});
      if (digits.length >= 6) FocusScope.of(context).unfocus();
      return;
    }
    if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
    if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final filled = _code.length == 6;
    return AlertDialog(
      title: const Text('Enter start code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Booking # + customer block — mirrors the web StartOtpModal so the
          // worker can confirm which job they're starting.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Booking', widget.bookingRef),
                if (widget.customerName != null &&
                    widget.customerName!.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _infoRow('Customer', widget.customerName!),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Ask the customer for the 6-digit start code shown in their app.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // FittedBox scales the row down so 6 boxes never overflow a narrow
          // dialog on any device.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: i == 0 ? 6 : 1,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800),
                      onChanged: (v) => _onChanged(i, v),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: filled ? () => Navigator.pop(context, _code) : null,
          child: const Text('Verify & start'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) => Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13.5)),
          ),
        ],
      );
}
