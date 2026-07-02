import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Worker Schedule — recurring weekly shifts + leaves / one-off changes.
///
/// Mirrors the partner web portal's WorkerScheduleModal. The concepts map
/// straight onto the backend:
///   • Recurring rules  = availability rules   (ownerType='worker').
///   • Leaves / one-off = availability exceptions ('off' / 'extra').
///
/// dayOfWeek is 0=Sunday … 6=Saturday (JS Date.getDay()), confirmed against
/// the backend AvailabilityRule model.
///
/// The profile hub opens this with no arguments, so the screen first lets the
/// partner pick one of their workers, then edits that worker's schedule.
class PartnerScheduleScreen extends ConsumerStatefulWidget {
  /// When opened for a specific worker (e.g. the "Schedule" action on a worker
  /// row), skip the picker and go straight to that worker's editor.
  final Worker? initialWorker;
  const PartnerScheduleScreen({super.key, this.initialWorker});
  @override
  ConsumerState<PartnerScheduleScreen> createState() =>
      _PartnerScheduleScreenState();
}

class _PartnerScheduleScreenState
    extends ConsumerState<PartnerScheduleScreen> {
  late Future<List<Worker>> _workersFuture;
  Worker? _selected;

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _selected = widget.initialWorker;
    _workersFuture = _repo.workers();
  }

  void _reloadWorkers() =>
      setState(() => _workersFuture = _repo.workers());

  @override
  Widget build(BuildContext context) {
    // When a worker's editor is showing, the editor draws its own header (with
    // a back button), so hide the scaffold app bar to avoid a double bar.
    return Scaffold(
      appBar: _selected == null ? MainAppBar('Worker Schedule') : null,
      body: FutureBuilder<List<Worker>>(
        future: _workersFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const LoadingList(height: 64);
          }
          if (snap.hasError) {
            return ErrorRetry(
                message: "Couldn't load workers.", onRetry: _reloadWorkers);
          }
          final workers = snap.data ?? const <Worker>[];
          if (workers.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 80),
              EmptyState(
                icon: Icons.groups_outlined,
                title: 'No workers yet',
                subtitle: 'Add a worker to manage their schedule.',
              ),
            ]);
          }
          if (_selected != null) {
            return SafeArea(
              bottom: false,
              child: _WorkerScheduleEditor(
                key: ValueKey(_selected!.id),
                worker: _selected!,
                // Opened per-worker (from a card / edit form) → back pops the
                // route. Opened via the picker → back returns to the picker.
                onBack: widget.initialWorker != null
                    ? () => Navigator.of(context).pop()
                    : () => setState(() => _selected = null),
              ),
            );
          }
          return _pickerList(workers);
        },
      ),
    );
  }

  Widget _pickerList(List<Worker> workers) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: workers.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('Pick a worker to view or edit their schedule.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            );
          }
          final w = workers[i - 1];
          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selected = w),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.brand50,
                    child: Text(
                      (w.name.isNotEmpty ? w.name[0] : '?').toUpperCase(),
                      style: const TextStyle(
                          color: AppColors.brand700,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.name.isEmpty ? 'Worker #${w.id}' : w.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                        if (w.code.isNotEmpty)
                          Text(w.code,
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textFaint),
                ],
              ),
            ),
          );
        },
      );
}

// ── One worker's schedule editor ─────────────────────────────────────────

class _WorkerScheduleEditor extends ConsumerStatefulWidget {
  final Worker worker;
  final VoidCallback onBack;
  const _WorkerScheduleEditor({
    super.key,
    required this.worker,
    required this.onBack,
  });

  @override
  ConsumerState<_WorkerScheduleEditor> createState() =>
      _WorkerScheduleEditorState();
}

class _WorkerScheduleEditorState
    extends ConsumerState<_WorkerScheduleEditor> {
  static const _dayLong = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday'
  ];
  static const _dayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool _loading = true;
  bool _error = false;
  bool _busy = false;

  List<AvailabilityRule> _rules = const [];
  List<AvailabilityException> _exceptions = const [];

  // Bulk-add form (same window applied to multiple days).
  final Set<int> _bulkDays = {1, 2, 3, 4, 5};
  TimeOfDay _bulkStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _bulkEnd = const TimeOfDay(hour: 17, minute: 0);

  // Add-exception form.
  DateTime? _exDate;
  String _exType = 'off';
  TimeOfDay? _exStart;
  TimeOfDay? _exEnd;
  final _exReason = TextEditingController();

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);
  int get _workerId => widget.worker.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _exReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final now = DateTime.now();
      final from = _fmtDate(now);
      final to = _fmtDate(now.add(const Duration(days: 90)));
      final results = await Future.wait([
        _repo.availabilityRules('worker', _workerId),
        _repo.availabilityExceptions('worker', _workerId, from: from, to: to),
      ]);
      final rules = results[0] as List<AvailabilityRule>;
      final exceptions = results[1] as List<AvailabilityException>;
      rules.sort((a, b) => a.dayOfWeek != b.dayOfWeek
          ? a.dayOfWeek.compareTo(b.dayOfWeek)
          : a.startTime.compareTo(b.startTime));
      exceptions.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _rules = rules.where((r) => r.isActive).toList();
        _exceptions = exceptions;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  // ── formatting helpers ─────────────────────────────────────────────
  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  String _hms(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  String _hhmm(String hms) => hms.length >= 5 ? hms.substring(0, 5) : hms;
  String _label(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Map<int, List<AvailabilityRule>> get _rulesByDay {
    final map = {for (var d = 0; d < 7; d++) d: <AvailabilityRule>[]};
    for (final r in _rules) {
      if (r.dayOfWeek >= 0 && r.dayOfWeek <= 6) map[r.dayOfWeek]!.add(r);
    }
    return map;
  }

  // ── mutations ──────────────────────────────────────────────────────
  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (ok != null) AppToast.success(ok);
      await _load();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } catch (_) {
      AppToast.error('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addRuleForDay(int day, TimeOfDay start, TimeOfDay end) async {
    if (_toMinutes(start) >= _toMinutes(end)) {
      AppToast.error('End must be after start');
      return;
    }
    await _run(
      () => _repo.createAvailabilityRule({
        'ownerType': 'worker',
        'ownerId': _workerId,
        'dayOfWeek': day,
        'startTime': _hms(start),
        'endTime': _hms(end),
        'isActive': true,
      }),
      ok: 'Added shift for ${_dayLong[day]}',
    );
  }

  Future<void> _bulkAdd() async {
    if (_bulkDays.isEmpty) {
      AppToast.error('Pick at least one day');
      return;
    }
    if (_toMinutes(_bulkStart) >= _toMinutes(_bulkEnd)) {
      AppToast.error('End must be after start');
      return;
    }
    final days = _bulkDays.toList()..sort();
    await _run(
      () async {
        for (final d in days) {
          await _repo.createAvailabilityRule({
            'ownerType': 'worker',
            'ownerId': _workerId,
            'dayOfWeek': d,
            'startTime': _hms(_bulkStart),
            'endTime': _hms(_bulkEnd),
            'isActive': true,
          });
        }
      },
      ok: 'Added ${days.length} shift${days.length > 1 ? 's' : ''}',
    );
  }

  Future<void> _deleteRule(int id) async {
    final ok = await _confirm('Remove this shift?');
    if (ok != true) return;
    await _run(() => _repo.deleteAvailabilityRule(id), ok: 'Shift removed');
  }

  Future<void> _addException() async {
    if (_exDate == null) {
      AppToast.error('Pick a date');
      return;
    }
    if (_exStart != null &&
        _exEnd != null &&
        _toMinutes(_exStart!) >= _toMinutes(_exEnd!)) {
      AppToast.error('End must be after start');
      return;
    }
    final reason = _exReason.text.trim();
    await _run(
      () => _repo.createAvailabilityException({
        'ownerType': 'worker',
        'ownerId': _workerId,
        'date': _fmtDate(_exDate!),
        'type': _exType,
        'startTime': _exStart == null ? null : _hms(_exStart!),
        'endTime': _exEnd == null ? null : _hms(_exEnd!),
        'reason': reason.isEmpty ? null : reason,
      }),
      ok: _exType == 'off' ? 'Leave added' : 'Extra shift added',
    );
    if (!mounted) return;
    setState(() {
      _exDate = null;
      _exStart = null;
      _exEnd = null;
      _exReason.clear();
    });
  }

  Future<void> _deleteException(int id) async {
    final ok = await _confirm('Remove this exception?');
    if (ok != true) return;
    await _run(() => _repo.deleteAvailabilityException(id), ok: 'Removed');
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.rose),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

  Future<TimeOfDay?> _pickTime(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  // ── build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final w = widget.worker;
    final header = Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
      child: Row(
        children: [
          IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to workers'),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Schedule — ${w.name.isEmpty ? 'Worker #${w.id}' : w.name}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
                Text('Recurring shifts + leaves / exceptions',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        header,
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const LoadingList(height: 64)
              : _error
                  ? ErrorRetry(
                      message: "Couldn't load schedule.", onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _statCards(),
                          const SizedBox(height: 18),
                          _weeklyShiftsSection(),
                          const SizedBox(height: 18),
                          _bulkAddSection(),
                          const SizedBox(height: 22),
                          _exceptionsSection(),
                          const SizedBox(height: 8),
                          _addExceptionForm(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _statCards() {
    final activeShifts = _rules.length;
    final upcomingLeaves = _exceptions.where((e) => e.isOff).length;
    Widget card(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        );
    return Row(children: [
      card('Active shifts', '$activeShifts'),
      const SizedBox(width: 10),
      card('Upcoming leaves', '$upcomingLeaves'),
    ]);
  }

  // ── Weekly shifts ──────────────────────────────────────────────────
  Widget _weeklyShiftsSection() {
    final byDay = _rulesByDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(Icons.access_time_rounded, 'Weekly shifts'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              for (var d = 0; d < 7; d++) ...[
                if (d > 0) Divider(height: 1, color: AppColors.border),
                _dayRow(d, byDay[d]!),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tip: add multiple shifts on a day to model a split day — '
          'e.g. 09:00–12:00 + 14:00–18:00.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _dayRow(int day, List<AvailabilityRule> shifts) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(_dayLong[day],
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          Expanded(
            child: shifts.isEmpty
                ? Text('— off —',
                    style: TextStyle(
                        color: AppColors.textFaint,
                        fontStyle: FontStyle.italic,
                        fontSize: 12.5))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final s in shifts) _shiftChip(s)],
                  ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _busy ? null : () => _openDayAdd(day, shifts),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.brand700,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add, size: 16),
            label: Text(shifts.isEmpty ? 'Add shift' : 'Add another',
                style: const TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _shiftChip(AvailabilityRule s) => Container(
        padding: const EdgeInsets.only(left: 8, right: 4, top: 3, bottom: 3),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${_hhmm(s.startTime)} – ${_hhmm(s.endTime)}',
                style: const TextStyle(
                    color: AppColors.brand700,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            InkWell(
              onTap: _busy ? null : () => _deleteRule(s.id),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child:
                    Icon(Icons.close, size: 13, color: AppColors.brand700),
              ),
            ),
          ],
        ),
      );

  /// Per-day inline add — opens a small bottom sheet seeded after the day's
  /// last shift, so adding a split-day second window is one tap + tweak.
  Future<void> _openDayAdd(int day, List<AvailabilityRule> existing) async {
    var start = const TimeOfDay(hour: 9, minute: 0);
    var end = const TimeOfDay(hour: 17, minute: 0);
    if (existing.isNotEmpty) {
      final lastEnd = existing.last.endTime;
      final parts = lastEnd.split(':');
      final h = int.tryParse(parts[0]) ?? 9;
      final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      start = TimeOfDay(hour: h.clamp(0, 23), minute: m);
      end = TimeOfDay(hour: (h + 1).clamp(0, 23), minute: m);
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add shift — ${_dayLong[day]}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _timeField('From', _label(start), () async {
                      final t = await _pickTime(start);
                      if (t != null) setSheet(() => start = t);
                    }),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _timeField('To', _label(end), () async {
                      final t = await _pickTime(end);
                      if (t != null) setSheet(() => end = t);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _addRuleForDay(day, start, end);
                  },
                  child: const Text('Add shift'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bulk add ───────────────────────────────────────────────────────
  Widget _bulkAddSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('BULK ADD — SAME HOURS ACROSS MULTIPLE DAYS',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var d = 0; d < 7; d++) _dayToggle(d),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              _preset('Mon–Fri', {1, 2, 3, 4, 5}),
              _preset('Mon–Sat', {1, 2, 3, 4, 5, 6}),
              _preset('All week', {0, 1, 2, 3, 4, 5, 6}),
              _preset('Clear', const {}, danger: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _timeField('From', _label(_bulkStart), () async {
                  final t = await _pickTime(_bulkStart);
                  if (t != null) setState(() => _bulkStart = t);
                }),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timeField('To', _label(_bulkEnd), () async {
                  final t = await _pickTime(_bulkEnd);
                  if (t != null) setState(() => _bulkEnd = t);
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: (_busy || _bulkDays.isEmpty) ? null : _bulkAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add shift'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayToggle(int d) {
    final active = _bulkDays.contains(d);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() =>
          active ? _bulkDays.remove(d) : _bulkDays.add(d)),
      child: Container(
        width: 44,
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.brand600 : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: active ? AppColors.brand600 : AppColors.border),
        ),
        child: Text(_dayShort[d],
            style: TextStyle(
                color: active ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 11.5)),
      ),
    );
  }

  Widget _preset(String label, Set<int> days, {bool danger = false}) =>
      InkWell(
        onTap: () => setState(() {
          _bulkDays
            ..clear()
            ..addAll(days);
        }),
        child: Text(label,
            style: TextStyle(
                color: danger ? AppColors.rose : AppColors.brand700,
                fontWeight: FontWeight.w700,
                fontSize: 12)),
      );

  // ── Exceptions ─────────────────────────────────────────────────────
  Widget _exceptionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            Icons.event_note_rounded, 'Leaves & one-off changes (next 90 days)'),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: _exceptions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text('No leaves or one-off changes scheduled.',
                        style: TextStyle(
                            color: AppColors.textFaint,
                            fontStyle: FontStyle.italic,
                            fontSize: 12.5)),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < _exceptions.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: AppColors.border),
                      _exceptionRow(_exceptions[i]),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _exceptionRow(AvailabilityException ex) {
    final window = ex.isWholeDay
        ? 'Whole day'
        : '${_hhmm(ex.startTime ?? '')} – ${_hhmm(ex.endTime ?? '')}';
    final (bg, fg) = ex.isOff
        ? (const Color(0xFFFFE4E6), AppColors.rose)
        : (AppColors.brand50, AppColors.brand700);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(ex.date,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(ex.isOff ? 'Off / Leave' : 'Extra shift',
                          style: TextStyle(
                              color: fg,
                              fontWeight: FontWeight.w700,
                              fontSize: 10.5)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  ex.reason.isEmpty ? window : '$window · ${ex.reason}',
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _busy ? null : () => _deleteException(ex.id),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(Icons.delete_outline,
                  size: 18, color: AppColors.textFaint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addExceptionForm() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ADD A LEAVE / ONE-OFF CHANGE',
              style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _timeField(
                  'Date',
                  _exDate == null
                      ? 'Pick a date'
                      : _fmtDate(_exDate!),
                  () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _exDate ?? now,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _exDate = d);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _typeField()),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _timeField(
                  'Start (optional)',
                  _exStart == null ? 'Whole day' : _label(_exStart!),
                  () async {
                    final t = await _pickTime(
                        _exStart ?? const TimeOfDay(hour: 9, minute: 0));
                    if (t != null) setState(() => _exStart = t);
                  },
                  onClear:
                      _exStart == null ? null : () => setState(() => _exStart = null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timeField(
                  'End (optional)',
                  _exEnd == null ? 'Whole day' : _label(_exEnd!),
                  () async {
                    final t = await _pickTime(
                        _exEnd ?? const TimeOfDay(hour: 17, minute: 0));
                    if (t != null) setState(() => _exEnd = t);
                  },
                  onClear:
                      _exEnd == null ? null : () => setState(() => _exEnd = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _exReason,
            decoration: const InputDecoration(
              labelText: 'Reason',
              hintText: 'e.g. sick, vacation, public holiday',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Leave start/end blank for a whole-day off; set a window for '
            'partial-day blocks.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: (_busy || _exDate == null) ? null : _addException,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type',
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _exType,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'off', child: Text('Off / Leave')),
                DropdownMenuItem(value: 'extra', child: Text('Extra shift')),
              ],
              onChanged: (v) => setState(() => _exType = v ?? 'off'),
            ),
          ),
        ),
      ],
    );
  }

  // ── small shared widgets ───────────────────────────────────────────
  Widget _sectionTitle(IconData icon, String title) => Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Text(title.toUpperCase(),
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
          ),
        ],
      );

  Widget _timeField(String label, String value, VoidCallback onTap,
      {VoidCallback? onClear}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    child: Icon(Icons.close,
                        size: 15, color: AppColors.textFaint),
                  )
                else
                  Icon(Icons.keyboard_arrow_down,
                      size: 18, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
