import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_states.dart';
import '../../widgets/searchable_picker.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/main_app_bar.dart';
import '../../widgets/service_title.dart';
import 'offer_details_sheet.dart';
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

  Future<void> _act(Offer o, bool accept,
      {Map<String, dynamic>? substitutions}) async {
    setState(() => _acting = o.id);
    try {
      final repo = ref.read(partnerRepositoryProvider);
      if (accept) {
        await repo.acceptOffer(o.id, substitutions: substitutions);
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
    // Refetch when the bottom-nav tab is (re)tapped.
    ref.listen(tabRefreshProvider, (_, __) {
      if (mounted) _fetch();
    });
    return Scaffold(
      appBar: const MainAppBar('Requests'),
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

  Future<void> _openDetails(Offer o) async {
    final action = await showOfferDetailsSheet(context, ref, o);
    if (action != null && mounted) _fetch();
  }

  Widget _card(Offer o) {
    final busy = _acting == o.id;
    final expired =
        o.expiresAt != null && o.expiresAt!.isBefore(DateTime.now());
    return InkWell(
      onTap: busy ? null : () => _openDetails(o),
      borderRadius: BorderRadius.circular(14),
      child: Container(
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
                child: ServiceTitle(o.serviceName),
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
              'Your earnings: AED ${o.earnings.toStringAsFixed(2)}'),
          if (o.crewRequired > 0)
            _row(Icons.groups_outlined, '${o.crewRequired} crew required'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    // Accept as auto-assigned (no worker/van/driver editing) —
                    // matches the web: the team is auto-assigned on accept.
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
                    style: TextStyle(
                        fontSize: 12.5, color: AppColors.textSecondary))),
          ],
        ),
      );
}

/// Review the proposed team for an offer and optionally swap the workers / van
/// / driver before accepting. Pops:
///   null  -> cancelled
///   {}    -> accept as proposed (no substitutions)
///   {...} -> accept with substitutions {workerIds, vanId, driverWorkerId}
class _OfferAcceptSheet extends ConsumerStatefulWidget {
  final int offerId;
  final PartnerRepository repo;
  const _OfferAcceptSheet({required this.offerId, required this.repo});
  @override
  ConsumerState<_OfferAcceptSheet> createState() => _OfferAcceptSheetState();
}

class _OfferAcceptSheetState extends ConsumerState<_OfferAcceptSheet> {
  bool _loading = true;
  bool _busy = false;
  List<Worker> _workers = const [];
  List<Van> _vans = const [];
  // proposed (from candidateSnapshot)
  Set<int> _selWorkers = {};
  int? _vanId;
  int? _driverId;
  Set<int> _origWorkers = {};
  int? _origVan;
  int? _origDriver;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repo.getOffer(widget.offerId),
        widget.repo.workers().catchError((_) => <Worker>[]),
        widget.repo.vans().catchError((_) => <Van>[]),
      ]);
      final offer = results[0] as Map<String, dynamic>;
      final snap = offer['candidateSnapshot'] is Map
          ? Map<String, dynamic>.from(offer['candidateSnapshot'])
          : const {};
      final wIds = (snap['workerIds'] is List)
          ? (snap['workerIds'] as List)
              .map((e) => int.tryParse('$e') ?? 0)
              .where((e) => e > 0)
              .toSet()
          : <int>{};
      _selWorkers = {...wIds};
      _origWorkers = {...wIds};
      _vanId = int.tryParse('${snap['vanId'] ?? ''}');
      _origVan = _vanId;
      _driverId = int.tryParse('${snap['driverWorkerId'] ?? ''}');
      _origDriver = _driverId;
      if (mounted) {
        setState(() {
          _workers = results[1] as List<Worker>;
          _vans = results[2] as List<Van>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _changed =>
      !_setEq(_selWorkers, _origWorkers) ||
      _vanId != _origVan ||
      _driverId != _origDriver;

  bool _setEq(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);

  void _confirm() {
    if (_selWorkers.isEmpty) {
      AppToast.error('Select at least one worker.');
      return;
    }
    setState(() => _busy = true);
    Navigator.pop(context,
        _changed
            ? {
                'workerIds': _selWorkers.toList(),
                'vanId': _vanId,
                'driverWorkerId': _driverId,
              }
            : <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    final drivers = _workers.where((w) => w.roles.contains('driver')).toList();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Accept offer',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('Review the team, swap if needed, then accept.',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5)),
                    const SizedBox(height: 16),
                    const Text('Workers',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _workers
                          .where((w) => !w.roles.contains('driver') ||
                              _selWorkers.contains(w.id))
                          .map((w) {
                        final on = _selWorkers.contains(w.id);
                        return FilterChip(
                          label: Text(w.name.isEmpty ? 'Worker' : w.name),
                          selected: on,
                          onSelected: (v) => setState(() => v
                              ? _selWorkers.add(w.id)
                              : _selWorkers.remove(w.id)),
                          selectedColor: AppColors.brand600,
                          labelStyle: TextStyle(
                              color: on ? Colors.white : AppColors.textSecondary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                          backgroundColor: AppColors.surface,
                          side: BorderSide(color: AppColors.border),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Van',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      const noVan = Van(id: -1);
                      final cur = _vans.where((v) => v.id == _vanId).toList();
                      return PickerField(
                        value: _vanId == null
                            ? 'No van'
                            : (cur.isNotEmpty ? cur.first.name : 'Van'),
                        hint: 'No van',
                        onTap: () async {
                          final picked = await showSearchablePicker<Van>(
                            context: context,
                            title: 'Van',
                            items: <Van>[noVan, ..._vans],
                            labelOf: (v) => v.id == -1
                                ? 'No van'
                                : (v.name.isEmpty ? 'Van' : v.name),
                            selected:
                                _vanId == null ? noVan : (cur.isNotEmpty ? cur.first : null),
                            equals: (a, b) => a.id == b.id,
                          );
                          if (picked == null) return;
                          setState(() =>
                              _vanId = picked.id == -1 ? null : picked.id);
                        },
                      );
                    }),
                    const SizedBox(height: 14),
                    const Text('Driver',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Builder(builder: (_) {
                      const noDriver = Worker(id: -1);
                      final cur =
                          drivers.where((d) => d.id == _driverId).toList();
                      return PickerField(
                        value: _driverId == null
                            ? 'No driver'
                            : (cur.isNotEmpty ? cur.first.name : 'Driver'),
                        hint: 'No driver',
                        onTap: () async {
                          final picked = await showSearchablePicker<Worker>(
                            context: context,
                            title: 'Driver',
                            items: <Worker>[noDriver, ...drivers],
                            labelOf: (d) => d.id == -1
                                ? 'No driver'
                                : (d.name.isEmpty ? 'Driver' : d.name),
                            selected: _driverId == null
                                ? noDriver
                                : (cur.isNotEmpty ? cur.first : null),
                            equals: (a, b) => a.id == b.id,
                          );
                          if (picked == null) return;
                          setState(() =>
                              _driverId = picked.id == -1 ? null : picked.id);
                        },
                      );
                    }),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _confirm,
                        child: Text(_changed
                            ? 'Accept with changes'
                            : 'Accept as proposed'),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
