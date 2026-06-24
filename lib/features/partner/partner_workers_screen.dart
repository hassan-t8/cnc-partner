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
  // Optimistic local edits (status / auto-assign) so the UI updates instantly,
  // before the server round-trip completes.
  final Map<int, Worker> _overrides = {};

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).workers();
  }

  Worker _apply(Worker w) => _overrides[w.id] ?? w;

  void _reload() => setState(() {
        _overrides.clear();
        _future = ref.read(partnerRepositoryProvider).workers();
      });

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
    final prev = _overrides[w.id];
    // Optimistic: reflect immediately.
    setState(() => _overrides[w.id] = w.copyWith(status: picked));
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateWorker(w.id, {'status': picked});
      AppToast.success('Status updated');
    } on ApiException catch (e) {
      setState(() {
        if (prev != null) {
          _overrides[w.id] = prev;
        } else {
          _overrides.remove(w.id);
        }
      });
      AppToast.error(e.message);
    }
  }

  Future<void> _toggleAutoAssign(Worker w, bool value) async {
    final prev = _overrides[w.id];
    // Optimistic: flip the switch right away.
    setState(() => _overrides[w.id] = w.copyWith(acceptAutoAssign: value));
    try {
      await ref
          .read(partnerRepositoryProvider)
          .updateWorker(w.id, {'acceptAutoAssign': value});
      AppToast.success(value ? 'Auto-assign on' : 'Auto-assign off');
    } on ApiException catch (e) {
      setState(() {
        if (prev != null) {
          _overrides[w.id] = prev;
        } else {
          _overrides.remove(w.id);
        }
      });
      AppToast.error(e.message);
    }
  }

  List<Worker> _filter(List<Worker> all) {
    final q = _query.toLowerCase();
    return all.map(_apply).where((w) {
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
    final roleLabel = w.roles.contains('driver') && w.roles.contains('crew')
        ? 'Crew · Driver'
        : (isDriver ? 'Driver' : 'Crew');
    // Subtle fade + rise entrance for a modern feel.
    return TweenAnimationBuilder<double>(
      key: ValueKey(w.id),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand700.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openForm(w),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header: avatar · name + role · status ───────────
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppColors.brand600, AppColors.brand700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brand600.withValues(alpha: 0.30),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        (w.name.isNotEmpty ? w.name[0] : '?').toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.name.isEmpty ? 'Worker' : w.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                                isDriver
                                    ? Icons.directions_car_filled
                                    : Icons.cleaning_services,
                                size: 13,
                                color: AppColors.textFaint),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                  w.code.isEmpty
                                      ? roleLabel
                                      : '$roleLabel · ${w.code}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (w.ratingCount > 0) ...[
                              const SizedBox(width: 8),
                              Icon(Icons.star_rounded,
                                  size: 14, color: AppColors.star),
                              const SizedBox(width: 2),
                              Text(w.ratingAvg.toStringAsFixed(1),
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _changeStatus(w),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StatusBadge(w.displayStatus, worker: true),
                        Icon(Icons.expand_more,
                            size: 16, color: AppColors.textFaint),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Info block: phone · address · auto-assign ─────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _infoRow(Icons.phone_outlined,
                        w.phone.isEmpty ? 'No phone' : w.phone),
                    if (w.email.isNotEmpty)
                      _infoRow(Icons.mail_outline_rounded, w.email),
                    if (w.homeAddress.isNotEmpty)
                      _infoRow(Icons.place_outlined, w.homeAddress),
                    Divider(height: 12, color: AppColors.border),
                    Row(
                      children: [
                        Icon(Icons.bolt_outlined,
                            size: 16, color: AppColors.brand600),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Auto-assign new bookings',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                        SizedBox(
                          height: 28,
                          child: Switch(
                            value: w.acceptAutoAssign,
                            activeThumbColor: AppColors.brand600,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) => _toggleAutoAssign(w, v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Actions ───────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                      child: _actionBtn(Icons.key_outlined, 'Account',
                          () => _manageAccount(w))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionBtn(
                          Icons.edit_outlined, 'Edit', () => _openForm(w))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _actionBtn(Icons.delete_outline, 'Delete',
                          () => _delete(w),
                          danger: true)),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap,
          {bool danger = false}) =>
      OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: danger ? AppColors.rose : AppColors.textMuted,
          side: BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
