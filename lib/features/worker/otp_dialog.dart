import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

/// 6-digit OTP entry. Returns the entered code on success, or null if cancelled.
///
/// When [onSubmit] is provided the dialog VALIDATES the code itself: on tap it
/// calls onSubmit(code) which returns an error message (or null on success). On
/// error the dialog stays OPEN and shows the message so the user can retry; it
/// only closes (returning the code) once onSubmit succeeds. Without onSubmit it
/// just returns the code on tap (legacy behaviour).
Future<String?> showOtpDialog(
  BuildContext context, {
  required String bookingRef,
  String? customerName,
  Future<String?> Function(String code)? onSubmit,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _OtpDialog(
        bookingRef: bookingRef,
        customerName: customerName,
        onSubmit: onSubmit),
  );
}

class _OtpDialog extends StatefulWidget {
  final String bookingRef;
  final String? customerName;
  final Future<String?> Function(String code)? onSubmit;
  const _OtpDialog(
      {required this.bookingRef, this.customerName, this.onSubmit});
  @override
  State<_OtpDialog> createState() => _OtpDialogState();
}

class _OtpDialogState extends State<_OtpDialog> {
  final _controllers = List.generate(6, (_) => TextEditingController());
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    // The focus node handles the key event so we can detect backspace on an
    // already-empty box (onChanged never fires when the text doesn't change).
    _nodes =
        List.generate(6, (i) => FocusNode(onKeyEvent: (_, e) => _onKey(i, e)));
    for (var i = 0; i < 6; i++) {
      _nodes[i].addListener(() => _selectOnFocus(i));
    }
  }

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

  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final code = _code;
    if (widget.onSubmit == null) {
      Navigator.pop(context, code);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.onSubmit!(code);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context, code); // verified → close with the code
    } else {
      // Wrong code: keep the dialog OPEN, show the error, reset for a retry.
      setState(() {
        _submitting = false;
        _error = err;
        for (final c in _controllers) {
          c.clear();
        }
      });
      _nodes[0].requestFocus();
    }
  }

  // Select a box's digit when it gains focus, so the next keystroke *replaces*
  // it instead of appending a second character (which used to be misread as a
  // paste and scramble the boxes).
  void _selectOnFocus(int i) {
    if (!_nodes[i].hasFocus) return;
    _controllers[i].selection = TextSelection(
        baseOffset: 0, extentOffset: _controllers[i].text.length);
  }

  // Backspace on an *empty* box: clear the previous box and step back to it.
  // TextField.onChanged doesn't fire here (no text change), so we must catch
  // the raw key — this is what makes "tab forward, then delete" move back.
  KeyEventResult _onKey(int i, KeyEvent e) {
    if (e is KeyDownEvent &&
        e.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[i].text.isEmpty &&
        i > 0) {
      _controllers[i - 1].clear();
      _nodes[i - 1].requestFocus();
      setState(() {});
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onChanged(int i, String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    // 3+ chars can only come from a paste — typing one at a time never does.
    // Spread the pasted code across the boxes from the first.
    if (digits.length >= 3) {
      for (var k = 0; k < 6; k++) {
        _controllers[k].text = k < digits.length ? digits[k] : '';
      }
      setState(() {});
      if (digits.length >= 6) {
        FocusScope.of(context).unfocus();
      } else {
        _nodes[digits.length.clamp(0, 5)].requestFocus();
      }
      return;
    }
    // A box already holds a digit and another was typed into it — e.g. all six
    // boxes are filled and the user keeps typing on the last box. Keep the
    // EXISTING digit and ignore the extra keystroke (to change it, delete
    // first). This stops a 7th keypress from overwriting the last digit.
    // (Re-tapping a box to edit it still works: focus change selects the digit,
    // so typing replaces it as a single char and never hits this branch.)
    if (digits.length == 2) {
      _controllers[i].text = digits.substring(0, 1);
      _controllers[i].selection = const TextSelection.collapsed(offset: 1);
      setState(() {});
      return;
    }
    if (digits.isNotEmpty) {
      if (i < 5) _nodes[i + 1].requestFocus(); // typed a digit → advance
    } else if (i > 0) {
      _nodes[i - 1].requestFocus(); // deleted a digit → step back
    }
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
          if (_error != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: AppColors.rose),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(
                          color: AppColors.rose,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: (filled && !_submitting) ? _submit : null,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: Colors.white))
              : const Text('Verify & start'),
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
