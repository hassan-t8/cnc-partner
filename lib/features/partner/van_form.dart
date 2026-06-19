import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class VanForm extends ConsumerStatefulWidget {
  final Van? van;
  const VanForm({super.key, this.van});
  @override
  ConsumerState<VanForm> createState() => _VanFormState();
}

class _VanFormState extends ConsumerState<VanForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _plate;
  late final TextEditingController _code;
  late final TextEditingController _seats;
  String _status = 'active';
  bool _busy = false;

  bool get _isEdit => widget.van != null;

  @override
  void initState() {
    super.initState();
    final v = widget.van;
    _name = TextEditingController(text: v?.name ?? '');
    _plate = TextEditingController(text: v?.plate ?? '');
    _code = TextEditingController(text: v?.code ?? '');
    _seats = TextEditingController(text: v != null ? '${v.seats}' : '');
    _status = v?.status.isNotEmpty == true ? v!.status : 'active';
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _code.dispose();
    _seats.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final partnerId = ref.read(authControllerProvider).user?.partnerId;
    final body = {
      'name': _name.text.trim(),
      'plate': _plate.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      'seats': int.tryParse(_seats.text.trim()) ?? 1,
      'status': _status,
      if (partnerId != null) 'partnerId': partnerId,
    };
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (_isEdit) {
        await repo.updateVan(widget.van!.id, body);
      } else {
        await repo.createVan(body);
      }
      AppToast.success(_isEdit ? 'Van updated' : 'Van added');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit van' : 'Add van')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('Name *', _name,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            _field('Plate *', _plate,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            _field('Code', _code),
            _field('Seats *', _seats,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null || n < 1 || n > 30) return '1–30';
                  return null;
                }),
            const SizedBox(height: 4),
            Text('Status',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(
                    value: 'maintenance', child: Text('Maintenance')),
                DropdownMenuItem(value: 'retired', child: Text('Retired')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white))
                    : Text(_isEdit ? 'Save changes' : 'Add van'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl,
          {String? Function(String?)? validator,
          TextInputType? keyboard,
          List<TextInputFormatter>? formatters}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          inputFormatters: formatters,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
