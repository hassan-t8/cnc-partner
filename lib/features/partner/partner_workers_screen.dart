import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'worker_form.dart';

class PartnerWorkersScreen extends ConsumerStatefulWidget {
  const PartnerWorkersScreen({super.key});
  @override
  ConsumerState<PartnerWorkersScreen> createState() =>
      _PartnerWorkersScreenState();
}

class _PartnerWorkersScreenState extends ConsumerState<PartnerWorkersScreen> {
  late Future<List<Worker>> _future;
  String _query = '';
  String _role = 'all';

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).workers();
  }

  void _reload() =>
      setState(() => _future = ref.read(partnerRepositoryProvider).workers());

  Future<void> _openForm([Worker? w]) async {
    final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => WorkerForm(worker: w)));
    if (saved == true) _reload();
  }

  Future<void> _delete(Worker w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete worker?'),
        content: Text('Remove "${w.name}"? This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(partnerRepositoryProvider).deleteWorker(w.id);
      AppToast.success('Worker deleted');
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    }
  }

  static const _statusLabels = {
    'active': 'Active',
    'not_working': 'Not working',
    'on_leave': 'On leave',
    'suspended': 'Suspended',
  };

  Future<void> _manageAccount(Worker w) async {
    final repo = ref.read(partnerRepositoryProvider);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AccountSheet(worker: w, repo: repo),
    );
  }

  Future<void> _changeStatus(Worker w) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Set status · ${w.name}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            for (final e in _statusLabels.entries)
              ListTile(
                title: Text(e.value),
                trailing: w.status == e.key
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.brand600)
                    : null,
                onTap: () => Navigator.pop(context, e.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == w.status) return;
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateWorker(w.id, {'status': picked});
      AppToast.success('Status updated');
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    }
  }

  List<Worker> _filter(List<Worker> all) {
    final q = _query.toLowerCase();
    return all.where((w) {
      if (_role != 'all' && !w.roles.contains(_role)) return false;
      if (q.isEmpty) return true;
      return [w.name, w.code, w.phone, w.email]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.brand600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add worker', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                      hintText: 'Search name, code, phone…',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ['all', 'crew', 'driver'].map((r) {
                    final on = _role == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r == 'all' ? 'All' : r),
                        selected: on,
                        onSelected: (_) => setState(() => _role = r),
                        selectedColor: AppColors.brand600,
                        labelStyle: TextStyle(
                            color: on ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                        backgroundColor: AppColors.surface,
                        side: BorderSide(color: AppColors.border),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Worker>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LoadingList();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(
                        message: 'Couldn\'t load workers.', onRetry: _reload);
                  }
                  final rows = _filter(snap.data ?? const []);
                  if (rows.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(
                          icon: Icons.groups_outlined,
                          title: 'No workers',
                          subtitle: 'Add workers from the web portal.'),
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
          ),
        ],
      ),
    );
  }

  Widget _card(Worker w) {
    final isDriver = w.roles.contains('driver');
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openForm(w),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.brand50,
                    child: Text(
                      (w.name.isNotEmpty ? w.name[0] : '?').toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.brand700,
                          fontWeight: FontWeight.w800,
                          fontSize: 17),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(w.name.isEmpty ? 'Worker' : w.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => _changeStatus(w),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  StatusBadge(w.displayStatus, worker: true),
                                  Icon(Icons.expand_more,
                                      size: 15, color: AppColors.textFaint),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _pill(
                                isDriver
                                    ? Icons.directions_car_filled
                                    : Icons.cleaning_services,
                                isDriver ? 'Driver' : 'Crew'),
                            if (w.code.isNotEmpty)
                              _pill(Icons.badge_outlined, w.code),
                            if (w.ratingCount > 0)
                              _pill(Icons.star_rounded,
                                  '${w.ratingAvg.toStringAsFixed(1)} (${w.ratingCount})',
                                  color: AppColors.star),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.border),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 14, color: AppColors.textFaint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(w.phone.isEmpty ? 'No phone' : w.phone,
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5)),
                  ),
                  _miniAction(Icons.key_outlined, 'Account',
                      () => _manageAccount(w)),
                  _miniAction(Icons.edit_outlined, 'Edit', () => _openForm(w)),
                  _miniAction(Icons.delete_outline, 'Delete', () => _delete(w),
                      danger: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color ?? AppColors.textMuted),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _miniAction(IconData icon, String tip, VoidCallback onTap,
          {bool danger = false}) =>
      IconButton(
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        tooltip: tip,
        icon: Icon(icon,
            size: 18, color: danger ? AppColors.rose : AppColors.textMuted),
      );
}

/// Worker account sheet: shows login status and lets the partner set a password
/// or email a reset link.
class _AccountSheet extends StatefulWidget {
  final Worker worker;
  final PartnerRepository repo;
  const _AccountSheet({required this.worker, required this.repo});
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  bool _busy = false;
  final _pw = TextEditingController();
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    widget.repo.workerLoginInfo(widget.worker.id).then((m) {
      if (!mounted) return;
      setState(() {
        _info = m;
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _setPassword() async {
    if (_pw.text.trim().length < 6) {
      AppToast.error('Password must be at least 6 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.setWorkerPassword(widget.worker.id, _pw.text.trim());
      AppToast.success('Password set');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset() async {
    setState(() => _busy = true);
    try {
      final r = await widget.repo.sendWorkerReset(widget.worker.id);
      AppToast.success('Reset link sent to ${r['sentTo'] ?? 'email'}');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogin = _info?['hasLogin'] == true;
    final email = '${_info?['email'] ?? widget.worker.email}';
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.worker.name} · account',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2)),
                )
              else
                Row(
                  children: [
                    Icon(hasLogin ? Icons.check_circle : Icons.info_outline,
                        size: 15,
                        color:
                            hasLogin ? AppColors.brand600 : AppColors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          hasLogin
                              ? 'Has login · ${email.isEmpty ? '—' : email}'
                              : 'No login yet${email.isEmpty ? '' : ' · $email'}',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12.5)),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              const Text('Set password',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _pw,
                obscureText: _obscure,
                decoration: InputDecoration(
                  hintText: 'New password (min 6)',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _busy ? null : _setPassword,
                  child: const Text('Set password'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: (_busy || email.isEmpty) ? null : _sendReset,
                  icon: const Icon(Icons.email_outlined, size: 18),
                  label: Text(email.isEmpty
                      ? 'No email on file'
                      : 'Email a reset link'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
