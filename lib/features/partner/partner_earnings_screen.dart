import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'deposit_sheet.dart';
import 'wallet_balance_alert.dart';
import 'partner_models.dart';
import 'partner_repository.dart';
import 'withdraw_sheet.dart';

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
  bool _exporting = false;

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
      repo
          .myCashRequests(type: 'withdraw')
          .catchError((_) => <PartnerCashRequest>[]),
      repo.myDeposits().catchError((_) => <PartnerDepositRow>[]),
    ]);
    return _Earn(
      statement: results[0] as WalletStatement,
      bookings: results[1] as List<PartnerBooking>,
      requests: results[2] as List<PartnerCashRequest>,
      deposits: results[3] as List<PartnerDepositRow>,
    );
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
      appBar: MainAppBar('Earnings', actions: [
        IconButton(
          tooltip: 'Export settlements (CSV)',
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.brand600),
                )
              : const Icon(Icons.file_download_outlined),
          onPressed: _exporting ? null : _exportCsv,
        ),
      ]),
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
    // Customer tips credited this period — 100% to the partner, no commission
    // (web parity: derives the tips card from `type=='tip'` ledger rows).
    final tips = txns
        .where((t) => t.type == 'tip' && _inRange(t.createdAt))
        .fold<double>(0, (s, t) => s + t.amount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        WalletBalanceAlert(balance: w.balance),
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
        if (tips > 0) ...[
          const SizedBox(height: 12),
          _stat('Tips received (period)',
              'AED ${tips.toStringAsFixed(2)}',
              Icons.volunteer_activism_outlined),
        ],
        // Above the tabs: only a compact "you have a request pending" banner.
        // The full history (and the Cancel action) lives in the Withdrawals tab,
        // so this section stops duplicating it.
        ..._pendingWithdrawBanner(e.requests),
        const SizedBox(height: 16),
        _dateFilterBar(),
        const SizedBox(height: 12),
        _tabs(
          pending.length + upcomingBookings.length,
          settled.length,
          _visibleDeposits(e.deposits).length,
          e.requests.length,
        ),
        const SizedBox(height: 12),
        if (_tab == 'upcoming')
          ..._upcomingList(pending, upcomingBookings, bMap)
        else if (_tab == 'settled')
          ..._settledList(settled, bMap)
        else if (_tab == 'deposits')
          ..._depositsList(e.deposits)
        else
          ..._withdrawalsList(e.requests),
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
            // Funds locked by a pending withdraw request. Already subtracted
            // from `balance` server-side, so it is not double-counted here.
            if (w.heldBalance > 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 13, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text('AED ${w.heldBalance.toStringAsFixed(2)} on hold',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
                'Lifetime earned AED ${w.lifetimeEarnings.toStringAsFixed(0)} · '
                'paid out AED ${w.lifetimePaidOut.toStringAsFixed(0)}',
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11.5)),
            const SizedBox(height: 14),
            _withdrawButton(w),
          ],
        ),
      );

  // ---------------- Withdraw ----------------

  /// The button is disabled, with a reason, rather than hidden — a partner who
  /// can't withdraw should be told why. The server enforces both rules anyway
  /// (`WALLET_FROZEN` 409, `INSUFFICIENT_BALANCE` 400).
  Widget _withdrawButton(WalletInfo w) {
    // Withdrawal needs available balance and an unfrozen wallet; a deposit is
    // always allowed (topping up a frozen wallet is fine — only withdrawing
    // from it is paused).
    final blocked = w.isFrozen || w.balance <= 0;
    final reason = w.isFrozen
        ? (w.frozenReason.isEmpty
            ? 'Your wallet is frozen.'
            : 'Frozen: ${w.frozenReason}')
        : 'No available balance to withdraw.';

    final btnStyle = ElevatedButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: AppColors.brand700,
      disabledBackgroundColor: Colors.white24,
      disabledForegroundColor: Colors.white60,
      elevation: 0,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openDeposit,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add funds'),
                style: btnStyle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: blocked ? null : () => _openWithdraw(w.balance),
                icon: const Icon(Icons.south_rounded, size: 16),
                label: const Text('Withdraw'),
                style: btnStyle,
              ),
            ),
          ],
        ),
        if (blocked) ...[
          const SizedBox(height: 6),
          Text(reason,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        ],
      ],
    );
  }

  Future<void> _openWithdraw(double available) async {
    final submitted =
        await showWithdrawSheet(context, availableBalance: available);
    // The hold is already applied server-side, so the wallet is stale.
    if (submitted) await _refresh();
  }

  Future<void> _openDeposit() async {
    final added = await showDepositSheet(context);
    // The callback credited the wallet server-side, so refresh to show it.
    if (added) await _refresh();
  }

  Future<void> _cancelRequest(PartnerCashRequest r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel withdraw request?'),
        content: Text(
          'AED ${r.amount.toStringAsFixed(2)} will be released back to your '
          'available balance.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.rose),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(partnerRepositoryProvider).cancelCashRequest(r.id);
      AppToast.success('Request cancelled — funds released.');
      await _refresh();
    } on ApiException catch (e) {
      // 409 NOT_PENDING: an admin decided it while this screen was open.
      AppToast.error(e.message);
      await _refresh();
    } catch (_) {
      AppToast.error('Could not cancel the request.');
    }
  }

  /// Compact "you have a withdrawal in review" banner. Only PENDING requests
  /// belong above the tabs — the full history and the Cancel action now live in
  /// the Withdrawals tab, so this no longer duplicates the whole list.
  ///
  /// Tapping it jumps to that tab.
  List<Widget> _pendingWithdrawBanner(List<PartnerCashRequest> requests) {
    final pending = requests
        .where((r) => r.status.toLowerCase() == 'pending')
        .toList();
    if (pending.isEmpty) return const [];

    final total = pending.fold<double>(0, (s, r) => s + r.amount);
    final one = pending.length == 1;

    return [
      const SizedBox(height: 16),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _tab = 'withdrawals'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.amber.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: AppColors.amber.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              const Icon(Icons.hourglass_top_rounded,
                  size: 20, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      one
                          ? 'Withdrawal in review'
                          : '${pending.length} withdrawals in review',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AED ${total.toStringAsFixed(2)} on hold until an admin '
                      'decides.',
                      style: const TextStyle(
                          fontSize: 11.5, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.amber),
            ],
          ),
        ),
      ),
    ];
  }

  /// Withdrawals tab — the FULL request history (pending, approved, rejected,
  /// cancelled), each with its Cancel action while it is still cancellable.
  List<Widget> _withdrawalsList(List<PartnerCashRequest> requests) {
    if (requests.isEmpty) {
      return [
        const SizedBox(height: 28),
        Center(
          child: Column(
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 38, color: AppColors.textMuted.withValues(alpha: 0.6)),
              const SizedBox(height: 10),
              const Text('No withdrawal requests yet',
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Use Withdraw above to move your available balance to your bank.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: Colors.black54),
              ),
            ],
          ),
        ),
      ];
    }
    return [for (final r in requests) _requestCard(r)];
  }

  Widget _requestCard(PartnerCashRequest r) {
    final (bg, fg) = switch (r.status.toLowerCase()) {
      'pending' => (AppColors.amber.withValues(alpha: 0.12), AppColors.amber),
      'approved' => (
          AppColors.emerald.withValues(alpha: 0.12),
          AppColors.emerald
        ),
      'rejected' => (AppColors.rose.withValues(alpha: 0.12), AppColors.rose),
      _ => (Colors.black12, Colors.black54),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(999)),
                child: Text(r.status.toUpperCase(),
                    style: TextStyle(
                        color: fg, fontSize: 10, fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              Text('AED ${r.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          if (r.bankName.isNotEmpty || r.bankAccountNumber.isNotEmpty)
            Text(
              [r.bankName, r.bankAccountNumber]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          if (r.rejectionReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Rejected: ${r.rejectionReason}',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.rose)),
            ),
          if (r.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                DateFormat('d MMM y · h:mm a').format(r.createdAt!),
                style: const TextStyle(fontSize: 11.5, color: Colors.black45),
              ),
            ),
          if (r.canCancel) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _cancelRequest(r),
                icon: const Icon(Icons.close_rounded, size: 15),
                label: const Text('Cancel'),
                style: TextButton.styleFrom(foregroundColor: AppColors.rose),
              ),
            ),
          ],
        ],
      ),
    );
  }

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

  // ---------------- CSV export ----------------

  /// Downloads the settlement CSV for the current date range and hands it to
  /// the OS share sheet — the mobile equivalent of the portal's file download
  /// (the same columns and rows; the server scopes it to this partner).
  Future<void> _exportCsv() async {
    setState(() => _exporting = true);
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      // Both bounds or neither — the endpoint 400s on a half-open range.
      final from = _range == null ? null : fmt.format(_range!.start);
      final to = _range == null ? null : fmt.format(_range!.end);

      final csv = await ref
          .read(partnerRepositoryProvider)
          .settlementCsv(from: from, to: to);

      if (csv.trim().isEmpty) {
        if (mounted) AppToast.error('Nothing to export for this range.');
        return;
      }

      final label = _range == null
          ? 'all'
          : '${fmt.format(_range!.start)}_${fmt.format(_range!.end)}';
      final file = File(
          '${(await getTemporaryDirectory()).path}/settlements_$label.csv');
      await file.writeAsString(csv);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'CNC settlements',
      );
    } on ApiException catch (e) {
      if (mounted) AppToast.error(e.message);
    } catch (_) {
      if (mounted) AppToast.error('Could not export settlements.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------- Tabs ----------------
  Widget _tabs(int upcomingCount, int settledCount, int depositsCount,
      int withdrawalsCount) {
    // All four segments must be VISIBLE. Laying them out side by side as
    // "Label (n)" doesn't fit on a phone, and the previous fix — letting the
    // strip scroll — just hid Withdrawals off the right edge with no hint that
    // anything was there. A tab you can't see is a tab that doesn't exist.
    //
    // Stacking the count over the label makes each segment narrow enough that
    // four fit as equal columns, so nothing is off-screen and nothing scrolls.
    Widget seg(String val, String label, int count) {
      final on = _tab == val;
      final fg = on ? Colors.white : AppColors.textMuted;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = val),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
            decoration: BoxDecoration(
              color: on ? AppColors.brand600 : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$count',
                    maxLines: 1,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: fg)),
                const SizedBox(height: 1),
                // Shrink rather than ellipsise, so "Withdrawals" stays readable
                // at any width or text scale.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: fg)),
                ),
              ],
            ),
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
          const SizedBox(width: 4),
          seg('deposits', 'Deposits', depositsCount),
          const SizedBox(width: 4),
          seg('withdrawals', 'Withdrawals', withdrawalsCount),
        ],
      ),
    );
  }

  // ---------------- Deposits list ----------------
  // Web hides pending/abandoned checkout rows and labels the rest
  // Credited / Failed / Refunded — match that.
  List<PartnerDepositRow> _visibleDeposits(List<PartnerDepositRow> all) =>
      all.where((d) => d.status.toLowerCase() != 'pending').toList();

  String _depositStatusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'approved':
        return 'Credited';
      case 'failed':
      case 'rejected':
        return 'Failed';
      case 'refunded':
        return 'Refunded';
      default:
        return s.toUpperCase();
    }
  }

  List<Widget> _depositsList(List<PartnerDepositRow> allDeposits) {
    final deposits = _visibleDeposits(allDeposits);
    if (deposits.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No deposits yet',
              subtitle: 'Top-ups you make to your wallet will appear here.'),
        ),
      ];
    }
    final df = DateFormat('d MMM y, h:mm a');
    Color statusColor(String s) {
      switch (s.toLowerCase()) {
        case 'approved':
          return AppColors.brand600;
        case 'pending':
          return AppColors.amber;
        default:
          return AppColors.rose;
      }
    }

    return [
      for (final d in deposits)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
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
                child: Icon(
                    d.paymentMethod == 'apple_pay'
                        ? Icons.apple
                        : Icons.credit_card,
                    size: 18,
                    color: AppColors.brand700),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${d.currency} ${d.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(
                      [
                        d.paymentMethod == 'apple_pay' ? 'Apple Pay' : 'Card',
                        if (d.createdAt != null) df.format(d.createdAt!),
                      ].join('  ·  '),
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor(d.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_depositStatusLabel(d.status).toUpperCase(),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor(d.status))),
              ),
            ],
          ),
        ),
    ];
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
    'tip': 'Customer tip',
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
      case 'tip':
        return 'A customer tip — 100% yours, no commission.';
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
      case 'tip':
        return 'tip';
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

  /// The partner's own cash requests, withdraw-only. New deposits go through
  /// the payment gateway now (the submit route rejects them with
  /// USE_HYPERPAY_DEPOSIT), so the portal filters deposit rows out and so
  /// do we — historical deposit rows would otherwise be uncancellable clutter.
  final List<PartnerCashRequest> requests;

  /// Wallet top-ups (HyperPay) — history for the Deposits tab.
  final List<PartnerDepositRow> deposits;

  _Earn({
    required this.statement,
    required this.bookings,
    this.requests = const [],
    this.deposits = const [],
  });
}
