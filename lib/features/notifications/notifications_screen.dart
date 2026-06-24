import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  @override
  void initState() {
    super.initState();
    // Opening the panel marks everything read (web parity).
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(notificationsProvider.notifier).markAllRead());
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
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen!));
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: const MainAppBar('Notifications', showBell: false),
      body: RefreshIndicator(
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: state.loading && state.items.isEmpty
            ? const LoadingList()
            : state.items.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 100),
                    EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'You\'re all caught up',
                        subtitle: 'New offers and updates will appear here.'),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _tile(state.items[i]),
                  ),
      ),
    );
  }

  Widget _tile(AppNotification n) {
    final color = _typeColor(n.type);
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
                    Text(n.title.isEmpty ? 'Notification' : n.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    if (n.message.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(n.message,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 12.5)),
                      ),
                    const SizedBox(height: 4),
                    Text(_ago(n.createdAt),
                        style: TextStyle(
                            color: AppColors.textFaint, fontSize: 11)),
                  ],
                ),
              ),
              if (!n.isRead)
                Container(
                  margin: const EdgeInsets.only(top: 4, left: 6),
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                      color: AppColors.brand600, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
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
