import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';
import '../../core/realtime/booking_realtime.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/service_title.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import '../worker/otp_dialog.dart';
import 'assign_team_sheet.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// Full booking detail with the team-assignment flow (assign / unassign) and
/// the accept / start / complete lifecycle. Pops `true` if anything changed.
class BookingDetailScreen extends ConsumerStatefulWidget {
  final PartnerBooking booking;
  const BookingDetailScreen({super.key, required this.booking});
  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late PartnerBooking b;
  List<BookingAssignment>? _team; // null = loading
  bool _teamError = false;
  bool _busy = false; // lifecycle actions only (start / complete / cash)
  final Set<int> _removing = {}; // assignment ids being unassigned
  bool _changed = false;
  // The partner's own review of this booking's customer, once loaded. Non-null
  // when already reviewed → the screen shows the submitted stars/comment.
  Review? _customerReview;

  @override
  void initState() {
    super.initState();
    b = widget.booking;
    _loadTeam();
    if (b.status == 'completed') _loadCustomerReview();
    // Live: join this booking's room for dispatch/assignment updates.
    ref.read(bookingRealtimeProvider.notifier).joinBooking(b.id);
  }

  /// Fetch the partner's existing customer review for this booking so the
  /// detail screen can show it instead of the "Review customer" button.
  Future<void> _loadCustomerReview() async {
    try {
      final r = await _repo.customerReviewFor(b.id);
      if (mounted && r != null) {
        setState(() {
          _customerReview = r;
          b = b.copyWith(customerReviewed: true);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    ref.read(bookingRealtimeProvider.notifier).leaveBooking(b.id);
    super.dispose();
  }

  PartnerRepository get _repo => ref.read(partnerRepositoryProvider);

  /// Re-fetch this booking (no single-booking endpoint, so pull the list and
  /// pick it out) so socket events — payment collected, completed from the web,
  /// status changes — update the header + action buttons live.
  Future<void> _reloadBooking() async {
    try {
      final list = await _repo.bookings();
      final fresh = list.where((x) => x.id == b.id);
      if (fresh.isNotEmpty && mounted) {
        final next = fresh.first;
        if (next.status != b.status ||
            next.cashCollected != b.cashCollected) {
          _changed = true;
        }
        final becameCompleted =
            next.status == 'completed' && b.status != 'completed';
        setState(() => b = next);
        // Just completed (e.g. from the web / another device) → surface any
        // customer review so the review card/CTA reflects the new state.
        if (becameCompleted && _customerReview == null) _loadCustomerReview();
      }
    } catch (_) {}
  }

  Future<void> _loadTeam() async {
    // Only show the skeleton on the FIRST load — on reloads (socket / after
    // assign-unassign) keep the current team visible so it doesn't flash a
    // loader that looks like the job is starting.
    if (_team == null) setState(() => _teamError = false);
    try {
      final list = await _repo.bookingAssignments(b.id);
      if (mounted) setState(() => _team = list);
    } catch (_) {
      if (mounted) {
        setState(() {
          _team ??= const [];
          _teamError = true;
        });
      }
    }
  }

  static const _statusForAction = {
    'accept': 'accepted',
    'decline': 'declined',
    'start': 'in_progress',
    'complete': 'completed',
  };

  // ---- lifecycle ----
  Future<void> _act(String action) async {
    setState(() => _busy = true);
    try {
      switch (action) {
        case 'accept':
          await _repo.acceptBooking(b.id);
          AppToast.success('Booking accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _busy = false);
            return;
          }
          await _repo.declineBooking(b.id,
              reason: reason.isEmpty ? null : reason);
          AppToast.success('Booking declined');
          break;
        case 'start':
          try {
            await _repo.startBooking(b.id);
          } on ApiException catch (e) {
            if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
              if (!mounted) return;
              final otp = await showOtpDialog(context,
                  bookingRef: '#${b.ref}', customerName: b.customerName);
              if (otp == null) {
                setState(() => _busy = false);
                return;
              }
              await _repo.startBooking(b.id, otp: otp);
            } else {
              rethrow;
            }
          }
          AppToast.success('Booking started');
          break;
        case 'complete':
          await _repo.completeBooking(b.id);
          AppToast.success('Booking completed');
          break;
      }
      _changed = true;
      // Return the new status so the list updates optimistically.
      if (mounted) Navigator.pop(context, _statusForAction[action] ?? '');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Collect the cash owed on this booking. Shown for unpaid/partial (and
  /// online-uncaptured) bookings, mirroring the web partner-admin condition.
  /// Confirms (like the web) with an optional notes field before recording.
  Future<void> _collectCash() async {
    final confirmed = await _cashCollectDialog();
    if (confirmed == null) return; // cancelled
    setState(() => _busy = true);
    try {
      await _repo.cashCollect(b.id, notes: confirmed.isEmpty ? null : confirmed);
      if (!mounted) return;
      setState(() {
        b = b.copyWith(cashCollected: true);
        _busy = false;
      });
      _changed = true;
      AppToast.success(b.status == 'in_progress'
          ? 'Cash collected — you can complete the job now'
          : 'Cash marked collected');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Confirm-and-record dialog for collecting cash. Returns the entered notes
  /// (may be empty) on confirm, or null on cancel. Mirrors the web confirm.
  Future<String?> _cashCollectDialog() {
    final notes = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collect cash'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Confirm you received AED ${b.cashDue.toStringAsFixed(2)} in '
                'cash from ${b.customerName.isEmpty ? 'the customer' : b.customerName} '
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
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: () => Navigator.pop(ctx, notes.text.trim()),
            child: const Text('Mark collected'),
          ),
        ],
      ),
    );
  }

  /// Review the booking's customer (optional, post-completion — mirrors the
  /// web). Pre-fills any prior submission; the backend upserts so re-submitting
  /// edits the same row. Stays on the screen and shows the submitted review.
  Future<void> _reviewCustomer() async {
    final r = await _reviewCustomerDialog();
    if (r == null) return;
    setState(() => _busy = true);
    try {
      await _repo.submitCustomerReview(b.id, r.$1,
          comment: r.$2.isEmpty ? null : r.$2);
      if (!mounted) return;
      setState(() {
        _customerReview = Review(
            stars: r.$1.toDouble(),
            comment: r.$2,
            customerName: b.customerName);
        b = b.copyWith(customerReviewed: true);
        _busy = false;
      });
      _changed = true;
      AppToast.success('Review submitted');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(int, String)?> _reviewCustomerDialog() {
    int stars = (_customerReview?.stars ?? 0).round();
    final comment =
        TextEditingController(text: _customerReview?.comment ?? '');
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
                maxLength: 2000,
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
              child: const Text('Submit review'),
            ),
          ],
        ),
      ),
    );
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

  // ---- team ----
  Future<void> _openAssignTeam() async {
    final changed = await showAssignTeamSheet(
      context,
      ref,
      bookingId: b.id,
      ref0: b.ref,
      scheduledStart: b.scheduledStart,
      zoneId: b.zoneId,
    );
    if (changed && mounted) {
      _changed = true;
      _loadTeam();
    }
  }

  Future<void> _unassign(BookingAssignment a) async {
    setState(() => _removing.add(a.id));
    try {
      await _repo.unassign(a.id);
      AppToast.success('Removed from job');
      _changed = true;
      await _loadTeam();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _removing.remove(a.id));
    }
  }

  List<Widget> _actions() {
    Widget btn(String label, IconData icon, Color color, String action,
        {bool outlined = false, VoidCallback? onTap, bool enabled = true}) {
      final handler = (!enabled || _busy) ? null : (onTap ?? () => _act(action));
      final showSpinner = _busy && handler != null;
      return SizedBox(
        height: 46,
        child: outlined
            ? OutlinedButton.icon(
                onPressed: handler,
                icon: Icon(icon, size: 18, color: color),
                label: Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                    side: BorderSide(color: color.withValues(alpha: 0.5))),
              )
            : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  disabledBackgroundColor: color.withValues(alpha: 0.35),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                ),
                onPressed: handler,
                icon: showSpinner
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.2, color: Colors.white))
                    : Icon(icon, size: 18),
                label: Text(label),
              ),
      );
    }
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
        // Cash still owed at the door → must collect before completing, like
        // the web. The Complete button stays disabled until cash is collected.
        if (b.cashPending) {
          return [
            btn('Collect AED ${b.cashDue.toStringAsFixed(0)}',
                Icons.payments_rounded, AppColors.amber, 'collect',
                onTap: _collectCash),
            btn('Complete', Icons.check_circle_rounded, AppColors.brand600,
                'complete',
                enabled: false),
          ];
        }
        return [
          btn('Complete', Icons.check_circle_rounded, AppColors.brand600,
              'complete'),
        ];
      case 'completed':
        // Optional post-completion CTA (mirrors the web). Hidden once the
        // customer has been reviewed — the submitted review card shows instead.
        if (b.customerReviewed) return const [];
        return [
          btn('Review customer', Icons.star_rounded, AppColors.amber, 'review',
              outlined: true, onTap: _reviewCustomer),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live: refresh team when this booking changes (status/dispatch/assign).
    ref.listen(bookingRealtimeProvider, (_, __) {
      final lid = ref.read(bookingRealtimeProvider.notifier).lastBookingId;
      if (mounted && (lid == null || lid == b.id)) {
        _loadTeam();
        _reloadBooking();
      }
    });
    final actions = _actions();
    final canManageTeam = b.status == 'awaiting_acceptance' ||
        b.status == 'accepted' ||
        b.status == 'in_progress';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed ? 'reload' : '');
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: MainAppBar('Booking details'),
        body: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _heroCard(),
              const SizedBox(height: 14),
              _customerCard(),
              const SizedBox(height: 14),
              _scheduleCard(),
              const SizedBox(height: 14),
              _paymentCard(),
              const SizedBox(height: 14),
              _teamCard(canManageTeam),
              if (b.status == 'completed' && _customerReview != null) ...[
                const SizedBox(height: 14),
                _reviewCard(_customerReview!),
              ],
            ],
          ),
        ),
        bottomNavigationBar:
            actions.isEmpty ? null : _bottomActionBar(actions),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared card scaffolding
  // ---------------------------------------------------------------------------

  Widget _card(Widget child, {EdgeInsetsGeometry? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: AppColors.isDark ? 0.28 : 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionHeader(IconData icon, String title, {Widget? trailing}) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.brand600.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 17, color: AppColors.brand600),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
          ),
          if (trailing != null) trailing,
        ],
      );

  /// A labelled field row used inside cards: leading icon, muted label, value.
  Widget _infoRow(IconData icon, String label, String value,
          {Color? valueColor}) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: valueColor ?? AppColors.textPrimary)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Rounded, semantic-coloured status chip with contrast in both themes.
  Widget _semChip(String label, Color base, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: base.withValues(alpha: AppColors.isDark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: base.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: base),
              const SizedBox(width: 5),
            ],
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: base)),
          ],
        ),
      );

  /// Semantic colour for a payment-receipt status string.
  Color _paymentColor(String status) {
    final v = status.toLowerCase();
    if (['paid', 'full', 'success', 'complete', 'completed'].contains(v)) {
      return AppColors.brand600;
    }
    if (['pending', 'partial', 'unpaid', 'not received', 'not_received']
        .contains(v)) {
      return AppColors.amber;
    }
    return AppColors.textMuted;
  }

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  /// Hero/status header: service, copyable booking ref, and status chips.
  Widget _heroCard() => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ServiceTitle(b.serviceName, titleSize: 20),
            if (b.ref.isNotEmpty) ...[
              const SizedBox(height: 12),
              _refChip(),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(b.status),
                if (b.paymentStatus.isNotEmpty)
                  _semChip(
                    b.paymentStatus.replaceAll('_', ' '),
                    _paymentColor(b.paymentStatus),
                    icon: Icons.payments_outlined,
                  ),
                if (b.cashCollected)
                  _semChip('Cash collected', AppColors.brand600,
                      icon: Icons.check_circle_outline)
                else if (b.cashPending)
                  _semChip('Cash due AED ${b.cashDue.toStringAsFixed(0)}',
                      AppColors.amber,
                      icon: Icons.account_balance_wallet_outlined),
              ],
            ),
          ],
        ),
      );

  /// Copyable booking reference chip.
  Widget _refChip() => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: b.ref));
          AppToast.success('Booking ref copied');
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tag, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Text('#${b.ref}',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Icon(Icons.copy_rounded, size: 13, color: AppColors.textFaint),
            ],
          ),
        ),
      );

  /// Customer & location.
  Widget _customerCard() => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.person_outline, 'Customer'),
            _infoRow(Icons.badge_outlined, 'Name',
                b.customerName.isEmpty ? '—' : b.customerName),
            _infoRow(Icons.place_outlined, 'Area',
                b.area.isEmpty ? '—' : b.area),
          ],
        ),
      );

  /// Schedule.
  Widget _scheduleCard() => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.event_outlined, 'Schedule'),
            _infoRow(
                Icons.schedule_outlined,
                'Scheduled start',
                b.scheduledStart != null
                    ? DateFormat('EEE d MMM y · h:mm a')
                        .format(b.scheduledStart!)
                    : 'Not scheduled'),
          ],
        ),
      );

  /// Payment, payout & cash collection.
  Widget _paymentCard() => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.payments_outlined, 'Payment & payout'),
            if (b.payment.isNotEmpty)
              _infoRow(Icons.credit_card_outlined, 'Method',
                  b.payment.replaceAll('_', ' ')),
            if (b.paymentStatus.isNotEmpty)
              _infoRow(Icons.receipt_long_outlined, 'Payment status',
                  b.paymentStatus.replaceAll('_', ' '),
                  valueColor: _paymentColor(b.paymentStatus)),
            // Cap-aware take-home (partnerNet mirror) — net of CNC commission
            // and cap-floor protected. This is the honest number; cash you
            // collect is reconciled against it in your wallet after completion.
            _infoRow(Icons.account_balance_wallet_outlined, 'Your payout',
                'AED ${b.partnerCost.toStringAsFixed(2)}',
                valueColor: AppColors.brand600),
            if (b.capApplied) ...[
              const SizedBox(height: 12),
              _noticeBox(
                Icons.verified_user_outlined,
                'Discount cap applied — your payout is protected at your '
                'guaranteed floor even though the customer used a discount.',
                AppColors.brand600,
              ),
            ],
            if (b.cashPending && b.status == 'in_progress') ...[
              const SizedBox(height: 12),
              _noticeBox(
                Icons.account_balance_wallet_outlined,
                'Collect AED ${b.cashDue.toStringAsFixed(2)} in cash from the '
                'customer, then mark it collected to complete the job.',
                AppColors.amber,
              ),
            ],
            if (b.cashCollected) ...[
              const SizedBox(height: 12),
              _noticeBox(
                Icons.check_circle_outline,
                'Cash of AED ${b.cashDue.toStringAsFixed(2)} marked collected.',
                AppColors.brand600,
              ),
            ],
          ],
        ),
      );

  /// A tinted, bordered inline notice inside a card.
  Widget _noticeBox(IconData icon, String text, Color base) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: base.withValues(alpha: AppColors.isDark ? 0.16 : 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: base.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: base),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ),
          ],
        ),
      );

  /// Assignment / team.
  Widget _teamCard(bool canManageTeam) => _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              Icons.groups_outlined,
              'Team',
              trailing: canManageTeam
                  ? TextButton.icon(
                      onPressed: _openAssignTeam,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppColors.brand600,
                      ),
                      icon: const Icon(Icons.person_add_alt_1, size: 18),
                      label: const Text('Assign',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            _teamBody(canManageTeam),
          ],
        ),
      );

  Widget _teamBody(bool canManageTeam) {
    final team = _team;
    if (team == null) {
      // Bounded skeleton placeholder while the team loads.
      return Column(
        children: List.generate(
          2,
          (_) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
          ),
        ),
      );
    }
    if (team.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.group_off_outlined,
                size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                  _teamError
                      ? 'Couldn\'t load the team. Pull down or reopen to retry.'
                      : canManageTeam
                          ? 'No one assigned yet. Tap Assign to add a worker.'
                          : 'No team assigned.',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ],
        ),
      );
    }
    // De-duplicate: the API can return the same worker+role more than once.
    final seen = <String>{};
    final unique = [
      for (final a in team)
        if (seen.add('${a.workerName.toLowerCase()}|${a.role}')) a
    ];
    return Column(
      children: [
        for (var i = 0; i < unique.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == unique.length - 1 ? 0 : 8),
            child: _teamRow(unique[i], canManageTeam),
          ),
      ],
    );
  }

  Widget _teamRow(BookingAssignment a, bool canManage) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brand600.withValues(alpha: 0.12),
              child: Icon(
                  a.role == 'driver'
                      ? Icons.directions_car
                      : Icons.cleaning_services,
                  size: 16,
                  color: AppColors.brand600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.workerName.isEmpty ? 'Worker' : a.workerName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ([a.role, if (a.status.isNotEmpty) a.status]
                      .where((s) => s.isNotEmpty)
                      .isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                        [a.role, if (a.status.isNotEmpty) a.status]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12)),
                  ],
                ],
              ),
            ),
            if (canManage)
              _removing.contains(a.id)
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2.2)),
                    )
                  : IconButton(
                      onPressed: () => _unassign(a),
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.rose),
                      tooltip: 'Remove',
                    ),
          ],
        ),
      );

  /// The submitted "your review of the customer" card (read-only), with a
  /// tap-to-edit affordance since the backend upserts the same row.
  Widget _reviewCard(Review r) {
    final s = r.stars.round();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            Icons.star_outline_rounded,
            'Your review of the customer',
            trailing: TextButton(
              onPressed: _busy ? null : _reviewCustomer,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.brand600,
              ),
              child: const Text('Edit',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= s ? Icons.star_rounded : Icons.star_border_rounded,
                    size: 24, color: AppColors.amber),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(r.comment,
                style:
                    TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }

  /// Pinned bottom bar hosting the contextual primary action(s).
  Widget _bottomActionBar(List<Widget> actions) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: AppColors.isDark ? 0.30 : 0.05),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: actions[i]),
                ],
              ],
            ),
          ),
        ),
      );
}
