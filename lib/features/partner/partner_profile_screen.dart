import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../core/auth/auth_controller.dart';
import '../../core/config/env.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/phone_field.dart';
import '../../widgets/status_badge.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerProfileScreen extends ConsumerStatefulWidget {
  const PartnerProfileScreen({super.key});
  @override
  ConsumerState<PartnerProfileScreen> createState() =>
      _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends ConsumerState<PartnerProfileScreen> {
  late Future<_Data> _future;
  bool _editing = false;
  bool _busy = false;

  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _website = TextEditingController();
  final _bankName = TextEditingController();
  final _bankBranch = TextEditingController();
  final _bankAcc = TextEditingController();
  final _bankIban = TextEditingController();
  String _phone = '+971';
  String _status = 'active';
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

  Future<void> _pickImage() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
    if (x != null) setState(() => _pickedImagePath = x.path);
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
    ]);
    final p = results[0] as Partner;
    _name.text = p.name;
    _contact.text = p.contactPerson;
    _website.text = p.website;
    _phone = p.phones.isNotEmpty ? p.phones.first : '+971';
    _status = p.status == 'not_working' ? 'not_working' : 'active';
    _autoAssign = p.acceptAutoAssign;
    _zoneId = p.primaryZoneId;
    _serviceZoneIds = p.serviceZoneIds;
    _currentImage = p.uploadFile;
    _pickedImagePath = null;
    final bank = p.bankDetails.isNotEmpty ? p.bankDetails.first : null;
    _bankName.text = bank?.bankName ?? '';
    _bankBranch.text = bank?.branchName ?? '';
    _bankAcc.text = bank?.accountNumber ?? '';
    _bankIban.text = bank?.ibanNumber ?? '';
    return _Data(p, results[1] as List<Zone>);
  }

  void _reload() => setState(() {
        _editing = false;
        _future = _load();
      });

  @override
  void dispose() {
    for (final c in [
      _name,
      _contact,
      _website,
      _bankName,
      _bankBranch,
      _bankAcc,
      _bankIban
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppToast.error('Business name is required.');
      return;
    }
    setState(() => _busy = true);
    final bank = BankAccount(
      bankName: _bankName.text.trim(),
      branchName: _bankBranch.text.trim(),
      accountNumber: _bankAcc.text.trim(),
      ibanNumber: _bankIban.text.trim(),
    );
    final body = {
      'partnerName': _name.text.trim(),
      'contactPerson': _contact.text.trim(),
      'partnerWebsite': _website.text.trim(),
      'status': _status,
      'acceptAutoAssign': _autoAssign,
      if (_zoneId != null) 'primaryZoneId': _zoneId,
      'serviceZoneIds': _serviceZoneIds,
      'partnerPhones': [
        if (_phone.trim().length > 4) {'number': _phone.trim()}
      ],
      'bankDetails': [if (!bank.isEmpty) bank.toJson()],
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
          return _editing ? _editView(p, snap.data!.zones) : _readView(p, zones);
        },
      ),
    );
  }

  // ---------- READ ----------
  Widget _readView(Partner p, Map<int, String> zones) => ListView(
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
    ImageProvider? img;
    if (_pickedImagePath != null) {
      img = FileImage(File(_pickedImagePath!));
    } else {
      final u = imageUrl(_currentImage);
      if (u != null) img = NetworkImage(u);
    }
    final avatar = CircleAvatar(
      radius: 32,
      backgroundColor: AppColors.brand600,
      backgroundImage: img,
      child: img == null
          ? Text((name.isNotEmpty ? name[0] : '?').toUpperCase(),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 22))
          : null,
    );
    if (!editable) return avatar;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            children: [
              avatar,
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
                  child: const Icon(Icons.camera_alt,
                      size: 13, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: _pickImage,
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32)),
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: Text(_pickedImagePath == null && _currentImage.isEmpty
              ? 'Upload photo'
              : 'Change photo'),
        ),
      ],
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
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.photo_camera_outlined, size: 16),
                label: Text(
                    _pickedImagePath != null ? 'Change photo' : 'Add photo'),
              ),
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
        _editLabel('Phone'),
        PhoneField(label: '', initial: _phone, onChanged: (v) => _phone = v),
        const SizedBox(height: 14),
        _editLabel('Primary zone'),
        DropdownButtonFormField<int>(
          initialValue: _zoneId,
          isExpanded: true,
          items: zones
              .map((z) => DropdownMenuItem(
                  value: z.id,
                  child: Text(z.label, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _zoneId = v),
        ),
        const SizedBox(height: 14),
        _editLabel('Status'),
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
        _editField(_bankName, hint: 'Bank name'),
        _editField(_bankBranch, hint: 'Branch'),
        _editField(_bankAcc, hint: 'Account number'),
        _editField(_bankIban, hint: 'IBAN'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('Cancel')),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 48,
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
  _Data(this.partner, this.zones);
}
