import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class ServiceRequestsScreen extends ConsumerStatefulWidget {
  const ServiceRequestsScreen({super.key});
  @override
  ConsumerState<ServiceRequestsScreen> createState() =>
      _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState
    extends ConsumerState<ServiceRequestsScreen> {
  late Future<List<ServiceRequest>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).serviceRequests();
  }

  void _reload() => setState(
      () => _future = ref.read(partnerRepositoryProvider).serviceRequests());

  Future<void> _newRequest() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _RequestForm(),
    );
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Service requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newRequest,
        backgroundColor: AppColors.brand600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New request', style: TextStyle(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<ServiceRequest>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList();
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load requests.', onRetry: _reload);
            }
            final rows = snap.data ?? const [];
            if (rows.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(
                    icon: Icons.auto_awesome_outlined,
                    title: 'No requests yet',
                    subtitle:
                        'Ask CNC to add a service you provide that isn\'t listed.'),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _card(rows[i]),
            );
          },
        ),
      ),
    );
  }

  (Color, Color) _statusColor(String s) {
    switch (s) {
      case 'approved_linked':
      case 'approved_created':
        return (const Color(0xFFD1FAE5), const Color(0xFF065F46));
      case 'in_review':
        return (const Color(0xFFE0F2FE), const Color(0xFF075985));
      case 'declined':
        return (const Color(0xFFFFE4E6), const Color(0xFF9F1239));
      default:
        return (const Color(0xFFF3F4F6), const Color(0xFF374151));
    }
  }

  Widget _card(ServiceRequest r) {
    final (bg, fg) = _statusColor(r.status);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r.requestedName.isEmpty ? 'Request' : r.requestedName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(6)),
                child: Text(r.status.replaceAll('_', ' ').toUpperCase(),
                    style: TextStyle(
                        color: fg,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          if (r.adminNotes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(r.adminNotes,
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 12.5)),
          ],
          if (r.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(DateFormat('d MMM y').format(r.createdAt!),
                style:
                    TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ],
        ],
      ),
    );
  }
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm();
  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      AppToast.error('Service name is required.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(partnerRepositoryProvider).submitServiceRequest({
        'requestedName': _name.text.trim(),
        if (_desc.text.trim().isNotEmpty) 'description': _desc.text.trim(),
        if (_price.text.trim().isNotEmpty)
          'targetPriceRange': _price.text.trim(),
        if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
      });
      AppToast.success('Request submitted');
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New service request',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Service name *')),
              const SizedBox(height: 10),
              TextField(
                  controller: _desc,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'What does it include?')),
              const SizedBox(height: 10),
              TextField(
                  controller: _price,
                  decoration: const InputDecoration(
                      labelText: 'Target price range (e.g. 200-350 AED)')),
              const SizedBox(height: 10),
              TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration:
                      const InputDecoration(labelText: 'Notes for CNC')),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white))
                      : const Text('Submit request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
