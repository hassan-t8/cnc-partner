import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/searchable_picker.dart';
import 'availability_editor.dart';
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
  String _emirate = ''; // tracks emirate when no area is picked yet
  int? _driverId;
  List<int> _serviceZoneIds = const [];
  bool _autoAssign = true;
  bool _busy = false;
  bool _dirty = false;
  late Future<List<Zone>> _zones;
  late Future<List<Worker>> _drivers;

  bool get _isEdit => widget.van != null;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

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
    _serviceZoneIds = List<int>.from(v?.serviceZoneIds ?? const []);
    _autoAssign = v?.acceptAutoAssign ?? true;
    for (final c in [_name, _plate, _code, _seats, _parking]) {
      c.addListener(_markDirty);
    }
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
      'serviceZoneIds':
          _serviceZoneIds.where((z) => z != _zoneId).toList(),
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
      appBar: MainAppBar(_isEdit ? 'Edit van' : 'Add van'),
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
            // Two-step (Emirate → Area), matching the web's ZonePicker.
            FutureBuilder<List<Zone>>(
              future: _zones,
              builder: (context, snap) {
                final zones = snap.data ?? const <Zone>[];
                final emirates = <String>[];
                for (final z in zones) {
                  if (z.emirate.isNotEmpty && !emirates.contains(z.emirate)) {
                    emirates.add(z.emirate);
                  }
                }
                final sel = zones.where((z) => z.id == _zoneId).toList();
                final curEmirate =
                    sel.isNotEmpty ? sel.first.emirate : _emirate;
                final areas =
                    zones.where((z) => z.emirate == curEmirate).toList();
                return Row(
                  children: [
                    Expanded(
                      child: PickerField(
                        value: curEmirate,
                        hint: 'Emirate',
                        onTap: () async {
                          final picked = await showSearchablePicker<String>(
                            context: context,
                            title: 'Emirate',
                            items: emirates,
                            labelOf: (e) => e,
                            selected: curEmirate.isEmpty ? null : curEmirate,
                          );
                          if (picked != null) {
                            setState(() {
                              _emirate = picked;
                              _zoneId = null;
                            });
                            _markDirty();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PickerField(
                        value: sel.isNotEmpty ? sel.first.name : '',
                        hint: '— Select area —',
                        onTap: () async {
                          if (areas.isEmpty) return;
                          final picked = await showSearchablePicker<Zone>(
                            context: context,
                            title: 'Area',
                            items: areas,
                            labelOf: (z) => z.name,
                            selected: sel.isNotEmpty ? sel.first : null,
                            equals: (a, b) => a.id == b.id,
                          );
                          if (picked != null) {
                            setState(() => _zoneId = picked.id);
                            _markDirty();
                          }
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            _hint('Default operating zone — drives dispatch + scheduling.'),
            const SizedBox(height: 14),
            _label('Additional service zones'),
            FutureBuilder<List<Zone>>(
              future: _zones,
              builder: (context, snap) {
                final zones = snap.data ?? const <Zone>[];
                final selectable =
                    zones.where((z) => z.id != _zoneId).toList();
                final sel = zones
                    .where((z) => _serviceZoneIds.contains(z.id) && z.id != _zoneId)
                    .toList();
                final value = sel.isEmpty
                    ? ''
                    : sel.map((z) => z.label).join(', ');
                return PickerField(
                  value: value,
                  hint: 'None (primary zone only)',
                  onTap: () async {
                    final picked = await showMultiSearchablePicker<Zone>(
                      context: context,
                      title: 'Additional service zones',
                      items: selectable,
                      labelOf: (z) => z.label,
                      keyOf: (z) => z.id,
                      selected: sel,
                    );
                    if (picked != null) {
                      setState(() =>
                          _serviceZoneIds = picked.map((z) => z.id).toList());
                      _markDirty();
                    }
                  },
                );
              },
            ),
            _hint('Extra zones to serve beyond the primary zone. Primary is auto-included and locked here.'),
            const SizedBox(height: 14),
            _label('Driver'),
            FutureBuilder<List<Worker>>(
              future: _drivers,
              builder: (context, snap) {
                final drivers = snap.data ?? const <Worker>[];
                const noDriver = Worker(id: -1); // sentinel = "No driver"
                final options = <Worker>[noDriver, ...drivers];
                Worker? current;
                if (_driverId != null) {
                  final m = drivers.where((d) => d.id == _driverId);
                  current = m.isNotEmpty ? m.first : null;
                }
                final label = _driverId == null
                    ? 'No driver'
                    : (current?.name.isNotEmpty == true
                        ? current!.name
                        : (widget.van?.driverName ?? 'Current driver'));
                return PickerField(
                  value: label,
                  hint: 'No driver',
                  onTap: () async {
                    final picked = await showSearchablePicker<Worker>(
                      context: context,
                      title: 'Driver',
                      items: options,
                      labelOf: (w) => w.id == -1
                          ? 'No driver'
                          : (w.name.isEmpty ? 'Driver' : w.name),
                      selected: _driverId == null ? noDriver : current,
                      equals: (a, b) => a.id == b.id,
                    );
                    if (picked == null) return; // dismissed
                    setState(
                        () => _driverId = picked.id == -1 ? null : picked.id);
                    _markDirty();
                  },
                );
              },
            ),
            _hint('Drivers already attached to another van are shown but not selectable until that pairing is removed.'),
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
              onChanged: (v) {
                setState(() => _status = v ?? 'active');
                _markDirty();
              },
            ),
            const SizedBox(height: 14),
            _field('Parking address', _parking),
            _hint('Where the van overnights and starts the morning shift from.'),
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
              onChanged: _saveAutoAssign,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AvailabilityEditor(
                        ownerType: 'van',
                        ownerId: widget.van!.id,
                        title: '${widget.van!.name} · hours'))),
                icon: const Icon(Icons.schedule, size: 18),
                label: const Text('Working hours'),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46)),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: (_busy || !_dirty) ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white))
                : Text(_isEdit ? 'Save changes' : 'Add van'),
          ),
        ),
      ),
    );
  }

  // Auto-assign saves immediately in edit mode (independent of Save).
  Future<void> _saveAutoAssign(bool v) async {
    setState(() => _autoAssign = v);
    if (!_isEdit) return;
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateVan(widget.van!.id, {'acceptAutoAssign': v});
    } on ApiException catch (e) {
      if (mounted) setState(() => _autoAssign = !v);
      AppToast.error(e.message);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t,
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
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
