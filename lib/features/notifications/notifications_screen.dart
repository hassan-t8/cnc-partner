import 'dart:async';

import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/notifications/notifications_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../partner/partner_bookings_screen.dart';
import '../partner/partner_earnings_screen.dart';
import '../partner/partner_requests_screen.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // 'all' | 'requests' | 'bookings' | 'earnings'
  String _filter = 'all';
  // Ticks every minute so the relative time + "time left" stay current.
  Timer? _tick;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // Opening the panel marks everything read (web parity).
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(notificationsProvider.notifier).markAllRead());
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    // Widen the window a page before the very bottom so it feels seamless.
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 300) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _open(AppNotification n) {
    final isPartner = ref.read(authControllerProvider).user?.isPartner ?? false;
    if (!isPartner) return;
    Widget? screen;
    switch (n.target) {
      case 'bookings':
        screen = const PartnerBookingsScreen();
        break;
      case 'requests':
        screen = const PartnerRequestsScreen();
        break;
      case 'earnings':
        screen = const PartnerEarningsScreen();
        break;
    }
    if (screen != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
    }
  }

  String _ago(DateTime? d) {
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  // Splits a booking-offer message into the human details and the trailing
  // "accept before <deadline>" text (which is only present on offers).
  ({String details, String? deadline}) _split(String msg) {
    final lower = msg.toLowerCase();
    final tapAt = lower.indexOf('tap to');
    final beforeAt = lower.indexOf('accept before');
    var details = (tapAt >= 0 ? msg.substring(0, tapAt) : msg).trim();
    details = details.replaceFirst(RegExp(r'[.\s]+$'), '');
    String? deadline;
    if (beforeAt >= 0) {
      deadline = msg
          .substring(beforeAt + 'accept before'.length)
          .trim()
          .replaceFirst(RegExp(r'^[:\s]+'), '')
          .replaceFirst(RegExp(r'[.\s]+$'), '');
      if (deadline.isEmpty) deadline = null;
    }
    return (details: details, deadline: deadline);
  }

  // Best-effort parse of a deadline like "Thu, Jul 2, 2026, 12:39 PM".
  DateTime? _parseDeadline(String s) {
    for (final f in const [
      'EEE, MMM d, yyyy, h:mm a',
      'MMM d, yyyy, h:mm a',
      'EEE, MMM d, h:mm a',
    ]) {
      try {
        return DateFormat(f).parseLoose(s);
      } catch (_) {}
    }
    return null;
  }

  String _timeLeft(DateTime dl) {
    final diff = dl.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m left';
    if (diff.inHours < 24) {
      return '${diff.inHours}h ${diff.inMinutes % 60}m left';
    }
    return '${diff.inDays}d left';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final items = _filter == 'all'
        ? state.items
        : state.items.where((n) => n.target == _filter).toList();
    return Scaffold(
      appBar: const MainAppBar('Notifications', showBell: false),
      body: Column(
        children: [
          _filterBar(state.items),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(notificationsProvider.notifier).refresh(),
              child: state.loading && state.items.isEmpty
                  ? const LoadingList()
                  : items.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 100),
                          EmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: "You're all caught up",
                              subtitle:
                                  'New offers and updates will appear here.'),
                        ])
                      : ListView.separated(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          // A trailing "load older" row on the All tab. The
                          // other tabs are client-side subsets of the same
                          // in-memory list, so paging them is meaningless —
                          // widening the window brings in more of everything.
                          itemCount: items.length +
                              (_filter == 'all' && state.hasMore ? 1 : 0),
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            if (i >= items.length) {
                              return _loadMoreFooter(state.loadingMore);
                            }
                            return _tile(items[i]);
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadMoreFooter(bool loading) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.brand600),
              )
            : TextButton(
                onPressed: () =>
                    ref.read(notificationsProvider.notifier).loadMore(),
                child: const Text('Load older'),
              ),
      ),
    );
  }

  Widget _filterBar(List<AppNotification> all) {
    int countFor(String t) =>
        t == 'all' ? all.length : all.where((n) => n.target == t).length;
    const tabs = [
      ('all', 'All'),
      ('requests', 'Offers'),
      ('bookings', 'Bookings'),
      ('earnings', 'Earnings'),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        children: [
          for (final t in tabs) ...[
            _filterChip(t.$1, t.$2, countFor(t.$1)),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _filterChip(String key, String label, int count) {
    final on = _filter == key;
    return ChoiceChip(
      selected: on,
      onSelected: (_) => setState(() => _filter = key),
      label: Text('$label${count > 0 ? '  $count' : ''}'),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: on ? Colors.white : AppColors.textMuted,
      ),
      selectedColor: AppColors.brand600,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: on ? AppColors.brand600 : AppColors.border),
      showCheckmark: false,
    );
  }

  Widget _tile(AppNotification n) {
    final color = _typeColor(n.type);
    final parts = _split(n.message);
    final dl = parts.deadline == null ? null : _parseDeadline(parts.deadline!);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _open(n),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
                child: Icon(_typeIcon(n.type), color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title (left) + relative time (top-right, same row).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                              n.title.isEmpty ? 'Notification' : n.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        const SizedBox(width: 8),
                        Text(_ago(n.createdAt),
                            style: TextStyle(
                                color: AppColors.textFaint, fontSize: 11)),
                        if (!n.isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                                color: AppColors.brand600,
                                shape: BoxShape.circle),
                          ),
                        ],
                      ],
                    ),
                    if (parts.details.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(parts.details,
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12.5,
                                height: 1.3)),
                      ),
                    if (parts.deadline != null) _deadlineChip(parts.deadline!, dl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Highlighted "accept before" row with a live time-left when parseable.
  Widget _deadlineChip(String text, DateTime? dl) {
    final left = dl == null ? null : _timeLeft(dl);
    final expired = left == 'Expired';
    final urgent = dl != null &&
        !expired &&
        dl.difference(DateTime.now()).inMinutes < 60;
    final c = expired
        ? AppColors.rose
        : (urgent ? AppColors.amber : AppColors.brand600);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(expired ? Icons.timer_off_outlined : Icons.timer_outlined,
              size: 15, color: c),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              expired ? 'Offer expired' : 'Accept before $text',
              style: TextStyle(
                  color: c, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (left != null && !expired) ...[
            const SizedBox(width: 8),
            Text(left,
                style: TextStyle(
                    color: c, fontSize: 11.5, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }

  IconData _typeIcon(String type) {
    if (type.startsWith('dispatch')) return Icons.inbox_rounded;
    if (type.startsWith('payment')) return Icons.payments_rounded;
    if (type.contains('completed')) return Icons.check_circle_rounded;
    if (type.contains('cancel')) return Icons.cancel_rounded;
    return Icons.event_note_rounded;
  }

  Color _typeColor(String type) {
    if (type.startsWith('dispatch')) return AppColors.violet;
    if (type.startsWith('payment')) return AppColors.brand600;
    if (type.contains('cancel')) return AppColors.rose;
    return AppColors.sky;
  }
}
