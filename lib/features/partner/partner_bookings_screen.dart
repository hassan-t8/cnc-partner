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

  Widget _card(PartnerBooking b) {
    final busy = _acting == b.id;
    final time = b.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(b.scheduledStart!)
        : '';
    final actions = <Widget>[];
    if (b.status == 'awaiting_acceptance') {
      actions.add(_btn('Accept', AppColors.brand600,
          busy ? null : () => _act(b, 'accept')));
      actions.add(
          _btn('Decline', AppColors.rose, busy ? null : () => _act(b, 'decline')));
    } else if (b.status == 'accepted') {
      actions.add(
          _btn('Start', AppColors.violet, busy ? null : () => _act(b, 'start')));
    } else if (b.status == 'in_progress') {
      actions.add(_btn('Complete', AppColors.brand600,
          busy ? null : () => _act(b, 'complete')));
    }
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
                child: Text(b.serviceName.isEmpty ? 'Service' : b.serviceName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5)),
              ),
              StatusBadge(b.status),
            ],
          ),
          const SizedBox(height: 3),
          Text(
              [
                if (b.ref.isNotEmpty) '#${b.ref}',
                b.customerName,
                b.area,
                time
              ].where((s) => s.isNotEmpty).join(' · '),
              style:
                  TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (b.partnerCost > 0) ...[
            const SizedBox(height: 4),
            Text('AED ${b.partnerCost.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: AppColors.brand700,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
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
    );
  }

  Widget _btn(String label, Color color, VoidCallback? onTap) => SizedBox(
        height: 40,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}
