import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import 'partner_repository.dart';

/// Weekly working-hours editor for any owner (worker / van / partner).
class AvailabilityEditor extends ConsumerStatefulWidget {
  final String ownerType; // 'worker' | 'van' | 'partner'
  final int ownerId;
  final String title;
  const AvailabilityEditor({
    super.key,
    required this.ownerType,
    required this.ownerId,
    required this.title,
  });

  @override
  ConsumerState<AvailabilityEditor> createState() => _AvailabilityEditorState();
}

class _DayState {
  bool on;
  TimeOfDay start;
  TimeOfDay end;
  int? ruleId; // existing rule id (null = none yet)
  _DayState(this.on, this.start, this.end, this.ruleId);
}

class _AvailabilityEditorState extends ConsumerState<AvailabilityEditor> {
  static const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  late List<_DayState> _state;
  bool _loading = true;
  bool _error = false;
  bool _busy = false;

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _state = List.generate(
        7, (_) => _DayState(false, const TimeOfDay(hour: 9, minute: 0),
            const TimeOfDay(hour: 18, minute: 0), null));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final rules =
          await _repo.availabilityRules(widget.ownerType, widget.ownerId);
      for (final r in rules) {
        if (r.dayOfWeek < 0 || r.dayOfWeek > 6) continue;
        _state[r.dayOfWeek]
          ..on = r.isActive
          ..start = _parse(r.startTime)
          ..end = _parse(r.endTime)
          ..ruleId = r.id;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  TimeOfDay _parse(String hms) {
    final parts = hms.split(':');
    return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0);
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  String _label(TimeOfDay t) {
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> _pick(int i, bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _state[i].start : _state[i].end,
    );
    if (t != null) {
      setState(() => isStart ? _state[i].start = t : (_state[i].end = t));
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      for (var d = 0; d < 7; d++) {
        final s = _state[d];
        if (s.on) {
          final body = {
            'ownerType': widget.ownerType,
            'ownerId': widget.ownerId,
            'dayOfWeek': d,
            'startTime': _fmt(s.start),
            'endTime': _fmt(s.end),
            'isActive': true,
          };
          if (s.ruleId != null) {
            await _repo.updateAvailabilityRule(s.ruleId!, body);
          } else {
            await _repo.createAvailabilityRule(body);
          }
        } else if (s.ruleId != null) {
          await _repo.deleteAvailabilityRule(s.ruleId!);
          s.ruleId = null;
        }
      }
      AppToast.success('Working hours saved');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: MainAppBar(widget.title),
      body: _loading
          ? const LoadingList(height: 64)
          : _error
              ? ErrorRetry(
                  message: 'Couldn\'t load working hours.', onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('Set the days and hours this '
                        '${widget.ownerType} is available.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 12),
                    for (var i = 0; i < 7; i++) _dayRow(i),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : const Text('Save working hours'),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _dayRow(int i) {
    final s = _state[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(_days[i],
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Switch(
            value: s.on,
            activeThumbColor: AppColors.brand600,
            onChanged: (v) => setState(() => s.on = v),
          ),
          const Spacer(),
          if (s.on) ...[
            _timeChip(_label(s.start), () => _pick(i, true)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('–', style: TextStyle(color: AppColors.textMuted)),
            ),
            _timeChip(_label(s.end), () => _pick(i, false)),
          ] else
            Text('Off',
                style: TextStyle(color: AppColors.textFaint, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _timeChip(String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12.5)),
        ),
      );
}
