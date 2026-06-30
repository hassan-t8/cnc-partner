import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerEarningsScreen extends ConsumerStatefulWidget {
  const PartnerEarningsScreen({super.key});
  @override
  ConsumerState<PartnerEarningsScreen> createState() =>
      _PartnerEarningsScreenState();
}

class _PartnerEarningsScreenState extends ConsumerState<PartnerEarningsScreen> {
  _Earn? _data;
  bool _loading = true;
  bool _error = false;
  String _tab = 'upcoming'; // upcoming | settled
  DateTimeRange? _range; // null = all time

  // Dispatch statuses that count as "money still coming".
  static const _upcomingStatuses = {
    'awaiting_acceptance',
    'pending_acceptance',
    'pending_dispatch',
    'accepted',
    'in_progress',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<_Earn> _fetch() async {
    final repo = ref.read(partnerRepositoryProvider);
    final partnerId = ref.read(authControllerProvider).user?.partnerId ?? 0;
    final results = await Future.wait([
      repo.wallet(partnerId).catchError((_) => const WalletStatement()),
      repo.bookings().catchError((_) => <PartnerBooking>[]),
    ]);
    return _Earn(
        statement: results[0] as WalletStatement,
        bookings: results[1] as List<PartnerBooking>);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final d = await _fetch();
      if (!mounted) return;
      setState(() {
        _data = d;
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

  Future<void> _refresh() async {
    try {
      final d = await _fetch();
      if (mounted) setState(() {
        _data = d;
        _error = false;
      });
    } catch (_) {
      if (mounted && _data == null) setState(() => _error = true);
    }
  }

  bool _inRange(DateTime? d) {
    if (_range == null) return true;
    if (d == null) return false;
    final day = DateUtils.dateOnly(d);
    return !day.isBefore(_range!.start) && !day.isAfter(_range!.end);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tabRefreshProvider, (_, __) => _load());
    return Scaffold(
      appBar: const MainAppBar('Earnings'),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _loading
            ? const LoadingList(height: 110)
            : (_error && _data == null)
                ? ListView(children: [
                    const SizedBox(height: 60),
                    ErrorRetry(
                        message: 'Couldn\'t load earnings.', onRetry: _load),
                  ])
                : _content(),
      ),
    );
  }

  Widget _content() {
    final e = _data!;
    final w = e.statement.wallet;
    final txns = e.statement.transactions;
    // Look up a booking (for its alphanumeric ref + service/customer) from a
    // transaction's numeric bookingId.
    final bMap = {for (final b in e.bookings) b.id: b};

    final pending =
        txns.where((t) => t.isPendingClearance && _inRange(t.createdAt)).toList()
          ..sort((a, b) => (a.clearedAt ?? a.createdAt ?? DateTime(2100))
              .compareTo(b.clearedAt ?? b.createdAt ?? DateTime(2100)));
    final upcomingBookings = e.bookings
        .where((b) =>
            _upcomingStatuses.contains(b.status) && _inRange(b.scheduledStart))
        .toList()
      ..sort((a, b) => (a.scheduledStart ?? DateTime(2100))
          .compareTo(b.scheduledStart ?? DateTime(2100)));
    final settled = txns
        .where((t) =>
            (t.status == 'completed' || t.status == 'reversed') &&
            _inRange(t.createdAt))
        .toList()
      ..sort((a, b) => (b.createdAt ?? DateTime(0))
          .compareTo(a.createdAt ?? DateTime(0)));

    final completed = e.bookings.where((b) => b.status == 'completed').length;
    // Physical cash collected at the door this period — canonical source is the
    // informational `cash_collected` ledger row (incl-VAT), per web parity.
    final cashCollected = txns
        .where((t) => t.type == 'cash_collected' && _inRange(t.createdAt))
        .fold<double>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _walletCard(w),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _stat('Completed', '$completed',
                    Icons.check_circle_outline)),
            const SizedBox(width: 12),
            Expanded(
                child: _stat(
                    'Pending',
                    'AED ${w.pendingBalance.toStringAsFixed(0)}',
                    Icons.hourglass_bottom_outlined)),
          ],
        ),
        if (cashCollected > 0) ...[
          const SizedBox(height: 12),
          _stat('Cash collected (period)',
              'AED ${cashCollected.toStringAsFixed(2)}', Icons.payments_outlined),
        ],
        const SizedBox(height: 16),
        _dateFilterBar(),
        const SizedBox(height: 12),
        _tabs(pending.length + upcomingBookings.length, settled.length),
        const SizedBox(height: 12),
        if (_tab == 'upcoming')
          ..._upcomingList(pending, upcomingBookings, bMap)
        else
          ..._settledList(settled, bMap),
        const SizedBox(height: 8),
      ],
    );
  }

  // ---------------- Wallet + stats ----------------
  Widget _walletCard(WalletInfo w) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.brand700, AppColors.brand500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Wallet balance',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text('AED ${w.balance.toStringAsFixed(2)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900)),
            if (w.pendingBalance > 0) ...[
              const SizedBox(height: 6),
              Text('AED ${w.pendingBalance.toStringAsFixed(2)} pending clearance',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 8),
            Text(
                'Lifetime earned AED ${w.lifetimeEarnings.toStringAsFixed(0)} · '
                'paid out AED ${w.lifetimePaidOut.toStringAsFixed(0)}',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11.5)),
          ],
        ),
      );

  Widget _stat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.brand600, size: 20),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );

  // ---------------- Date filter ----------------
  Widget _dateFilterBar() {
    final hasRange = _range != null;
    final label = hasRange
        ? '${DateFormat('d MMM').format(_range!.start)} – ${DateFormat('d MMM').format(_range!.end)}'
        : 'All time';
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickRange,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppColors.brand600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  Icon(Icons.keyboard_arrow_down, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
        ),
        if (hasRange) ...[
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _range = null),
          ),
        ],
      ],
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = DateTimeRange(
          start: DateUtils.dateOnly(picked.start),
          end: DateUtils.dateOnly(picked.end)));
    }
  }

  // ---------------- Tabs ----------------
  Widget _tabs(int upcomingCount, int settledCount) {
    Widget seg(String val, String label, int count) {
      final on = _tab == val;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = val),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppColors.brand600 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$label ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : AppColors.textMuted)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          seg('upcoming', 'Upcoming', upcomingCount),
          const SizedBox(width: 4),
          seg('settled', 'Settled', settledCount),
        ],
      ),
    );
  }

  // ---------------- Upcoming list ----------------
  // Columns (web): Booking · Service/Customer · Status · Clears in · Amount.
  /// The alphanumeric booking ref ("CNC-B-…") for a transaction, resolved via
  /// its numeric bookingId; falls back to '#<number>'.
  String _refFor(WalletTransaction t, Map<int, PartnerBooking> bMap) {
    final id = int.tryParse(t.bookingRef ?? '');
    final b = id == null ? null : bMap[id];
    if (b != null && b.ref.isNotEmpty) return b.ref;
    return t.bookingRef != null ? '#${t.bookingRef}' : '—';
  }

  List<Widget> _upcomingList(List<WalletTransaction> pending,
      List<PartnerBooking> bookings, Map<int, PartnerBooking> bMap) {
    if (pending.isEmpty && bookings.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: EmptyState(
              icon: Icons.hourglass_empty_rounded,
              title: 'Nothing upcoming',
              subtitle: 'Money still coming will appear here.'),
        )
      ];
    }
    return [
      // Earnings awaiting clearance (have a "clears in" countdown).
      for (final t in pending)
        _upcomingRow(
          ref: _refFor(t, bMap),
          title: () {
            final b = bMap[int.tryParse(t.bookingRef ?? '')];
            final svcName = (b?.serviceName ?? '').trim();
            final parts = [
              if (svcName.isNotEmpty) ServiceTitle.specific(svcName),
              if ((b?.customerName ?? '').isNotEmpty) b!.customerName,
            ];
            return parts.isNotEmpty ? parts.join(' · ') : _settledTitle(t);
          }(),
          statusText: 'Pending clearance',
          statusColor: AppColors.amber,
          clearsIn: _clearsIn(t.clearedAt),
          amount: t.amount,
        ),
      // Jobs not yet completed — show the scheduled date (web parity).
      for (final b in bookings)
        _upcomingRow(
          ref: b.ref.isNotEmpty ? b.ref : '#${b.id}',
          title: [ServiceTitle.specific(b.serviceName), b.customerName]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          statusBadge: StatusBadge(b.status),
          clearsIn: b.scheduledStart != null
              ? DateFormat('d MMM · h:mm a').format(b.scheduledStart!)
              : 'Scheduled',
          amount: b.partnerCost,
        ),
    ];
  }

  Widget _upcomingRow({
    required String ref,
    required String title,
    String? statusText,
    Color? statusColor,
    Widget? statusBadge,
    required String clearsIn,
    required double amount,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                child: Text(ref,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
              Text('AED ${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ],
          ),
          if (title.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              statusBadge ??
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (statusColor ?? AppColors.textMuted)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusText ?? '',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor ?? AppColors.textMuted)),
                  ),
              const Spacer(),
              Icon(Icons.schedule, size: 13, color: AppColors.textFaint),
              const SizedBox(width: 4),
              Text(clearsIn,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }

  String _clearsIn(DateTime? clearedAt) {
    if (clearedAt == null) return 'Soon';
    final diff = clearedAt.difference(DateTime.now());
    if (diff.isNegative) return 'Clearing…';
    if (diff.inDays > 0) return 'in ${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return 'in ${diff.inHours}h';
    return 'in ${diff.inMinutes}m';
  }

  // ---------------- Settled list ----------------
  // Columns (web): Booking · Description · Type · When · Amount.
  List<Widget> _settledList(
      List<WalletTransaction> settled, Map<int, PartnerBooking> bMap) {
    if (settled.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No settled transactions',
              subtitle: 'Cleared earnings and payouts appear here.'),
        )
      ];
    }
    return [for (final t in settled) _settledRow(t, bMap)];
  }

  Widget _settledRow(WalletTransaction t, Map<int, PartnerBooking> bMap) {
    final credit = t.isCredit;
    // cash_collected is INFORMATIONAL — it doesn't move the wallet balance, so
    // render it neutral (no +/- credit/debit styling).
    final info = t.type == 'cash_collected';
    final color = info
        ? AppColors.textMuted
        : (credit ? AppColors.brand600 : AppColors.rose);
    final subtitle = _settledSubtitle(t);
    final when = t.createdAt != null
        ? DateFormat('d MMM y · h:mm a').format(t.createdAt!)
        : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
                info
                    ? Icons.info_outline
                    : (credit
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded),
                color: color,
                size: 18),
          ),
          const SizedBox(width: 12),
          // Description + meta — wraps so every field shows fully.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_settledTitle(t),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                          height: 1.25)),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _pill(Icons.tag, _refFor(t, bMap)),
                    _pill(Icons.category_outlined, _typeLabel(t)),
                    if (when.isNotEmpty) _pill(Icons.schedule, when),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
              info
                  ? 'AED ${t.amount.toStringAsFixed(2)}'
                  : '${credit ? '+' : '−'} AED ${t.amount.toStringAsFixed(2)}',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  decoration:
                      t.isReversed ? TextDecoration.lineThrough : null)),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: AppColors.textMuted),
            const SizedBox(width: 4),
            Text(text,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ],
        ),
      );

  // Friendly title per transaction type — mirrors the backend TYPE_LABELS so
  // the card shows a clean line ("Cash collected from customer") instead of the
  // long raw description.
  static const _titleLabels = {
    'earning': 'Earnings',
    'cash_commission': 'Cash commission to CNC',
    'cash_collected': 'Cash collected from customer',
    'partner_unassign_penalty': 'Unassign penalty',
    'payout': 'Payout to bank',
    'adjustment': 'Manual adjustment',
    'commission': 'Commission',
    'commission_correction': 'Commission correction',
    'reversal': 'Reversal',
  };

  String _settledTitle(WalletTransaction t) {
    if (t.isReversal || t.isReversed) return 'Reversal';
    return _titleLabels[t.type] ??
        (t.type.isEmpty
            ? (t.isCredit ? 'Credit' : 'Debit')
            : t.type
                .replaceAll('_', ' ')
                .replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase()));
  }

  // One short line of context under the title (only where it helps).
  String _settledSubtitle(WalletTransaction t) {
    switch (t.type) {
      case 'cash_collected':
        return 'Physical cash you already hold — not added to your wallet.';
      case 'cash_commission':
        return 'What you owe CNC on the cash you collected.';
      default:
        return '';
    }
  }

  // Short TYPE pill (web: "cash in hand", "commission", …).
  String _typeLabel(WalletTransaction t) {
    if (t.isReversed || t.isReversal || t.type == 'reversal') return 'reversal';
    switch (t.type) {
      case 'earning':
        return 'earnings';
      case 'payout':
        return 'payout';
      case 'adjustment':
        return 'adjustment';
      case 'commission':
      case 'cash_commission':
        return 'commission';
      case 'cash_collected':
        return 'cash in hand';
      default:
        return t.type.isEmpty
            ? (t.isCredit ? 'credit' : 'debit')
            : t.type.replaceAll('_', ' ');
    }
  }
}

class _Earn {
  final WalletStatement statement;
  final List<PartnerBooking> bookings;
  _Earn({required this.statement, required this.bookings});
}
