import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
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
  late Future<Partner> _future;
  bool _editing = false;
  bool _busy = false;
  final _name = TextEditingController();
  final _contact = TextEditingController();
  final _website = TextEditingController();
  final _phone = TextEditingController();

  int get _partnerId => ref.read(authControllerProvider).user?.partnerId ?? 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Partner> _load() async {
    final p = await ref.read(partnerRepositoryProvider).getPartner(_partnerId);
    _name.text = p.name;
    _contact.text = p.contactPerson;
    _website.text = p.website;
    _phone.text = p.phones.isNotEmpty ? p.phones.first : '';
    return p;
  }

  void _reload() => setState(() {
        _editing = false;
        _future = _load();
      });

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    _website.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AppToast.error('Business name is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(partnerRepositoryProvider).updatePartner(_partnerId, {
        'partnerName': _name.text.trim(),
        'contactPerson': _contact.text.trim(),
        'partnerWebsite': _website.text.trim(),
        'partnerPhones': [
          if (_phone.text.trim().isNotEmpty) {'number': _phone.text.trim()}
        ],
      });
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
      appBar: AppBar(
        title: const Text('Business profile'),
        actions: [
          if (!_editing)
            IconButton(
                onPressed: () => setState(() => _editing = true),
                icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      body: FutureBuilder<Partner>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 70);
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: 'Couldn\'t load your profile.', onRetry: _reload);
          }
          final p = snap.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.brand600,
                    child: Text(
                        (p.name.isNotEmpty ? p.name[0] : '?').toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.name.isEmpty ? 'Partner' : p.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        StatusBadge(
                            p.status == 'active' ? 'completed' : p.status),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!_editing) ...[
                _viewRow('Code', p.code),
                _viewRow('Email', p.email),
                _viewRow('Contact person', p.contactPerson),
                _viewRow('Website', p.website),
                _viewRow('Phone', p.phones.isNotEmpty ? p.phones.first : ''),
                _viewRow('Commission',
                    p.commissionPct > 0 ? '${p.commissionPct}%' : ''),
                _viewRow('Rating',
                    p.ratingAvg > 0 ? p.ratingAvg.toStringAsFixed(1) : ''),
              ] else ...[
                _editField('Business name *', _name),
                _editField('Contact person', _contact),
                _editField('Website', _website),
                _editField('Phone', _phone, keyboard: TextInputType.phone),
                const SizedBox(height: 12),
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
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _viewRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 12.5)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _editField(String label, TextEditingController c,
          {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label),
        ),
      );
}
