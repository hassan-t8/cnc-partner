import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

class PartnerRequestsScreen extends ConsumerStatefulWidget {
  const PartnerRequestsScreen({super.key});
  @override
  ConsumerState<PartnerRequestsScreen> createState() =>
      _PartnerRequestsScreenState();
}

class _PartnerRequestsScreenState
    extends ConsumerState<PartnerRequestsScreen> {
  List<Offer> _offers = [];
  bool _loading = true;
  bool _error = false;
  int _acting = -1;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _fetch());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _offers.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final offers = await ref.read(partnerRepositoryProvider).offers();
      if (!mounted) return;
      setState(() {
        _offers = offers;
        _loading = false;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _act(Offer o, bool accept) async {
    setState(() => _acting = o.id);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (accept) {
        await repo.acceptOffer(o.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineOffer(o.id);
        AppToast.success('Declined — passed to the next partner');
      }
      await _fetch();
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _acting = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Requests'),
        actions: [
          IconButton(
              onPressed: _fetch, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const LoadingList(height: 150)
          : _error
              ? ErrorRetry(
                  message: 'Couldn\'t load requests.', onRetry: _fetch)
              : _offers.isEmpty
                  ? const EmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No pending requests',
                      subtitle: 'New dispatch offers will appear here.')
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _offers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _card(_offers[i]),
                      ),
                    ),
    );
  }

  String _countdown(DateTime? exp) {
    if (exp == null) return '';
    final secs = exp.difference(DateTime.now()).inSeconds;
    if (secs <= 0) return 'Expired';
    final m = secs ~/ 60, s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Color _countdownColor(DateTime? exp) {
    if (exp == null) return AppColors.textMuted;
    final secs = exp.difference(DateTime.now()).inSeconds;
    if (secs <= 0) return AppColors.textFaint;
    if (secs < 300) return AppColors.rose;
    return AppColors.amber;
  }

  Widget _card(Offer o) {
    final busy = _acting == o.id;
    final expired =
        o.expiresAt != null && o.expiresAt!.isBefore(DateTime.now());
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
                child: Text(o.serviceName.isEmpty ? 'Service' : o.serviceName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _countdownColor(o.expiresAt).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 14, color: _countdownColor(o.expiresAt)),
                    const SizedBox(width: 4),
                    Text(_countdown(o.expiresAt),
                        style: TextStyle(
                            color: _countdownColor(o.expiresAt),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (o.rank > 1)
            Text('Attempt #${o.rank}',
                style: const TextStyle(
                    color: AppColors.amber,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          _row(Icons.person_outline, o.customerName),
          if (o.address.isNotEmpty) _row(Icons.place_outlined, o.address),
          _row(Icons.payments_outlined,
              'AED ${o.earnings.toStringAsFixed(2)}'),
          if (o.crewRequired > 0)
            _row(Icons.groups_outlined, '${o.crewRequired} crew required'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed:
                        (busy || expired) ? null : () => _act(o, true),
                    child: const Text('Accept'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: OutlinedButton(
                    onPressed:
                        (busy || expired) ? null : () => _act(o, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.rose,
                        side: const BorderSide(color: AppColors.rose)),
                    child: const Text('Decline'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textFaint),
            const SizedBox(width: 6),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))),
          ],
        ),
      );
}
