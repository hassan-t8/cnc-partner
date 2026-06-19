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
          Text(
            'Ask ${widget.customerName ?? 'the customer'} for the 6-digit code '
            'for ${widget.bookingRef}.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (i) {
              final on = _controllers[i].text.isNotEmpty;
              return SizedBox(
                width: 46,
                height: 56,
                child: TextField(
                  controller: _controllers[i],
                  focusNode: _nodes[i],
                  autofocus: i == 0,
                  textAlign: TextAlign.center,
                  textAlignVertical: TextAlignVertical.center,
                  keyboardType: TextInputType.number,
                  maxLength: i == 0 ? 6 : 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, height: 1.0),
                  decoration: InputDecoration(
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: EdgeInsets.zero,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: on ? AppColors.brand600 : AppColors.border,
                          width: on ? 1.6 : 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: AppColors.brand600, width: 1.8),
                    ),
                  ),
                  onChanged: (v) => _onChanged(i, v),
                ),
              );
            }),
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
}
