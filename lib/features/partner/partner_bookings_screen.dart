import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import '../worker/otp_dialog.dart';
import '../../core/auth/auth_controller.dart';
import 'booking_detail_screen.dart';
import 'partner_repository.dart';
import 'unassign_confirm_sheet.dart';

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
  /// Optional initial date filter (e.g. opened from a dashboard KPI).
  final DateTime? initialFrom;
  final DateTime? initialTo;
  const PartnerBookingsScreen({super.key, this.initialFrom, this.initialTo});
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
  double? _penaltyPct; // partner's self-unassign penalty %, fetched lazily
  bool _penaltyLoaded = false;

  // ----- infinite-scroll pagination -----
  static const _pageSize = 30;
  final ScrollController _scroll = ScrollController();
  int _page = 1;
  int _totalRecords = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

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
    _from = widget.initialFrom;
    _to = widget.initialTo;
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  // Append the next page when the user nears the bottom.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) _loadMore();
  }

  // Fresh load (page 1) — resets the accumulated list + pagination.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final res = await ref
          .read(partnerRepositoryProvider)
          .bookingsPage(page: 1, limit: _pageSize);
      if (mounted) {
        setState(() {
          _all = res.rows;
          _page = res.currentPage;
          _totalRecords = res.totalRecords;
          _hasMore = res.hasMore;
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

  // Fetch + append the next page. No-op while a page is in flight, when the
  // list is exhausted, or during the initial/error load.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _error) return;
    setState(() => _loadingMore = true);
    try {
      final next = _page + 1;
      final res = await ref
          .read(partnerRepositoryProvider)
          .bookingsPage(page: next, limit: _pageSize);
      if (!mounted) return;
      // De-dupe defensively in case a new row shifted paging between fetches.
      final seen = {for (final b in _all) b.id};
      final fresh = res.rows.where((b) => !seen.contains(b.id)).toList();
      setState(() {
        _all = [..._all, ...fresh];
        _page = res.currentPage;
        _totalRecords = res.totalRecords;
        _hasMore = res.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
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
        case 'unsign':
          final pct = await _loadPenaltyPct();
          if (!mounted) return;
          final reason = await showUnassignSheet(context,
              bookingRef: b.ref.isNotEmpty ? b.ref : '#${b.id}',
              customerName: b.customerName,
              partnerCost: b.partnerCost,
              penaltyPct: pct);
          if (reason == null) {
            setState(() => _acting = -1);
            return;
          }
          final res = await repo.partnerUnassign(b.id,
              reason: reason,
              clientRequestId:
                  'app-${DateTime.now().microsecondsSinceEpoch}');
          final penalty = res['penalty'];
          final amt = penalty is Map ? penalty['amount'] : null;
          AppToast.success((amt is num && amt > 0)
              ? 'Released — penalty AED ${amt.toStringAsFixed(2)}'
              : 'Booking released');
          break;
        case 'cash':
          final done = await _cashCollectDialog(b);
          if (done != true) {
            setState(() => _acting = -1);
            return;
          }
          await repo.cashCollect(b.id);
          AppToast.success('Cash marked collected');
          break;
        case 'review':
          final r = await _reviewCustomerDialog(b);
          if (r == null) {
            setState(() => _acting = -1);
            return;
          }
          await repo.submitCustomerReview(b.id, r.$1,
              comment: r.$2.isEmpty ? null : r.$2);
          AppToast.success('Review submitted');
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

  /// Lazily fetch (and cache) the partner's self-unassign penalty %, so the
  /// confirm sheet can preview the exact AED penalty.
  Future<double?> _loadPenaltyPct() async {
    if (_penaltyLoaded) return _penaltyPct;
    try {
      final pid = ref.read(authControllerProvider).user?.partnerId;
      if (pid != null) {
        final p = await ref.read(partnerRepositoryProvider).getPartner(pid);
        _penaltyPct = p.unassignPenaltyPct;
      }
    } catch (_) {
      // Leave null — sheet falls back to "no penalty / preview unavailable".
    }
    _penaltyLoaded = true;
    return _penaltyPct;
  }

  Future<(int, String)?> _reviewCustomerDialog(PartnerBooking b) {
    int stars = 0;
    final comment = TextEditingController();
    return showDialog<(int, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
              'Review ${b.customerName.isEmpty ? 'customer' : b.customerName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => setD(() => stars = i),
                      icon: Icon(
                          i <= stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: AppColors.amber,
                          size: 34),
                    ),
                ],
              ),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration:
                    const InputDecoration(hintText: 'Comment (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: stars == 0
                  ? null
                  : () => Navigator.pop(ctx, (stars, comment.text.trim())),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _cashCollectDialog(PartnerBooking b) {
    final notes = TextEditingController();
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collect cash'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm you collected the cash from '
                '${b.customerName.isEmpty ? 'the customer' : b.customerName} '
                'for booking #${b.ref}.'),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(hintText: 'Notes (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark collected'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Live updates: reload when any booking status/dispatch event arrives.
    ref.listen(bookingRealtimeProvider, (_, __) {
      if (mounted) _load();
    });
    // Refetch when the bottom-nav tab is (re)tapped.
    ref.listen(tabRefreshProvider, (_, __) {
      if (mounted) _load();
    });
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
                  return ListView(
                      controller: _scroll,
                      children: const [
                        SizedBox(height: 80),
                        EmptyState(
                            icon: Icons.assignment_outlined,
                            title: 'No bookings match',
                            subtitle: 'Try clearing the filters.'),
                      ]);
                }
                // Trailing slot: a loading spinner while a page is in flight,
                // else a "showing X of Y" footer once everything is loaded.
                return ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) =>
                      i < rows.length ? _card(rows[i]) : _listFooter(rows.length),
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
      actions.add(_btn('Unsign', Icons.undo_rounded, AppColors.rose,
          busy ? null : () => _act(b, 'unsign'), false, outlined: true));
    } else if (b.status == 'in_progress') {
      // Cash bookings must collect cash before completing.
      if (b.cashPending) {
        actions.add(_btn('Collect AED ${b.cashDue.toStringAsFixed(2)}',
            Icons.payments_rounded, AppColors.amber,
            busy ? null : () => _act(b, 'cash'), busy));
      }
      actions.add(_btn('Complete', Icons.check_circle_rounded,
          AppColors.brand600,
          (busy || b.cashPending) ? null : () => _act(b, 'complete'), busy));
    } else if (b.status == 'completed') {
      actions.add(_btn('Review customer', Icons.star_rounded, AppColors.amber,
          busy ? null : () => _act(b, 'review'), false, outlined: true));
    }
    return actions;
  }

  // Trailing list slot: a spinner while the next page loads, a tap-to-load
  // affordance if more remain, else a "showing X of Y" summary. [shownCount]
  // is the number of rows currently visible after client-side filters.
  Widget _listFooter(int shownCount) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4)),
        ),
      );
    }
    // Loaded rows (pre-filter) vs the server total. When filters are active
    // the visible count can be lower; note that in the label for clarity.
    final loaded = _all.length;
    final total = _totalRecords > 0 ? _totalRecords : loaded;
    final filtered = shownCount != loaded;
    final label = filtered
        ? 'Showing $shownCount filtered · $loaded of $total loaded'
        : 'Showing $loaded of $total';
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        children: [
          if (_hasMore)
            TextButton(
              onPressed: _loadMore,
              child: const Text('Load more'),
            ),
          Text(label,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
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
                            ServiceTitle.specific(b.serviceName)),
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
