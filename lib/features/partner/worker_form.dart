import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/searchable_picker.dart';
import 'availability_editor.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class WorkerForm extends ConsumerStatefulWidget {
  final Worker? worker;
  const WorkerForm({super.key, this.worker});
  @override
  ConsumerState<WorkerForm> createState() => _WorkerFormState();
}

class _WorkerFormState extends ConsumerState<WorkerForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _address;
  String _phone = '+971';
  String _role = 'crew';
  String _status = 'active';
  int? _zoneId;
  bool _autoAssign = true;
  bool _busy = false;
  bool _dirty = false; // enables Save only after a change/entry
  late Future<List<Zone>> _zones;

  bool get _isEdit => widget.worker != null;

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  @override
  void initState() {
    super.initState();
    final w = widget.worker;
    _first = TextEditingController(text: w?.firstName ?? '');
    _last = TextEditingController(text: w?.lastName ?? '');
    _phone = (w?.phone.isNotEmpty ?? false) ? w!.phone : '+971';
    _email = TextEditingController(text: w?.email ?? '');
    _address = TextEditingController(text: w?.homeAddress ?? '');
    _role = (w?.roles.contains('driver') ?? false) ? 'driver' : 'crew';
    _status = w?.status.isNotEmpty == true ? w!.status : 'active';
    _autoAssign = w?.acceptAutoAssign ?? true;
    _zoneId = w?.primaryZoneId;
    _zones = ref.read(partnerRepositoryProvider).zones();
    // Track edits to enable Save (listeners added AFTER initial text is set).
    for (final c in [_first, _last, _email, _address]) {
      c.addListener(_markDirty);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  // Auto-assign saves immediately in edit mode (independent of the Save button).
  Future<void> _saveAutoAssign(bool v) async {
    setState(() => _autoAssign = v);
    if (!_isEdit) return; // create: persisted with the new worker
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateWorker(widget.worker!.id, {'acceptAutoAssign': v});
    } on ApiException catch (e) {
      if (mounted) setState(() => _autoAssign = !v);
      AppToast.error(e.message);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_zoneId == null) {
      AppToast.error('Please choose a primary zone.');
      return;
    }
    if (_phone.replaceAll(RegExp(r'\D'), '').length < 9) {
      AppToast.error('Enter a valid phone number.');
      return;
    }
    setState(() => _busy = true);
    final partnerId = ref.read(authControllerProvider).user?.partnerId;
    final body = {
      'firstName': _first.text.trim(),
      if (_last.text.trim().isNotEmpty) 'lastName': _last.text.trim(),
      'phone': _phone.trim(),
      'email': _email.text.trim(),
      'roles': [_role],
      'primaryZoneId': _zoneId,
      'status': _status,
      'acceptAutoAssign': _autoAssign,
      if (_address.text.trim().isNotEmpty) 'homeAddress': _address.text.trim(),
      if (partnerId != null) 'partnerId': partnerId,
    };
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (_isEdit) {
        await repo.updateWorker(widget.worker!.id, body);
      } else {
        await repo.createWorker(body);
      }
      AppToast.success(_isEdit ? 'Worker updated' : 'Worker added');
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
      appBar: AppBar(title: Text(_isEdit ? 'Edit worker' : 'Add worker')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('First name *', _first,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            _field('Last name', _last),
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: PhoneField(
                label: 'Phone *',
                initial: _phone,
                onChanged: (v) {
                  _phone = v;
                  _markDirty();
                },
              ),
            ),
            _field('Email *', _email,
                keyboard: TextInputType.emailAddress, validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Required';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s)) {
                return 'Invalid email';
              }
              return null;
            }),
            _label('Role'),
            Row(
              children: [
                _roleChip('crew', 'Crew'),
                const SizedBox(width: 8),
                _roleChip('driver', 'Driver'),
              ],
            ),
            const SizedBox(height: 14),
            _label('Primary zone'),
            FutureBuilder<List<Zone>>(
              future: _zones,
              builder: (context, snap) {
                final zones = snap.data ?? const <Zone>[];
                final ids = zones.map((z) => z.id).toSet();
                if (_zoneId == null || !ids.contains(_zoneId)) {
                  _zoneId = zones.isNotEmpty ? zones.first.id : null;
                }
                final sel = zones.where((z) => z.id == _zoneId).toList();
                return PickerField(
                  value: sel.isNotEmpty ? sel.first.label : '',
                  hint: 'Select a zone',
                  onTap: () async {
                    final picked = await showSearchablePicker<Zone>(
                      context: context,
                      title: 'Primary zone',
                      items: zones,
                      labelOf: (z) => z.label,
                      selected: sel.isNotEmpty ? sel.first : null,
                      equals: (a, b) => a.id == b.id,
                    );
                    if (picked != null) {
                      setState(() => _zoneId = picked.id);
                      _markDirty();
                    }
                  },
                );
              },
            ),
            const SizedBox(height: 14),
            _field('Home address', _address),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoAssign,
              activeThumbColor: AppColors.brand600,
              title: const Text('Auto-assign new bookings',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  _autoAssign
                      ? 'Can be auto-dispatched to matching jobs'
                      : 'Only manual assignments',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              onChanged: _saveAutoAssign,
            ),
            if (_isEdit) ...[
              const SizedBox(height: 10),
              _label('Status'),
              DropdownButtonFormField<String>(
                initialValue: _status,
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                      value: 'not_working', child: Text('Not working')),
                  DropdownMenuItem(value: 'on_leave', child: Text('On leave')),
                  DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                ],
                onChanged: (v) {
                  setState(() => _status = v ?? 'active');
                  _markDirty();
                },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AvailabilityEditor(
                        ownerType: 'worker',
                        ownerId: widget.worker!.id,
                        title: '${widget.worker!.name} · hours'))),
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
      // Sticky save bar — always visible (no need to scroll to the bottom).
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
                : Text(_isEdit ? 'Save changes' : 'Add worker'),
          ),
        ),
      ),
    );
  }

  Widget _roleChip(String value, String label) {
    final on = _role == value;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _role = value);
          _markDirty();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.brand600 : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AppColors.brand600 : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700)),
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
          {String? Function(String?)? validator, TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          validator: validator,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
