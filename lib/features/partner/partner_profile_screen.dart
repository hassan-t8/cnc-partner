import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../core/profile/profile_image_provider.dart';
import '../../widgets/image_source_sheet.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/status_badge.dart';
import 'availability_editor.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerProfileScreen extends ConsumerStatefulWidget {
  final bool startInEdit;
  const PartnerProfileScreen({super.key, this.startInEdit = false});
  @override
  ConsumerState<PartnerProfileScreen> createState() =>
      _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  late Future<_Data> _future;
  late bool _editing = widget.startInEdit;
  bool _busy = false;
  bool _uploadingPhoto = false;

  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _website = TextEditingController();
  final List<_BankEntry> _banks = [];
  List<String> _phones = ['+971'];
  String _status = 'active';

  /// suspended / terminated are set by CNC admins, not the partner. When the
  /// account is in one of those states the control is read-only (web parity) and
  /// the status is never included in the save payload.
  bool get _statusLocked => _status == 'suspended' || _status == 'terminated';
  bool _autoAssign = true;
  int? _zoneId;
  List<int> _serviceZoneIds = const [];
  String _currentImage = ''; // server filename/url
  String? _pickedImagePath; // newly picked local file

  static String? imageUrl(String f) {
    if (f.isEmpty) return null;
    if (f.startsWith('http')) return f;
    if (f.startsWith('/uploads/')) return '${Env.apiUrl}$f';
    return '${Env.apiUrl}/uploads/$f';
  }

  /// Open the Camera/Gallery sheet and upload the photo immediately — the
  /// edit form's Save is not required for the picture. Updates the shared
  /// avatar provider so the app bar + hub reflect it at once.
  Future<void> _changePhoto() async {
    final picked = await pickProfileImage(context);
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      await repo.updatePartnerWithImage(_partnerId, const {},
          imagePath: picked.path);
      final fresh = await repo.getPartner(_partnerId);
      if (!mounted) return;
      setState(() {
        _currentImage = fresh.uploadFile;
        _pickedImagePath = null;
      });
      ref.read(profileImageProvider.notifier).setFromFilename(fresh.uploadFile);
      AppToast.success('Photo updated');
    } catch (_) {
      AppToast.error('Couldn\'t update photo. Try again.');
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  int get _partnerId => ref.read(authControllerProvider).user?.partnerId ?? 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final repo = ref.read(partnerRepositoryProvider);
    final results = await Future.wait([
      repo.getPartner(_partnerId),
      repo.zones().catchError((_) => <Zone>[]),
      repo
          .availabilityRules('partner', _partnerId)
          .catchError((_) => <AvailabilityRule>[]),
      repo.myServices().catchError((_) => <MyService>[]),
    ]);
    final p = results[0] as Partner;
    _name.text = p.name;
    _contact.text = p.contactPerson;
    _website.text = p.website;
    _phones = p.phones.isNotEmpty ? List<String>.from(p.phones) : ['+971'];
    // Keep the server's real status. Coercing anything that wasn't
    // 'not_working' to 'active' meant opening a SUSPENDED partner's profile and
    // saving silently reactivated them. suspended/terminated are admin-only —
    // preserve them and lock the control (see [_statusLocked]).
    _status = p.status.trim().isEmpty ? 'active' : p.status.trim();
    _autoAssign = p.acceptAutoAssign;
    _zoneId = p.primaryZoneId;
    _serviceZoneIds = p.serviceZoneIds;
    _currentImage = p.uploadFile;
    _pickedImagePath = null;
    // Keep the shared avatar (app bar + hub) in sync with fresh server data.
    ref.read(profileImageProvider.notifier).setFromFilename(p.uploadFile);
    for (final e in _banks) {
      e.dispose();
    }
    _banks
      ..clear()
      ..addAll(p.bankDetails.isEmpty
          ? [_BankEntry()]
          : p.bankDetails.map(_BankEntry.from));
    return _Data(
      p,
      results[1] as List<Zone>,
      results[2] as List<AvailabilityRule>,
      results[3] as List<MyService>,
    );
  }

  void _reload() => setState(() {
        _editing = false;
        _future = _load();
      });

  @override
  void dispose() {
    for (final c in [_name, _contact, _website]) {
      c.dispose();
    }
    for (final e in _banks) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppToast.error('Business name is required.');
      return;
    }
    setState(() => _busy = true);
    // Payload mirrors the web's partner-update body exactly so nothing is lost.
    final body = {
      'partnerName': _name.text.trim(),
      'contactPerson': _contact.text.trim(),
      'partnerWebsite': _website.text.trim(),
      // suspended / terminated are admin-controlled — never post them back from
      // the partner's own profile, or a save would attempt to un-suspend.
      if (!_statusLocked) 'status': _status,
      'acceptAutoAssign': _autoAssign,
      if (_zoneId != null) 'primaryZoneId': _zoneId,
      'serviceZoneIds':
          _serviceZoneIds.where((z) => z != _zoneId).toList(),
      'partnerPhones': [
        for (final p in _phones)
          if (p.trim().length > 4) {'number': p.trim()}
      ],
      'bankDetails': [
        for (final e in _banks)
          if (!e.isEmpty) e.toJson(),
      ],
    };
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (_pickedImagePath != null) {
        await repo.updatePartnerWithImage(_partnerId, body,
            imagePath: _pickedImagePath);
      } else {
        await repo.updatePartner(_partnerId, body);
      }
      AppToast.success('Profile updated');
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Business profile', actions: [
        if (!_editing)
          IconButton(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined)),
      ]),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 70);
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: 'Couldn\'t load your profile.', onRetry: _reload);
          }
          final p = snap.data!.partner;
          final zones = {for (final z in snap.data!.zones) z.id: z.label};
          return _editing
              ? _editView(p, snap.data!.zones)
              : _readView(p, zones, snap.data!.rules, snap.data!.services);
        },
      ),
      bottomNavigationBar: _editing
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                          onPressed: _busy ? null : _reload,
                          child: const Text('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.2, color: Colors.white))
                            : const Text('Save changes'),
                      ),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  // ---------- READ ----------
  Widget _readView(Partner p, Map<int, String> zones,
          List<AvailabilityRule> rules, List<MyService> services) =>
      ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _hero(p),
          const SizedBox(height: 16),
          _statsRow(p),
          _section('Identity', [
            _kv('Partner name', p.name),
            _kv('Contact', p.contactPerson),
            _kv('Code', p.code),
            _kv('Kind', p.kind),
            _kv('Priority', '${p.priority}'),
          ]),
          _section('Contact', [
            _kv('Email', p.email),
            _kv('Phone', p.phones.isNotEmpty ? p.phones.join(', ') : ''),
            _kv('Website', p.website),
          ]),
          _section('Location', [
            _kv('Primary zone', zones[p.primaryZoneId] ?? ''),
            _kv(
                'Service zones',
                p.serviceZoneIds
                    .map((id) => zones[id] ?? '#$id')
                    .join('\n')),
          ]),
          _hoursSection(rules),
          _section('Commercial', [
            _kv('Commission',
                p.commissionPct > 0 ? '${p.commissionPct}%' : '—'),
            _kv('Max discount',
                p.maxDiscountPercent > 0 ? '${p.maxDiscountPercent}%' : '—'),
            _kv('Buffer', '${p.bufferMinutes} min'),
            _kv('Revenue cap',
                p.annualRevenueLimit > 0 ? 'AED ${p.annualRevenueLimit.toStringAsFixed(0)}' : '—'),
          ]),
          _section('Compliance', [
            _kv('Has TRN', p.hasTRN ? 'Yes' : 'No'),
            _kv('TRN', p.trn),
          ]),
          _servicesSection(services),
          if (p.bankDetails.isNotEmpty)
            _section(
                'Bank details',
                p.bankDetails
                    .expand((b) => [
                          _kv('Bank', b.bankName),
                          _kv('Branch', b.branchName),
                          _kv('A/C', b.accountNumber),
                          _kv('IBAN', b.ibanNumber),
                        ])
                    .toList()),
        ],
      );

  Widget _avatar(String name, {bool editable = false}) {
    final initials = Text((name.isNotEmpty ? name[0] : '?').toUpperCase(),
        style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22));
    Widget avatar;
    if (_pickedImagePath != null) {
      avatar = Container(
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Image.file(File(_pickedImagePath!), fit: BoxFit.cover),
      );
    } else {
      avatar = ProfileAvatar(
        url: imageUrl(_currentImage),
        size: 64,
        backgroundColor: AppColors.brand600,
        placeholder: initials,
      );
    }
    if (!editable) return avatar;
    // Tapping the avatar opens the Camera/Gallery sheet and uploads
    // immediately — no Save needed for the photo.
    return GestureDetector(
      onTap: _uploadingPhoto ? null : _changePhoto,
      child: Stack(
        children: [
          avatar,
          if (_uploadingPhoto)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                    color: Colors.black38, shape: BoxShape.circle),
                child: const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: AppColors.brand600,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
              child:
                  const Icon(Icons.camera_alt, size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(Partner p) => Row(
        children: [
          _avatar(p.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name.isEmpty ? 'Partner' : p.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StatusBadge(p.status == 'active' ? 'completed' : p.status),
                    const SizedBox(width: 8),
                    if (p.code.isNotEmpty)
                      Text(p.code,
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
                if (p.createdAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                        'Joined ${DateFormat('d MMM y').format(p.createdAt!)}',
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11.5)),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _statsRow(Partner p) => Row(
        children: [
          Expanded(
              child: _stat('Rating',
                  p.ratingAvg > 0 ? p.ratingAvg.toStringAsFixed(2) : '—',
                  '${p.ratingCount} reviews')),
          const SizedBox(width: 10),
          Expanded(
              child: _stat('SOT %',
                  '${p.sotPct.toStringAsFixed(0)}%', 'Start on time')),
          const SizedBox(width: 10),
          Expanded(
              child: _stat('Auto-assign', p.acceptAutoAssign ? 'On' : 'Off',
                  p.availableOnline ? 'Available' : 'Offline')),
        ],
      );

  Widget _stat(String label, String value, String sub) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w800)),
            Text(label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textFaint, fontSize: 10.5)),
          ],
        ),
      );

  Widget _section(String title, List<Widget> rows) {
    final visible = rows.whereType<_KV>().where((w) => w.value.trim().isNotEmpty);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: visible.toList()),
        ),
      ],
    );
  }

  _KV _kv(String label, String value) => _KV(label, value);

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textMuted)),
      );

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  // ---------- OPERATING HOURS ----------
  Widget _hoursSection(List<AvailabilityRule> rules) {
    final active = rules.where((r) => r.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final activeDays = active.map((r) => r.dayOfWeek).toSet();
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    String fmt(String t) => t.length >= 5 ? t.substring(0, 5) : t;
    final ranges = active
        .map((r) => '${fmt(r.startTime)} – ${fmt(r.endTime)}')
        .toSet()
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Operating hours'),
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: _dayPill(labels[i], activeDays.contains(i)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.schedule, size: 16, color: AppColors.brand600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(ranges.join(', '),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ],
        )),
      ],
    );
  }

  Widget _dayPill(String label, bool on) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppColors.brand600 : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: on ? AppColors.brand600 : AppColors.border),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.textMuted)),
        ),
      );

  // ---------- SERVICES I PROVIDE ----------
  Widget _servicesSection(List<MyService> services) {
    if (services.isEmpty) return const SizedBox.shrink();
    final byVertical = <String, List<MyService>>{};
    for (final s in services) {
      final key = s.verticalName.isNotEmpty
          ? s.verticalName
          : (s.categoryName.isNotEmpty ? s.categoryName : 'Services');
      byVertical.putIfAbsent(key, () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Services I provide'),
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Linked from the catalog — dispatch picks you for matching bookings.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            for (final entry in byVertical.entries) ...[
              Text(entry.key,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in entry.value) _serviceChip(s.name),
                ],
              ),
              if (entry.key != byVertical.keys.last)
                const SizedBox(height: 14),
            ],
          ],
        )),
      ],
    );
  }

  Widget _serviceChip(String name) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.brand600.withValues(alpha: 0.3)),
        ),
        child: Text(name,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brand700)),
      );

  // ---------- EDIT ----------
  Widget _editView(Partner p, List<Zone> zones) {
    _zoneId ??= zones.isNotEmpty ? zones.first.id : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Column(
            children: [
              _avatar(_name.text, editable: true),
              const SizedBox(height: 6),
              Text('Tap the photo to change it',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _editLabel('Business name *'),
        _editField(_name),
        _editLabel('Contact person'),
        _editField(_contact),
        _editLabel('Website'),
        _editField(_website),
        _editLabel('Phone numbers'),
        for (var i = 0; i < _phones.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: PhoneField(
                    key: ValueKey('phone$i'),
                    label: '',
                    initial: _phones[i],
                    onChanged: (v) => _phones[i] = v,
                  ),
                ),
                if (_phones.length > 1)
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.rose),
                    onPressed: () => setState(() => _phones.removeAt(i)),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _phones.add('+971')),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add phone number'),
          ),
        ),
        const SizedBox(height: 10),
        _editLabel('Primary zone *'),
        // Two-step (Emirate → Area), matching the web's ZonePicker.
        Builder(builder: (_) {
          final emirates = <String>[];
          for (final z in zones) {
            if (z.emirate.isNotEmpty && !emirates.contains(z.emirate)) {
              emirates.add(z.emirate);
            }
          }
          final sel = zones.where((z) => z.id == _zoneId).toList();
          final curEmirate = sel.isNotEmpty ? sel.first.emirate : '';
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
                      final first =
                          zones.where((z) => z.emirate == picked).toList();
                      if (first.isNotEmpty) {
                        setState(() => _zoneId = first.first.id);
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PickerField(
                  value: sel.isNotEmpty ? sel.first.name : '',
                  hint: 'Area',
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
                    if (picked != null) setState(() => _zoneId = picked.id);
                  },
                ),
              ),
            ],
          );
        }),
        const SizedBox(height: 4),
        Text('Default operating zone — drives dispatch + scheduling.',
            style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
        const SizedBox(height: 14),
        _editLabel('Additional service zones'),
        Builder(builder: (_) {
          final selectable = zones.where((z) => z.id != _zoneId).toList();
          final sel = zones
              .where((z) => _serviceZoneIds.contains(z.id) && z.id != _zoneId)
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
              }
            },
          );
        }),
        const SizedBox(height: 14),
        _editLabel('Operating hours'),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AvailabilityEditor(
                  ownerType: 'partner',
                  ownerId: _partnerId,
                  title: 'Operating hours'))),
          icon: const Icon(Icons.schedule, size: 18),
          label: const Text('Edit working days & hours'),
          style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46)),
        ),
        const SizedBox(height: 14),
        _editLabel('Status'),
        if (_statusLocked)
          // Admin-controlled — read-only, with the reason (web parity).
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.amber.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.amber.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 18, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _status == 'suspended' ? 'Suspended' : 'Terminated',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your status is admin-controlled. Contact CNC support '
                        'to change it.',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Row(children: [
            _statusChip('active', 'Active'),
            const SizedBox(width: 8),
            _statusChip('not_working', 'Not working'),
          ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _autoAssign,
          activeThumbColor: AppColors.brand600,
          title: const Text('Auto-assign new bookings',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          onChanged: (v) => setState(() => _autoAssign = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text('BANK DETAILS',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted)),
        ),
        for (var i = 0; i < _banks.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Bank #${i + 1}',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: AppColors.textMuted)),
                    const Spacer(),
                    if (_banks.length > 1)
                      InkWell(
                        onTap: () => setState(() {
                          _banks.removeAt(i).dispose();
                        }),
                        child: const Icon(Icons.remove_circle_outline,
                            color: AppColors.rose, size: 20),
                      ),
                  ],
                ),
                _editField(_banks[i].name, hint: 'Bank name'),
                _editField(_banks[i].branch, hint: 'Branch'),
                _editField(_banks[i].account, hint: 'Account number'),
                _editField(_banks[i].iban, hint: 'IBAN'),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _banks.add(_BankEntry())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add bank account'),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
              'Commission, TRN, priority and limits are managed by CNC.',
              style: TextStyle(color: AppColors.textFaint, fontSize: 11.5)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _statusChip(String value, String label) {
    final on = _status == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _status = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.brand600 : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: on ? AppColors.brand600 : AppColors.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _editLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(t,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted)),
      );

  Widget _editField(TextEditingController c, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          decoration: InputDecoration(hintText: hint),
        ),
      );
}

class _KV extends StatelessWidget {
  final String label;
  final String value;
  const _KV(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _Data {
  final Partner partner;
  final List<Zone> zones;
  final List<AvailabilityRule> rules;
  final List<MyService> services;
  _Data(this.partner, this.zones, this.rules, this.services);
}

/// One editable bank-account row (its own controllers) so the partner can
/// keep several accounts — sent as the `bankDetails` array, like the web.
class _BankEntry {
  final TextEditingController name;
  final TextEditingController branch;
  final TextEditingController account;
  final TextEditingController iban;

  _BankEntry({String? name, String? branch, String? account, String? iban})
      : name = TextEditingController(text: name ?? ''),
        branch = TextEditingController(text: branch ?? ''),
        account = TextEditingController(text: account ?? ''),
        iban = TextEditingController(text: iban ?? '');

  factory _BankEntry.from(BankAccount b) => _BankEntry(
        name: b.bankName,
        branch: b.branchName,
        account: b.accountNumber,
        iban: b.ibanNumber,
      );

  bool get isEmpty =>
      name.text.trim().isEmpty &&
      account.text.trim().isEmpty &&
      iban.text.trim().isEmpty;

  Map<String, dynamic> toJson() => {
        'bankName': name.text.trim(),
        'branchName': branch.text.trim(),
        'accountNumber': account.text.trim(),
        'ibanNumber': iban.text.trim(),
      };

  void dispose() {
    name.dispose();
    branch.dispose();
    account.dispose();
    iban.dispose();
  }
}
