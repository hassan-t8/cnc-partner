import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import '../worker/otp_dialog.dart';
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
  late Future<List<PartnerBooking>> _future;
  String _query = '';
  String _status = 'all';
  int _acting = -1;

  @override
  void initState() {
    super.initState();
    _future = ref.read(partnerRepositoryProvider).bookings();
  }

  void _reload() => setState(
      () => _future = ref.read(partnerRepositoryProvider).bookings());

  List<PartnerBooking> _filter(List<PartnerBooking> all) {
    final q = _query.toLowerCase();
    return all.where((b) {
      if (_status != 'all' && b.status != _status) return false;
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
      appBar: AppBar(title: const Text('Bookings')),
      body: Column(
        children: [
          _filters(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<PartnerBooking>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const LoadingList();
                  }
                  if (snap.hasError) {
                    return ErrorRetry(
                        message: 'Couldn\'t load bookings.', onRetry: _reload);
                  }
                  final rows = _filter(snap.data ?? const []);
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
                },
              ),
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
              decoration: const InputDecoration(
                hintText: 'Search ref, customer, service…',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
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
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          bottomLeft: Radius.circular(4),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      b.serviceName.isEmpty
                                          ? 'Service'
                                          : b.serviceName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15)),
                                ),
                                StatusBadge(b.status),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _metaRow(Icons.person_outline,
                                b.customerName.isEmpty
                                    ? 'Customer'
                                    : b.customerName),
                            if (b.area.isNotEmpty)
                              _metaRow(Icons.place_outlined, b.area),
                            _metaRow(Icons.schedule_outlined, time),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (b.ref.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: AppColors.bg,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                        border: Border.all(
                                            color: AppColors.border)),
                                    child: Text('#${b.ref}',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textMuted)),
                                  ),
                                const Spacer(),
                                if (b.partnerCost > 0)
                                  Text(
                                      'AED ${b.partnerCost.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                          color: AppColors.brand700,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.textFaint),
            const SizedBox(width: 6),
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

  void _showDetail(PartnerBooking b) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
          final actions = _sheetActions(ctx, b);
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            b.serviceName.isEmpty ? 'Service' : b.serviceName,
                            style: const TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w800)),
                      ),
                      StatusBadge(b.status),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _detailRow(Icons.tag, 'Reference',
                      b.ref.isEmpty ? '—' : '#${b.ref}'),
                  _detailRow(Icons.person_outline, 'Customer',
                      b.customerName.isEmpty ? '—' : b.customerName),
                  _detailRow(Icons.place_outlined, 'Area',
                      b.area.isEmpty ? '—' : b.area),
                  _detailRow(
                      Icons.schedule_outlined,
                      'Scheduled',
                      b.scheduledStart != null
                          ? DateFormat('EEE d MMM y · h:mm a')
                              .format(b.scheduledStart!)
                          : 'Not scheduled'),
                  if (b.paymentStatus.isNotEmpty)
                    _detailRow(Icons.payments_outlined, 'Payment',
                        b.paymentStatus.replaceAll('_', ' ')),
                  _detailRow(Icons.account_balance_wallet_outlined, 'Your payout',
                      'AED ${b.partnerCost.toStringAsFixed(2)}'),
                  if (actions.isNotEmpty) ...[
                    const SizedBox(height: 18),
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
          );
      },
    );
  }

  /// Action buttons for the detail sheet: close the sheet, then run the action.
  List<Widget> _sheetActions(BuildContext ctx, PartnerBooking b) {
    Widget btn(String label, IconData icon, Color color, String action,
            {bool outlined = false}) =>
        _btn(label, icon, color, () {
          Navigator.pop(ctx);
          _act(b, action);
        }, false, outlined: outlined);
    switch (b.status) {
      case 'awaiting_acceptance':
        return [
          btn('Accept', Icons.check_rounded, AppColors.brand600, 'accept'),
          btn('Decline', Icons.close_rounded, AppColors.rose, 'decline',
              outlined: true),
        ];
      case 'accepted':
        return [
          btn('Start job', Icons.play_arrow_rounded, AppColors.violet,
              'start'),
        ];
      case 'in_progress':
        return [
          btn('Complete', Icons.check_circle_rounded, AppColors.brand600,
              'complete'),
        ];
      default:
        return const [];
    }
  }

  Widget _detailRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(label,
                  style: TextStyle(
                      color: AppColors.textMuted, fontSize: 13)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
