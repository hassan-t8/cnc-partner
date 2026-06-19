import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import '../worker/otp_dialog.dart';
import 'booking_detail_screen.dart';
import 'partner_repository.dart';

const _statusOptions = [
  'all',
  'awaiting_acceptance',
  'accepted',
  'in_progress',
  'completed',
  'declined',
  'cancelled',
];

class PartnerBookingsScreen extends ConsumerStatefulWidget {
  const PartnerBookingsScreen({super.key});
  @override
  ConsumerState<PartnerBookingsScreen> createState() =>
      _PartnerBookingsScreenState();
}

class _PartnerBookingsScreenState
    extends ConsumerState<PartnerBookingsScreen> {
  List<PartnerBooking> _all = const [];
  bool _loading = true;
  bool _error = false;
  String _query = '';
  String _status = 'all';
  DateTime? _from;
  DateTime? _to;
  int _acting = -1;

  bool get _hasFilters => _status != 'all' || _from != null || _to != null;
  int get _filterCount =>
      (_status != 'all' ? 1 : 0) + (_from != null ? 1 : 0) + (_to != null ? 1 : 0);

  static const _statusForAction = {
    'accept': 'accepted',
    'decline': 'declined',
    'start': 'in_progress',
    'complete': 'completed',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final list = await ref.read(partnerRepositoryProvider).bookings();
      if (mounted) {
        setState(() {
          _all = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _loading = false;
        });
      }
    }
  }

  void _reload() => _load();

  /// Optimistically update a booking's status in the local list.
  void _patch(int id, String status) {
    final i = _all.indexWhere((b) => b.id == id);
    if (i >= 0) {
      setState(() => _all = [
            for (var k = 0; k < _all.length; k++)
              k == i ? _all[k].copyWith(status: status) : _all[k]
          ]);
    }
  }

  List<PartnerBooking> _filter(List<PartnerBooking> all) {
    final q = _query.toLowerCase();
    return all.where((b) {
      if (_status != 'all' && b.status != _status) return false;
      final d = b.scheduledStart;
      if (_from != null && (d == null || d.isBefore(_from!))) return false;
      if (_to != null &&
          (d == null ||
              d.isAfter(DateTime(_to!.year, _to!.month, _to!.day, 23, 59)))) {
        return false;
      }
      if (q.isEmpty) return true;
      return [b.ref, b.customerName, b.serviceName, b.area]
          .any((s) => s.toLowerCase().contains(q));
    }).toList();
  }

  Future<void> _act(PartnerBooking b, String action) async {
    final repo = ref.read(partnerRepositoryProvider);
    setState(() => _acting = b.id);
    try {
      switch (action) {
        case 'accept':
          await repo.acceptBooking(b.id);
          AppToast.success('Booking accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _acting = -1);
            return;
          }
          await repo.declineBooking(b.id, reason: reason.isEmpty ? null : reason);
          AppToast.success('Booking declined');
          break;
        case 'start':
          try {
            await repo.startBooking(b.id);
          } on ApiException catch (e) {
            if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
              if (!mounted) return;
              final otp = await showOtpDialog(context,
                  bookingRef: '#${b.ref}', customerName: b.customerName);
              if (otp == null) {
                setState(() => _acting = -1);
                return;
              }
              await repo.startBooking(b.id, otp: otp);
            } else {
              rethrow;
            }
          }
          AppToast.success('Booking started');
          break;
        case 'complete':
          await repo.completeBooking(b.id);
          AppToast.success('Booking completed');
          break;
      }
      final newStatus = _statusForAction[action];
      if (newStatus != null) _patch(b.id, newStatus);
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  Future<String?> _reasonDialog() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline booking'),
        content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Reason (optional)')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MainAppBar('Bookings'),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: Builder(builder: (context) {
                if (_loading) return const LoadingList();
                if (_error) {
                  return ErrorRetry(
                      message: 'Couldn\'t load bookings.', onRetry: _reload);
                }
                final rows = _filter(_all);
                if (rows.isEmpty) {
                  return ListView(children: const [
                    SizedBox(height: 80),
                    EmptyState(
                        icon: Icons.assignment_outlined,
                        title: 'No bookings match',
                        subtitle: 'Try clearing the filters.'),
                  ]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _card(rows[i]),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                hintText: 'Search ref, customer, service…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Stack(
                  alignment: Alignment.center,
                  children: [
                    IconButton(
                      onPressed: _openFilterSheet,
                      icon: Icon(Icons.tune,
                          color: _hasFilters
                              ? AppColors.brand600
                              : AppColors.textMuted),
                      tooltip: 'Filters',
                    ),
                    if (_filterCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.brand600,
                              shape: BoxShape.circle),
                          child: Text('$_filterCount',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ],
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _statusOptions.map((s) {
                  final on = _status == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s == 'all' ? 'All' : s.replaceAll('_', ' ')),
                      selected: on,
                      onSelected: (_) => setState(() => _status = s),
                      selectedColor: AppColors.brand600,
                      labelStyle: TextStyle(
                          color: on ? Colors.white : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: AppColors.border),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }).toList(),
              ),
            ),
            if (_from != null || _to != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (_from != null)
                      _appliedChip('From ${_fmt(_from!)}',
                          () => setState(() => _from = null)),
                    if (_to != null)
                      _appliedChip(
                          'To ${_fmt(_to!)}', () => setState(() => _to = null)),
                    _appliedChip('Clear dates',
                        () => setState(() {
                              _from = null;
                              _to = null;
                            }),
                        solid: true),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  String _fmt(DateTime d) => DateFormat('d MMM').format(d);

  Widget _appliedChip(String label, VoidCallback onClear, {bool solid = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onClear,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: solid ? AppColors.rose.withValues(alpha: 0.1)
                  : AppColors.brand50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: solid ? AppColors.rose : AppColors.brand600,
                  width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: solid ? AppColors.rose : AppColors.brand700)),
                const SizedBox(width: 4),
                Icon(Icons.close,
                    size: 13,
                    color: solid ? AppColors.rose : AppColors.brand700),
              ],
            ),
          ),
        ),
      );

  Future<void> _openFilterSheet() async {
    var status = _status;
    DateTime? from = _from;
    DateTime? to = _to;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Filter bookings',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                const Text('Status',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _statusOptions.map((s) {
                    final on = status == s;
                    return ChoiceChip(
                      label: Text(s == 'all' ? 'All' : s.replaceAll('_', ' ')),
                      selected: on,
                      onSelected: (_) => setSheet(() => status = s),
                      selectedColor: AppColors.brand600,
                      labelStyle: TextStyle(
                          color: on ? Colors.white : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      backgroundColor: AppColors.surface,
                      side: BorderSide(color: AppColors.border),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),
                const Text('Date range',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _dateBox('From', from, () async {
                      final d = await _pickDate(ctx, from);
                      if (d != null) setSheet(() => from = d);
                    })),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _dateBox('To', to, () async {
                      final d = await _pickDate(ctx, to);
                      if (d != null) setSheet(() => to = d);
                    })),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheet(() {
                            status = 'all';
                            from = null;
                            to = null;
                          });
                        },
                        child: const Text('Reset'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _status = status;
                              _from = from;
                              _to = to;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Apply filters'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDate(BuildContext ctx, DateTime? initial) => showDatePicker(
        context: ctx,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2024),
        lastDate: DateTime(2030),
      );

  Widget _dateBox(String label, DateTime? value, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_outlined,
                  size: 16, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(value != null ? _fmt(value) : label,
                  style: TextStyle(
                      color: value != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );

  List<Widget> _actionsFor(PartnerBooking b, bool busy) {
    final actions = <Widget>[];
    if (b.status == 'awaiting_acceptance') {
      actions.add(_btn('Accept', Icons.check_rounded, AppColors.brand600,
          busy ? null : () => _act(b, 'accept'), busy));
      actions.add(_btn('Decline', Icons.close_rounded, AppColors.rose,
          busy ? null : () => _act(b, 'decline'), false,
          outlined: true));
    } else if (b.status == 'accepted') {
      actions.add(_btn('Start job', Icons.play_arrow_rounded,
          AppColors.violet, busy ? null : () => _act(b, 'start'), busy));
    } else if (b.status == 'in_progress') {
      actions.add(_btn('Complete', Icons.check_circle_rounded,
          AppColors.brand600, busy ? null : () => _act(b, 'complete'),
          busy));
    }
    return actions;
  }

  Widget _card(PartnerBooking b) {
    final busy = _acting == b.id;
    final (accent, _) = AppColors.dispatchStatus(b.status);
    final time = b.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(b.scheduledStart!)
        : 'Not scheduled';
    final customer = b.customerName.isEmpty ? 'Customer' : b.customerName;
    final actions = _actionsFor(b, busy);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _showDetail(b),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header — customer is the headline (cnc_panel style).
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: AppColors.brand50,
                              child: Text(customer[0].toUpperCase(),
                                  style: const TextStyle(
                                      color: AppColors.brand700,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(customer,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15)),
                                  if (b.ref.isNotEmpty)
                                    Text('#${b.ref}',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            StatusBadge(b.status),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Divider(height: 1, color: AppColors.border),
                        const SizedBox(height: 8),
                        _metaRow(Icons.cleaning_services_outlined,
                            b.serviceName.isEmpty ? 'Service' : b.serviceName),
                        _metaRow(Icons.schedule_outlined, time),
                        if (b.area.isNotEmpty)
                          _metaRow(Icons.place_outlined, b.area),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (b.paymentStatus.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: AppColors.bg,
                                    borderRadius: BorderRadius.circular(20),
                                    border:
                                        Border.all(color: AppColors.border)),
                                child: Text(
                                    b.paymentStatus
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textMuted)),
                              ),
                            const Spacer(),
                            if (b.partnerCost > 0) ...[
                              Text('Payout  ',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textMuted)),
                              Text(
                                  'AED ${b.partnerCost.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      color: AppColors.brand700,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15.5)),
                            ],
                          ],
                        ),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              for (var i = 0; i < actions.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(child: actions[i]),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 7),
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ],
        ),
      );

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap,
          bool busy,
          {bool outlined = false}) =>
      SizedBox(
        height: 42,
        child: outlined
            ? OutlinedButton.icon(
                onPressed: onTap,
                icon: Icon(icon, size: 18, color: color),
                label: Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withValues(alpha: 0.5))),
              )
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: color),
                onPressed: onTap,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                    : Icon(icon, size: 18),
                label: Text(label),
              ),
      );

  Future<void> _showDetail(PartnerBooking b) async {
    final result = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => BookingDetailScreen(booking: b)));
    // Detail returns the new status string after a lifecycle action,
    // 'reload' if only the team changed, or '' on a plain back.
    if (result == null || result.isEmpty) return;
    if (result == 'reload') {
      _reload();
    } else {
      _patch(b.id, result);
      _reload();
    }
  }
}
