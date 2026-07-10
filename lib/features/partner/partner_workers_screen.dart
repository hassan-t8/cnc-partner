import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/search_filter_bar.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'partner_schedule_screen.dart';
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
  String _status = 'all';
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
    await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => WorkerForm(worker: w)));
    // Always refresh — the form may have saved the auto-assign toggle
    // immediately without returning a "saved" flag.
    if (mounted) _reload();
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
      builder: (_) => _AccountSheet(
        worker: w,
        repo: repo,
        onStatusChanged: (status) => _applyStatus(w, status),
      ),
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
    await _applyStatus(w, picked);
  }

  // Optimistic status update shared by the status picker and the Account sheet.
  Future<bool> _applyStatus(Worker w, String status) async {
    final prev = _overrides[w.id];
    setState(() => _overrides[w.id] = w.copyWith(status: status));
    try {
      // Dedicated status route — the generic updateWorker rejects
      // `not_working`, which is one of the options this picker offers, with a
      // 400. This endpoint accepts it.
      await ref.read(partnerRepositoryProvider).setWorkerStatus(w.id, status);
      AppToast.success('Status updated');
      return true;
    } on ApiException catch (e) {
      setState(() {
        if (prev != null) {
          _overrides[w.id] = prev;
        } else {
          _overrides.remove(w.id);
        }
      });
      AppToast.error(e.message);
      return false;
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
      if (_status != 'all') {
        // 'pending' is a derived, exclusive state: a pending worker must not
        // show under 'active', and an activated worker must not show under
        // 'pending'. Other statuses match on Worker.status directly.
        if (_status == 'pending') {
          if (!w.pendingActivation) return false;
        } else if (_status == 'active') {
          if (w.pendingActivation) return false;
          if (w.status != 'active') return false;
        } else if (w.status != _status) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      return [w.name, w.code, w.phone, w.email]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar('Workers'),
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
            child: SearchFilterBar(
              hint: 'Search name, code, phone…',
              onSearch: (v) => setState(() => _query = v),
              values: {'role': _role, 'status': _status},
              onApply: (m) => setState(() {
                _role = m['role'] ?? 'all';
                _status = m['status'] ?? 'all';
              }),
              groups: const [
                FilterGroup(key: 'role', label: 'Role', options: [
                  FilterOption('all', 'All roles'),
                  FilterOption('crew', 'Crew'),
                  FilterOption('driver', 'Driver'),
                ]),
                FilterGroup(key: 'status', label: 'Status', options: [
                  FilterOption('all', 'All statuses'),
                  FilterOption('active', 'Active'),
                  FilterOption('not_working', 'Not working'),
                  FilterOption('pending', 'Pending'),
                  FilterOption('on_leave', 'On leave'),
                  FilterOption('suspended', 'Suspended'),
                ]),
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
              // ── Schedule (recurring shifts + leaves) ──────────────
              SizedBox(
                width: double.infinity,
                child: _actionBtn(
                    Icons.calendar_month_outlined, 'Schedule + leaves', () {
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => PartnerScheduleScreen(initialWorker: w)));
                }),
              ),
              const SizedBox(height: 8),
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
  // Returns true when the status change persisted, so the sheet can reflect it.
  final Future<bool> Function(String status) onStatusChanged;
  const _AccountSheet({
    required this.worker,
    required this.repo,
    required this.onStatusChanged,
  });
  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  Map<String, dynamic>? _info;
  bool _loading = true;
  // Local mirror of the worker's status so the sheet reflects changes it makes.
  late String _status = widget.worker.status;
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

  // Put on leave / suspend / reactivate — keeps the sheet open and reflects the
  // new status. Delegates the persistence + list update to the parent.
  Future<void> _changeStatus(String status) async {
    setState(() => _busy = true);
    final ok = await widget.onStatusChanged(status);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _status = status;
    });
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return AppColors.brand600;
      case 'on_leave':
        return AppColors.amber;
      case 'suspended':
        return AppColors.rose;
      default:
        return AppColors.textMuted;
    }
  }

  static const _statusText = {
    'active': 'Active',
    'on_leave': 'On leave',
    'suspended': 'Suspended',
    'not_working': 'Not working',
  };

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
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('STATUS',
                      style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(_status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(_statusText[_status] ?? _status,
                        style: TextStyle(
                            color: _statusColor(_status),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
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
              const SizedBox(height: 20),
              Text('ACCOUNT STATUS',
                  style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
              const SizedBox(height: 10),
              // On leave ⇄ active (operational only — login stays active).
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _changeStatus(
                          _status == 'on_leave' ? 'active' : 'on_leave'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.amber,
                    side: BorderSide(color: AppColors.amber),
                  ),
                  child: Text(_status == 'on_leave'
                      ? 'End leave (set active)'
                      : 'Put on leave'),
                ),
              ),
              const SizedBox(height: 10),
              // Suspend ⇄ reactivate (blocks login + auto-dispatch).
              SizedBox(
                width: double.infinity,
                height: 46,
                child: _status == 'suspended'
                    ? ElevatedButton.icon(
                        onPressed: _busy ? null : () => _changeStatus('active'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand600),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Reactivate account'),
                      )
                    : ElevatedButton.icon(
                        onPressed:
                            _busy ? null : () => _changeStatus('suspended'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.rose),
                        icon: const Icon(Icons.block, size: 18),
                        label: const Text('Suspend account'),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                "Suspended workers can't log in and are excluded from "
                'auto-dispatch. Leave is operational only — login stays active.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
