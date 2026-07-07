import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/searchable_picker.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Web-parity "Assign team" sheet: shows the current team (with remove) and an
/// Add-to-team block — Crew (multi, zone-grouped), Driver + Van pickers that
/// show each candidate's code + zone so the partner can verify who they pick.
/// Picking a van auto-fills its default driver. Returns true if anything
/// changed.
Future<bool> showAssignTeamSheet(BuildContext context, WidgetRef ref,
    {required int bookingId,
    required String ref0,
    DateTime? scheduledStart,
    int? zoneId}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AssignTeamSheet(
        bookingId: bookingId,
        bref: ref0,
        scheduledStart: scheduledStart,
        zoneId: zoneId),
  );
  return changed ?? false;
}

class _AssignTeamSheet extends ConsumerStatefulWidget {
  final int bookingId;
  final String bref;
  final DateTime? scheduledStart;
  final int? zoneId;
  const _AssignTeamSheet(
      {required this.bookingId,
      required this.bref,
      this.scheduledStart,
      this.zoneId});
  @override
  ConsumerState<_AssignTeamSheet> createState() => _AssignTeamSheetState();
}

class _AssignTeamSheetState extends ConsumerState<_AssignTeamSheet> {
  List<BookingAssignment> _team = [];
  List<Worker> _workers = [];
  List<Van> _vans = [];
  Map<int, Zone> _zones = {};
  bool _loading = true;
  bool _adding = false;
  bool _changed = false;
  final Set<int> _removing = {};

  final List<Worker> _crew = [];
  Worker? _driver;
  Van? _van;

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    try {
      final res = await Future.wait([
        _repo.bookingAssignments(widget.bookingId),
        _repo.workers().catchError((_) => <Worker>[]),
        _repo.vans().catchError((_) => <Van>[]),
        _repo.zones().catchError((_) => <Zone>[]),
      ]);
      if (!mounted) return;
      setState(() {
        _team = res[0] as List<BookingAssignment>;
        _workers = (res[1] as List<Worker>).where((w) => w.status == 'active').toList();
        _vans = (res[2] as List<Van>).where((v) => v.status == 'active').toList();
        _zones = {for (final z in (res[3] as List<Zone>)) z.id: z};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadTeam() async {
    try {
      final t = await _repo.bookingAssignments(widget.bookingId);
      if (mounted) setState(() => _team = t);
    } catch (_) {}
  }

  Set<int> get _assignedIds =>
      {for (final a in _team) if (a.workerId != null) a.workerId!};

  String _zoneLabel(int? zoneId) => _zones[zoneId]?.label ?? '';
  bool _inZone(int? primaryZoneId) =>
      widget.zoneId != null && primaryZoneId == widget.zoneId;

  String _wLabel(Worker w) {
    final z = _zoneLabel(w.primaryZoneId);
    return [w.name.isEmpty ? 'Worker' : w.name, w.code, if (z.isNotEmpty) z]
        .where((s) => s.isNotEmpty)
        .join(' · ');
  }

  // Vans already on this booking's team → disabled in the picker ("already
  // added"), matching the web.
  Set<int> get _assignedVanIds =>
      {for (final a in _team) if (a.vanId != null) a.vanId!};

  String _vLabel(Van v) {
    final z = _zoneLabel(v.homeZoneId);
    return [
      v.code,
      v.plate,
      if (z.isNotEmpty) z,
      if (v.driverName.isNotEmpty) 'driver: ${v.driverName}',
    ].where((s) => s.isNotEmpty).join(' · ');
  }

  // ---- pickers ----
  Future<void> _pickCrew() async {
    final pool = _workers
        .where((w) => w.roles.contains('crew') || w.roles.isEmpty)
        .where((w) => !_assignedIds.contains(w.id))
        .toList();
    final picked = await showMultiSearchablePicker<Worker>(
      context: context,
      title: 'Add crew',
      items: pool,
      selected: _crew,
      labelOf: _wLabel,
      keyOf: (w) => w.id,
      groupOf: (w) => _inZone(w.primaryZoneId)
          ? 'In this zone'
          : (_zoneLabel(w.primaryZoneId).isEmpty
              ? 'Other'
              : _zoneLabel(w.primaryZoneId)),
    );
    if (picked != null) setState(() => _crew..clear()..addAll(picked));
  }

  Future<void> _pickDriver() async {
    final pool = _workers.where((w) => w.roles.contains('driver')).toList();
    final picked = await showSearchablePicker<Worker>(
      context: context,
      title: 'Driver',
      items: pool,
      selected: _driver,
      labelOf: _wLabel,
      equals: (a, b) => a.id == b.id,
      enabledOf: (w) => !_assignedIds.contains(w.id),
      disabledReasonOf: (_) => 'already added',
    );
    if (picked != null) setState(() => _driver = picked);
  }

  Future<void> _pickVan() async {
    final picked = await showSearchablePicker<Van>(
      context: context,
      title: 'Van',
      items: _vans,
      selected: _van,
      labelOf: _vLabel,
      equals: (a, b) => a.id == b.id,
      // A van already on this booking's team can't be added again.
      enabledOf: (v) => !_assignedVanIds.contains(v.id),
      disabledReasonOf: (_) => 'already added',
    );
    if (picked != null) {
      setState(() {
        _van = picked;
        // Auto-fill the van's default driver (web parity).
        if (picked.driverWorkerId != null) {
          final d = _workers.where((w) => w.id == picked.driverWorkerId);
          if (d.isNotEmpty && !_assignedIds.contains(d.first.id)) {
            _driver = d.first;
          }
        }
      });
    }
  }

  Future<void> _addToTeam() async {
    // Synchronous re-entry guard: `_adding` is set inside setState (async
    // rebuild), so a rapid double-tap could fire this twice before the button
    // disables and create duplicate assignment rows. This bails in-thread —
    // first tap wins, the rest no-op. (Mirrors the web savingRef fix.)
    if (_adding) return;
    if (_crew.isEmpty && _driver == null) {
      AppToast.error('Pick a crew member or driver first');
      return;
    }
    setState(() => _adding = true);
    try {
      for (final c in _crew) {
        await _repo.assignWorker(widget.bookingId, c.id, role: 'crew');
      }
      if (_driver != null) {
        await _repo.assignWorker(widget.bookingId, _driver!.id,
            role: 'driver', vanId: _van?.id);
      }
      _changed = true;
      AppToast.success('Team updated');
      setState(() {
        _crew.clear();
        _driver = null;
        _van = null;
      });
      await _reloadTeam();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _remove(BookingAssignment a) async {
    setState(() => _removing.add(a.id));
    try {
      await _repo.unassign(a.id);
      _changed = true;
      await _reloadTeam();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _removing.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.scheduledStart != null
        ? '${widget.bref} · ${DateFormat('EEE, MMM d, h:mm a').format(widget.scheduledStart!)}'
        : widget.bref;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, controller) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(4))),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
                child: Row(
                  children: [
                    Icon(Icons.groups_2_outlined, color: AppColors.brand600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Assign team',
                              style: TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(sub,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(context, _changed),
                        icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          if (_team.isEmpty)
                            Text('No one assigned yet.',
                                style: TextStyle(color: AppColors.textMuted))
                          else
                            ..._team.map(_teamRow),
                          const SizedBox(height: 16),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Text('ADD TO TEAM',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                  color: AppColors.textMuted)),
                          const SizedBox(height: 12),
                          _fieldLabel(Icons.groups_outlined, 'Crew'),
                          const SizedBox(height: 6),
                          PickerField(
                            value: _crew.isEmpty
                                ? ''
                                : _crew.map((w) => w.name).join(', '),
                            hint: 'Select crew',
                            onTap: _pickCrew,
                          ),
                          if (_crew.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final w in _crew)
                                    _chip(w.name, () =>
                                        setState(() => _crew.remove(w))),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          _fieldLabel(
                              Icons.person_outline, 'Driver (optional)'),
                          const SizedBox(height: 6),
                          PickerField(
                            value: _driver == null ? '' : _wLabel(_driver!),
                            hint: '— No driver —',
                            onTap: _pickDriver,
                          ),
                          const SizedBox(height: 14),
                          _fieldLabel(
                              Icons.local_shipping_outlined, 'Van (optional)'),
                          const SizedBox(height: 6),
                          PickerField(
                            value: _van == null ? '' : _vLabel(_van!),
                            hint: '— No van —',
                            onTap: _pickVan,
                          ),
                          const SizedBox(height: 6),
                          Text(
                              'Picking a van auto-fills its default driver above.',
                              style: TextStyle(
                                  fontSize: 11.5, color: AppColors.textMuted)),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: _adding ? null : _addToTeam,
                              icon: _adding
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white))
                                  : const Icon(Icons.add, size: 18),
                              label: const Text('Add to team'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _chip(String label, VoidCallback onRemove) => Container(
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: TextStyle(
                    color: AppColors.brand700,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5)),
            const SizedBox(width: 4),
            GestureDetector(
                onTap: onRemove,
                child:
                    Icon(Icons.close, size: 15, color: AppColors.brand700)),
          ],
        ),
      );

  Widget _teamRow(BookingAssignment a) {
    final removing = _removing.contains(a.id);
    final isDriver = a.role.toLowerCase() == 'driver';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.violet.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Text(a.role.isEmpty ? 'CREW' : a.role.toUpperCase(),
                style: TextStyle(
                    color: AppColors.violet,
                    fontWeight: FontWeight.w800,
                    fontSize: 10)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.workerName.isEmpty ? 'Worker' : a.workerName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (isDriver && a.vanLabel.isNotEmpty)
                  Text('Van: ${a.vanLabel}',
                      style: TextStyle(
                          fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          if (a.status.isNotEmpty)
            Text(a.status.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: a.status == 'cancelled'
                        ? AppColors.textFaint
                        : AppColors.textMuted)),
          removing
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2)),
                )
              : IconButton(
                  onPressed: () => _remove(a),
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: AppColors.rose),
                  tooltip: 'Remove'),
        ],
      ),
    );
  }
}
