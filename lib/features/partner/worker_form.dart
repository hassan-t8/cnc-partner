import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/location_picker_screen.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/searchable_picker.dart';
import 'partner_schedule_screen.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'worker_services_picker.dart';

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
  String _emirate = ''; // tracks emirate when no area is picked yet
  final Set<int> _workingDays = {}; // 0=Sun..6=Sat (create-only quick set)
  String _startTime = '09:00';
  String _endTime = '18:00';
  double? _homeLat;
  double? _homeLng;
  List<int> _serviceZoneIds = const []; // additional zones beyond primary
  List<int> _serviceBasePriceIds = const []; // services (crew) — anchor rows
  Map<int, List<int>> _serviceItemsByBp = {}; // basePriceId -> serviceItemIds
  int? _assignedVanId; // van (driver)
  bool _autoAssign = true;
  bool _busy = false;
  bool _dirty = false; // enables Save only after a change/entry
  late Future<List<Zone>> _zones;
  late Future<List<Van>> _vans;
  late Future<List<MyService>> _myServices;

  bool get _isEdit => widget.worker != null;

  int? _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v');

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
    _homeLat = w?.homeLat;
    _homeLng = w?.homeLng;
    final repo = ref.read(partnerRepositoryProvider);
    _zones = repo.zones();
    _vans = repo.vans().catchError((_) => <Van>[]);
    _myServices = repo.myServices().catchError((_) => <MyService>[]);
    // On edit, hydrate the additional zones, linked services, and assigned van.
    if (_isEdit) {
      repo.workerZones(w!.id).then((rows) {
        final secondary = rows
            .where((r) => r['isPrimary'] != true)
            .map((r) => _toInt(r['zoneId']))
            .whereType<int>()
            .where((z) => z != _zoneId)
            .toList();
        if (mounted) setState(() => _serviceZoneIds = secondary);
      }).catchError((_) {});
      repo.workerServicesLink(w.id).then((link) {
        if (mounted) {
          setState(() {
            _serviceBasePriceIds = link.basePriceIds;
            _serviceItemsByBp = {
              for (final e in link.itemsByBp.entries) e.key: [...e.value],
            };
          });
        }
      }).catchError((_) {});
      _vans.then((vans) {
        final mine = vans.where((v) => v.driverWorkerId == w.id).toList();
        if (mine.isNotEmpty && mounted) {
          setState(() => _assignedVanId = mine.first.id);
        }
      }).catchError((_) {});
    }
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
      if (_homeLat != null) 'homeLat': _homeLat,
      if (_homeLng != null) 'homeLng': _homeLng,
      if (partnerId != null) 'partnerId': partnerId,
    };
    try {
      final repo = ref.read(partnerRepositoryProvider);
      int? workerId;
      if (_isEdit) {
        await repo.updateWorker(widget.worker!.id, body);
        workerId = widget.worker!.id;
      } else {
        workerId = await repo.createWorker(body);
      }
      if (workerId != null) {
        await _syncRelations(repo, workerId);
      }
      AppToast.success(_isEdit ? 'Worker updated' : 'Worker added');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Persist the additional zones, linked services (crew) and van (driver)
  /// after the worker row itself is saved — these use dedicated endpoints.
  Future<void> _syncRelations(PartnerRepository repo, int workerId) async {
    // Zones — always send primary + the additional ones.
    final zoneIds = <int>{
      if (_zoneId != null) _zoneId!,
      ..._serviceZoneIds,
    }.toList();
    await repo.syncWorkerZones(workerId, zoneIds, _zoneId);

    if (_role == 'crew') {
      // Services only apply to crew; drivers don't deliver services.
      await repo.syncWorkerServices(workerId, _serviceBasePriceIds,
          itemsByBp: _serviceItemsByBp);
    } else if (_role == 'driver') {
      // Re-point van assignment: clear any van this worker used to drive,
      // then attach the newly chosen one.
      final vans = await _vans;
      for (final v in vans) {
        if (v.driverWorkerId == workerId && v.id != _assignedVanId) {
          await repo.updateVan(v.id, {'driverWorkerId': null});
        }
      }
      if (_assignedVanId != null) {
        await repo.updateVan(_assignedVanId!, {'driverWorkerId': workerId});
      }
    }

    // Working hours quick-set on create — one availability rule per day.
    if (!_isEdit && _workingDays.isNotEmpty) {
      String pad(String t) =>
          RegExp(r'^\d{2}:\d{2}$').hasMatch(t) ? '$t:00' : t;
      for (final dow in _workingDays) {
        await repo.createAvailabilityRule({
          'ownerType': 'worker',
          'ownerId': workerId,
          'dayOfWeek': dow,
          'startTime': pad(_startTime),
          'endTime': pad(_endTime),
          'isActive': true,
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(_isEdit ? 'Edit worker' : 'Add worker'),
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
                    .where((z) =>
                        _serviceZoneIds.contains(z.id) && z.id != _zoneId)
                    .toList();
                return PickerField(
                  value: sel.isEmpty ? '' : sel.map((z) => z.label).join(', '),
                  hint: 'None (primary zone only)',
                  onTap: () async {
                    final picked = await showMultiSearchablePicker<Zone>(
                      context: context,
                      title: 'Additional service zones',
                      items: selectable,
                      labelOf: (z) => z.name,
                      keyOf: (z) => z.id,
                      groupOf: (z) => z.emirate.isEmpty ? 'Other' : z.emirate,
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
            if (_role == 'crew') ...[
              _label('Services attached'),
              FutureBuilder<List<MyService>>(
                future: _myServices,
                builder: (context, snap) {
                  final services = (snap.data ?? const <MyService>[])
                      .where((s) => s.basePriceId != null)
                      .toList();
                  final sel = services
                      .where((s) =>
                          _serviceBasePriceIds.contains(s.basePriceId) ||
                          (_serviceItemsByBp[s.basePriceId]?.isNotEmpty ??
                              false))
                      .toList();
                  final pickedCount = sel.length;
                  return PickerField(
                    value: sel.isEmpty
                        ? ''
                        : '$pickedCount linked · ${sel.map((s) => s.name).join(', ')}',
                    hint: 'None linked',
                    onTap: () async {
                      final result = await showWorkerServicesPicker(
                        context: context,
                        services: services,
                        selectedBasePriceIds: _serviceBasePriceIds,
                        itemsByBp: _serviceItemsByBp,
                      );
                      if (result != null) {
                        setState(() {
                          _serviceBasePriceIds = result.basePriceIds;
                          _serviceItemsByBp = result.itemsByBp;
                        });
                        _markDirty();
                      }
                    },
                  );
                },
              ),
              _hint(
                  'Tap to pick the services and items this worker handles. Prices shown per item.'),
              const SizedBox(height: 14),
            ],
            if (_role == 'driver') ...[
              _label('Assigned van'),
              FutureBuilder<List<Van>>(
                future: _vans,
                builder: (context, snap) {
                  final vans = snap.data ?? const <Van>[];
                  const noVan = Van(id: -1);
                  final options = <Van>[noVan, ...vans];
                  final cur = vans.where((v) => v.id == _assignedVanId);
                  final label = _assignedVanId == null
                      ? 'No van'
                      : (cur.isNotEmpty
                          ? '${cur.first.name} · ${cur.first.plate}'
                          : 'Current van');
                  return PickerField(
                    value: label,
                    hint: 'No van',
                    onTap: () async {
                      final picked = await showSearchablePicker<Van>(
                        context: context,
                        title: 'Assigned van',
                        items: options,
                        labelOf: (v) =>
                            v.id == -1 ? 'No van' : '${v.name} · ${v.plate}',
                        // A van already attached to another driver is shown but
                        // disabled (unselectable) until that pairing is removed.
                        enabledOf: (v) =>
                            v.id == -1 ||
                            v.driverWorkerId == null ||
                            v.driverWorkerId == widget.worker?.id,
                        disabledReasonOf: (v) => v.driverName.isNotEmpty
                            ? 'Assigned to ${v.driverName}'
                            : 'Assigned to another driver',
                        selected: _assignedVanId == null
                            ? noVan
                            : (cur.isNotEmpty ? cur.first : null),
                        equals: (a, b) => a.id == b.id,
                      );
                      if (picked == null) return;
                      setState(() =>
                          _assignedVanId = picked.id == -1 ? null : picked.id);
                      _markDirty();
                    },
                  );
                },
              ),
              const SizedBox(height: 14),
            ],
            _label('Home pickup location'),
            PickerField(
              value: _address.text,
              hint: 'Pick home location',
              onTap: () async {
                final r = await Navigator.of(context).push<PickedLocation>(
                  MaterialPageRoute(
                    builder: (_) => LocationPickerScreen(
                      title: 'Home pickup location',
                      initialLat: _homeLat,
                      initialLng: _homeLng,
                      initialAddress: _address.text,
                    ),
                  ),
                );
                if (r != null) {
                  setState(() {
                    _homeLat = r.lat;
                    _homeLng = r.lng;
                    _address.text = r.address;
                  });
                  _markDirty();
                }
              },
            ),
            _hint('Exact pickup point for the daily van route. Leave blank to use the primary zone centre as a fallback.'),
            const SizedBox(height: 8),
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
            // Working hours — inline quick-set on create (web parity); edit
            // mode uses the full availability editor below.
            if (!_isEdit) ...[
              const SizedBox(height: 10),
              _label('Working hours (optional)'),
              _daysWrap(),
              const SizedBox(height: 8),
              _presetsRow(),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _timeField('Start', _startTime, true)),
                  const SizedBox(width: 12),
                  Expanded(child: _timeField('End', _endTime, false)),
                ],
              ),
              _hint(
                  'Pick at least one day to define working hours, or leave empty — worker can set this later.'),
            ],
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
                    builder: (_) =>
                        PartnerScheduleScreen(initialWorker: widget.worker!))),
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: const Text('Schedule + leaves'),
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

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(t,
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
      );

  // ----- working-hours quick set (create) -----
  Widget _daysWrap() {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < 7; i++)
          GestureDetector(
            onTap: () {
              setState(() {
                _workingDays.contains(i)
                    ? _workingDays.remove(i)
                    : _workingDays.add(i);
              });
              _markDirty();
            },
            child: Container(
              width: 42,
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _workingDays.contains(i)
                    ? AppColors.brand600
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: _workingDays.contains(i)
                        ? AppColors.brand600
                        : AppColors.border),
              ),
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _workingDays.contains(i)
                          ? Colors.white
                          : AppColors.textMuted)),
            ),
          ),
      ],
    );
  }

  Widget _presetsRow() {
    void apply(Set<int> days) {
      setState(() {
        _workingDays
          ..clear()
          ..addAll(days);
      });
      _markDirty();
    }

    Widget chip(String label, VoidCallback onTap) => GestureDetector(
          onTap: onTap,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand600)),
        );
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip('Mon–Fri', () => apply({1, 2, 3, 4, 5})),
        chip('Mon–Sat', () => apply({1, 2, 3, 4, 5, 6})),
        chip('All week', () => apply({0, 1, 2, 3, 4, 5, 6})),
        chip('Clear', () => apply({})),
      ],
    );
  }

  Widget _timeField(String label, String value, bool isStart) => InkWell(
        onTap: () async {
          final parts = value.split(':');
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(
                hour: int.tryParse(parts.first) ?? 9,
                minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0),
          );
          if (picked != null) {
            final t =
                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
            setState(() => isStart ? _startTime = t : _endTime = t);
            _markDirty();
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          child: Row(
            children: [
              const Icon(Icons.schedule, size: 16),
              const SizedBox(width: 8),
              Text(value, style: const TextStyle(fontSize: 15)),
            ],
          ),
        ),
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
