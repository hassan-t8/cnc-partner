import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/service_title.dart';
import '../bookings/models.dart';

/// In-app alert shown to a worker/driver when a new job is auto-assigned to
/// them (partner accepted the dispatch offer). Purely a notification — the job
/// is already accepted; the worker just Starts/Completes it. Returns 'view'
/// (open the job) or 'dismiss'.
Future<String> showJobAlert(
    BuildContext context, WidgetRef ref, Assignment a) async {
  final res = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'New job',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.92 + 0.08 * curved.value,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _JobAlertCard(a: a),
            ),
          ),
        ),
      );
    },
  );
  return res ?? 'dismiss';
}

class _JobAlertCard extends StatelessWidget {
  final Assignment a;
  const _JobAlertCard({required this.a});

  @override
  Widget build(BuildContext context) {
    final schedule = a.scheduledStart != null
        ? DateFormat('EEE d MMM y · h:mm a').format(a.scheduledStart!)
        : null;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.assignment_turned_in_rounded,
                          size: 15, color: AppColors.brand700),
                      const SizedBox(width: 3),
                      Text('NEW JOB ASSIGNED',
                          style: TextStyle(
                              color: AppColors.brand700,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                              letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const Spacer(),
                if (a.role.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.violet.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(a.role.toUpperCase(),
                        style: TextStyle(
                            color: AppColors.violet,
                            fontWeight: FontWeight.w800,
                            fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ServiceTitle(a.serviceName, titleSize: 17),
            const SizedBox(height: 10),
            if (a.customerName.isNotEmpty)
              _row(Icons.person_outline, a.customerName),
            if (schedule != null) _row(Icons.schedule_outlined, schedule),
            if (a.fullAddress.isNotEmpty)
              _row(Icons.place_outlined, a.fullAddress),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, 'dismiss'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: const Text('Got it'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'view'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand600,
                        padding: const EdgeInsets.symmetric(vertical: 13)),
                    child: const Text('View job',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
