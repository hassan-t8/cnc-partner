import '../../widgets/main_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/status_badge.dart';
import '../bookings/models.dart';
import 'otp_dialog.dart';
import 'today_summary.dart';
import 'worker_repository.dart';

class CrewJobsScreen extends ConsumerStatefulWidget {
  const CrewJobsScreen({super.key});
  @override
  ConsumerState<CrewJobsScreen> createState() => _CrewJobsScreenState();
}

class _CrewJobsScreenState extends ConsumerState<CrewJobsScreen> {
  late Future<List<Assignment>> _future;
  int _acting = -1;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Assignment>> _load() {
    final workerId =
        ref.read(authControllerProvider).user?.workerId ?? 0;
    final now = DateTime.now();
    final from = DateTime(now.year, now.month, now.day);
    final to = from.add(const Duration(days: 2));
    return ref
        .read(workerRepositoryProvider)
        .assignments(workerId: workerId, from: from, to: to);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _act(Assignment a, String action) async {
    final repo = ref.read(workerRepositoryProvider);
    setState(() => _acting = a.id);
    try {
      switch (action) {
        case 'accept':
          await repo.accept(a.id);
          AppToast.success('Job accepted');
          break;
        case 'decline':
          final reason = await _reasonDialog();
          if (reason == null) {
            setState(() => _acting = -1);
            return;
          }
          await repo.decline(a.id, reason: reason.isEmpty ? null : reason);
          AppToast.success('Job declined');
          break;
        case 'start':
          await _start(a);
          break;
        case 'complete':
          await repo.complete(a.id);
          AppToast.success('Job completed');
          break;
      }
      _reload();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  Future<void> _start(Assignment a) async {
    final repo = ref.read(workerRepositoryProvider);
    try {
      await repo.start(a.id);
      AppToast.success('Job started');
    } on ApiException catch (e) {
      if (e.code == 'OTP_REQUIRED' || e.code == 'OTP_INVALID') {
        if (!mounted) return;
        final otp = await showOtpDialog(context,
            bookingRef: '#${a.bookingId ?? a.id}',
            customerName: a.customerName);
        if (otp == null) return;
        await repo.start(a.id, otp: otp);
        AppToast.success('Job started');
      } else {
        rethrow;
      }
    }
  }

  Future<String?> _reasonDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline job'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration:
              const InputDecoration(hintText: 'Reason (optional)'),
        ),
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
      appBar: const MainAppBar('My jobs'),
      body: Column(
        children: [
          const TodaySummary(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<Assignment>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const LoadingList();
            }
            if (snap.hasError) {
              return ErrorRetry(
                  message: 'Couldn\'t load your jobs.', onRetry: _reload);
            }
            final jobs = snap.data ?? const [];
            if (jobs.isEmpty) {
              return ListView(children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.event_available,
                  title: 'Nothing scheduled',
                  subtitle: 'Enjoy the day — new jobs will appear here.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _jobCard(jobs[i]),
            );
          },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jobCard(Assignment a) {
    final busy = _acting == a.id;
    final time = a.scheduledStart != null
        ? DateFormat('EEE d MMM · h:mm a').format(a.scheduledStart!)
        : 'Time TBD';
    return Container(
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
              Expanded(
                child: Text(
                    a.serviceName.isEmpty ? 'Service' : a.serviceName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15.5)),
              ),
              StatusBadge(a.status, worker: true),
            ],
          ),
          const SizedBox(height: 6),
          _row(Icons.schedule, time),
          if (a.customerName.isNotEmpty) _row(Icons.person_outline, a.customerName),
          if (a.fullAddress.isNotEmpty) _row(Icons.place_outlined, a.fullAddress),
          const SizedBox(height: 10),
          Row(
            children: [
              if (a.fullAddress.isNotEmpty)
                _ghost(Icons.directions_outlined, 'Directions', () {
                  launchUrl(
                    Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(a.fullAddress)}'),
                    mode: LaunchMode.externalApplication,
                  );
                }),
              if (a.partnerPhone != null && a.partnerPhone!.isNotEmpty) ...[
                const SizedBox(width: 8),
                _ghost(Icons.call_outlined, 'Call', () {
                  launchUrl(Uri.parse('tel:${a.partnerPhone}'));
                }),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _actions(a, busy),
          if (a.status == 'accepted' ||
              a.status == 'in_progress' ||
              a.status == 'completed') ...[
            const Divider(height: 20),
            _photoRow(a, 'before', 'Before photos'),
            if (a.status == 'in_progress' || a.status == 'completed')
              _photoRow(a, 'after', 'After photos'),
          ],
        ],
      ),
    );
  }

  Widget _photoRow(Assignment a, String type, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          OutlinedButton.icon(
            onPressed: () => _uploadPhoto(a, type),
            icon: const Icon(Icons.camera_alt_outlined, size: 16),
            label: const Text('Add', style: TextStyle(fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadPhoto(Assignment a, String type) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
        source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear);
    if (file == null) return;
    try {
      await ref
          .read(workerRepositoryProvider)
          .uploadAttachment(a.id, file.path, type);
      AppToast.success('Photo uploaded');
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } catch (_) {
      AppToast.error('Upload failed.');
    }
  }

  Widget _actions(Assignment a, bool busy) {
    final children = <Widget>[];
    switch (a.status) {
      case 'pending_acceptance':
        children.add(_primary('Accept', AppColors.brand600,
            busy ? null : () => _act(a, 'accept')));
        children.add(_primary('Decline', AppColors.rose,
            busy ? null : () => _act(a, 'decline')));
        break;
      case 'accepted':
        children.add(_primary('Start', AppColors.violet,
            busy ? null : () => _act(a, 'start')));
        break;
      case 'in_progress':
        children.add(_primary('Complete', AppColors.brand600,
            busy ? null : () => _act(a, 'complete')));
        break;
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _primary(String label, Color color, VoidCallback? onTap) => SizedBox(
        height: 42,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color),
          onPressed: onTap,
          child: Text(label),
        ),
      );

  Widget _ghost(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      );

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))),
          ],
        ),
      );
}
