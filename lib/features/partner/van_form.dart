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
  late final TextEditingController _parking;
  String _status = 'active';
  int? _zoneId;
  int? _driverId;
  bool _autoAssign = true;
  bool _busy = false;
  late Future<List<Zone>> _zones;
  late Future<List<Worker>> _drivers;

  bool get _isEdit => widget.van != null;

  @override
  void initState() {
    super.initState();
    final v = widget.van;
    _name = TextEditingController(text: v?.name ?? '');
    _plate = TextEditingController(text: v?.plate ?? '');
    _code = TextEditingController(text: v?.code ?? '');
    _seats = TextEditingController(text: v != null ? '${v.seats}' : '');
    _parking = TextEditingController(text: v?.parkingAddress ?? '');
    _status = v?.status.isNotEmpty == true ? v!.status : 'active';
    _zoneId = v?.homeZoneId;
    _driverId = v?.driverWorkerId;
    _autoAssign = v?.acceptAutoAssign ?? true;
    _zones = ref.read(partnerRepositoryProvider).zones();
    _drivers = ref
        .read(partnerRepositoryProvider)
        .workers()
        .then((all) => all.where((w) => w.roles.contains('driver')).toList())
        .catchError((_) => <Worker>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    _plate.dispose();
    _code.dispose();
    _seats.dispose();
    _parking.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_zoneId == null) {
      AppToast.error('Please choose a primary zone.');
      return;
    }
    setState(() => _busy = true);
    final partnerId = ref.read(authControllerProvider).user?.partnerId;
    final body = {
      'name': _name.text.trim(),
      'plate': _plate.text.trim(),
      if (_code.text.trim().isNotEmpty) 'code': _code.text.trim(),
      'seats': int.tryParse(_seats.text.trim()) ?? 1,
      'homeZoneId': _zoneId,
      'driverWorkerId': _driverId,
      'status': _status,
      'acceptAutoAssign': _autoAssign,
      if (_parking.text.trim().isNotEmpty)
        'parkingAddress': _parking.text.trim(),
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
            _label('Primary zone *'),
            FutureBuilder<List<Zone>>(
              future: _zones,
              builder: (context, snap) {
                final zones = snap.data ?? const <Zone>[];
                final ids = zones.map((z) => z.id).toSet();
                // Keep the selected value valid for the dropdown.
                if (_zoneId == null || !ids.contains(_zoneId)) {
                  _zoneId = zones.isNotEmpty ? zones.first.id : null;
                }
                return DropdownButtonFormField<int>(
                  initialValue: _zoneId,
                  isExpanded: true,
                  hint: const Text('Select a zone'),
                  items: zones
                      .map((z) => DropdownMenuItem(
                          value: z.id,
                          child:
                              Text(z.label, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() => _zoneId = v),
                );
              },
            ),
            const SizedBox(height: 14),
            _label('Driver'),
            FutureBuilder<List<Worker>>(
              future: _drivers,
              builder: (context, snap) {
                final drivers = snap.data ?? const <Worker>[];
                final items = <DropdownMenuItem<int?>>[
                  const DropdownMenuItem<int?>(
                      value: null, child: Text('No driver')),
                  ...drivers.map((d) => DropdownMenuItem<int?>(
                      value: d.id,
                      child: Text(d.name.isEmpty ? 'Driver' : d.name,
                          overflow: TextOverflow.ellipsis))),
                ];
                // Current driver may not be in the active-driver list — keep it
                // selectable so the dropdown doesn't assert.
                if (_driverId != null &&
                    !drivers.any((d) => d.id == _driverId)) {
                  final name = widget.van?.driverName ?? '';
                  items.add(DropdownMenuItem<int?>(
                      value: _driverId,
                      child: Text(name.isEmpty ? 'Current driver' : name,
                          overflow: TextOverflow.ellipsis)));
                }
                return DropdownButtonFormField<int?>(
                  initialValue: _driverId,
                  isExpanded: true,
                  hint: const Text('No driver'),
                  items: items,
                  onChanged: (v) => setState(() => _driverId = v),
                );
              },
            ),
            const SizedBox(height: 14),
            _label('Status'),
            DropdownButtonFormField<String>(
              initialValue: _status,
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Active')),
                DropdownMenuItem(
                    value: 'not_working', child: Text('Not working')),
                DropdownMenuItem(
                    value: 'maintenance', child: Text('Maintenance')),
                DropdownMenuItem(value: 'retired', child: Text('Retired')),
              ],
              onChanged: (v) => setState(() => _status = v ?? 'active'),
            ),
            const SizedBox(height: 14),
            _field('Parking address', _parking),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoAssign,
              activeThumbColor: AppColors.brand600,
              title: const Text('Auto-assign bookings',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  _autoAssign
                      ? 'Van can be auto-dispatched'
                      : 'Active but skips auto-dispatch',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onChanged: (v) => setState(() => _autoAssign = v),
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

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      );

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
