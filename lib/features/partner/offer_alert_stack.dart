import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../widgets/reason_dialog.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/service_title.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// inDrive-style STACKED offer alerts.
///
/// Instead of a single blocking dialog, fresh dispatch offers stack at the top
/// of the screen — the newest on top, older ones peeking behind. Each card
/// slides in on arrival, runs its own 30-second countdown, and slides out
/// (auto-dismiss) when it expires or is accepted/declined. Up to 3 are shown;
/// any beyond that collapse into a "+N more" pill.
class OfferAlertOverlay {
  OfferAlertOverlay._();
  static final OfferAlertOverlay instance = OfferAlertOverlay._();

  OverlayEntry? _entry;
  final GlobalKey<_OfferStackState> _key = GlobalKey<_OfferStackState>();

  /// Hides the stack while a dialog opened FROM it is on screen.
  ///
  /// The stack lives in an OverlayEntry appended to the ROOT overlay, so it
  /// renders ABOVE every Navigator route — including dialogs. The decline-reason
  /// prompt was therefore pushed UNDERNEATH the offer card: the card stayed
  /// visible on top of it and swallowed every tap, so neither Cancel nor Decline
  /// responded.
  ///
  /// Suspending makes the stack transparent AND pointer-transparent, so the
  /// dialog below it is both visible and tappable. It is NOT unmounted — the
  /// card's BuildContext has to stay valid for the dialog it just opened.
  final ValueNotifier<bool> suspended = ValueNotifier<bool>(false);

  /// Push an offer onto the stack. Creates the overlay on first use.
  /// [onAction] fires with 'accept' | 'decline' | 'later' when it resolves.
  void push(
    BuildContext context,
    WidgetRef ref,
    Offer offer, {
    void Function(String action)? onAction,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_entry == null) {
      _entry = OverlayEntry(
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: suspended,
          child: _OfferStack(key: _key, ref: ref, onEmpty: _collapse),
          builder: (_, isSuspended, child) => IgnorePointer(
            ignoring: isSuspended,
            child: Opacity(opacity: isSuspended ? 0 : 1, child: child),
          ),
        ),
      );
      overlay.insert(_entry!);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _key.currentState?.add(offer, onAction));
    } else {
      _key.currentState?.add(offer, onAction);
    }
  }

  void _collapse() {
    _entry?.remove();
    _entry = null;
    suspended.value = false;
  }
}

class _OfferData {
  final Offer offer;
  final void Function(String action)? onAction;
  _OfferData(this.offer, this.onAction);
}

class _OfferStack extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final VoidCallback onEmpty;
  const _OfferStack(
      {super.key, required this.ref, required this.onEmpty});
  @override
  ConsumerState<_OfferStack> createState() => _OfferStackState();
}

class _OfferStackState extends ConsumerState<_OfferStack> {
  static const int _maxVisible = 3;
  final List<_OfferData> _items = []; // newest first (index 0)

  void add(Offer offer, void Function(String)? onAction) {
    if (_items.any((d) => d.offer.id == offer.id)) return;
    setState(() => _items.insert(0, _OfferData(offer, onAction)));
  }

  void _resolve(_OfferData d, String action) {
    d.onAction?.call(action);
    if (!mounted) return;
    setState(() => _items.remove(d));
    if (_items.isEmpty) widget.onEmpty();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items.take(_maxVisible).toList();
    final hidden = _items.length - visible.length;
    // Centered on screen (was top-anchored). A dim scrim sits behind so the
    // offer draws focus; still scrollable if several stack up.
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
            for (var i = 0; i < visible.length; i++)
              _OfferAlertCard(
                // Key by offer id so Flutter keeps each card's state as the
                // list shifts when one above it is dismissed.
                key: ValueKey(visible[i].offer.id),
                ref: widget.ref,
                offer: visible[i].offer,
                depth: i,
                onResolved: (a) => _resolve(visible[i], a),
              ),
            if (hidden > 0)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10),
                  ],
                ),
                child: Text('+$hidden more offer${hidden == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfferAlertCard extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Offer offer;
  final int depth; // 0 = front/top
  final void Function(String action) onResolved;
  final Duration window;
  const _OfferAlertCard({
    super.key,
    required this.ref,
    required this.offer,
    required this.depth,
    required this.onResolved,
    this.window = const Duration(seconds: 30),
  });

  @override
  ConsumerState<_OfferAlertCard> createState() => _OfferAlertCardState();
}

class _OfferAlertCardState extends ConsumerState<_OfferAlertCard>
    with TickerProviderStateMixin {
  late final AnimationController _bar; // countdown
  late final AnimationController _appear; // slide/fade in & out
  bool _busy = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _appear = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 260))
      ..forward();
    _bar = AnimationController(vsync: this, duration: widget.window)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted && !_busy) {
          _dismiss('later');
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _bar.dispose();
    _appear.dispose();
    super.dispose();
  }

  Future<void> _dismiss(String action) async {
    if (_dismissing) return;
    _dismissing = true;
    _bar.stop();
    try {
      await _appear.reverse();
    } catch (_) {}
    widget.onResolved(action);
  }

  Future<void> _decide(bool accept) async {
    if (_busy || _dismissing) return;
    String? reason;
    if (!accept) {
      // Freeze the countdown: it would otherwise fire _dismiss('later') and rip
      // this card out from under the prompt that is still open.
      _bar.stop();
      // Hide the stack so the prompt isn't rendered underneath it — see
      // OfferAlertOverlay.suspended.
      OfferAlertOverlay.instance.suspended.value = true;
      try {
        reason = await showDeclineReasonDialog(context, title: 'Decline offer');
      } finally {
        OfferAlertOverlay.instance.suspended.value = false;
      }
      if (reason == null) {
        // Cancelled — put the card back and resume its countdown.
        if (mounted) _bar.forward();
        return;
      }
      if (!mounted) return;
    }
    setState(() => _busy = true);
    _bar.stop();
    final repo = ref.read(partnerRepositoryProvider);
    try {
      if (accept) {
        await repo.acceptOffer(widget.offer.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineOffer(widget.offer.id,
            reason: reason!.isEmpty ? null : reason);
        AppToast.success('Declined — passed to the next partner');
      }
      await _dismiss(accept ? 'accept' : 'decline');
    } on ApiException catch (e) {
      AppToast.error(e.message);
      if (mounted) {
        setState(() => _busy = false);
        _bar.forward();
      }
    } catch (_) {
      AppToast.error('Something went wrong');
      if (mounted) {
        setState(() => _busy = false);
        _bar.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Deeper cards sit slightly smaller + dimmer, giving the "stack" look.
    final scale = 1.0 - widget.depth * 0.03;
    final dim = 1.0 - widget.depth * 0.12;
    return AnimatedBuilder(
      animation: _appear,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_appear.value);
        return Opacity(
          opacity: (t * dim).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -24),
            child: Transform.scale(scale: scale * (0.96 + 0.04 * t), child: child),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _card(),
      ),
    );
  }

  Widget _card() {
    final o = widget.offer;
    final secs = widget.window.inSeconds;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 26,
              offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: AnimatedBuilder(
              animation: _bar,
              builder: (_, __) {
                final remaining = (1 - _bar.value).clamp(0.0, 1.0);
                final col = remaining < 0.33
                    ? AppColors.rose
                    : (remaining < 0.66
                        ? AppColors.amber
                        : AppColors.brand600);
                return LinearProgressIndicator(
                  value: remaining,
                  minHeight: 6,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(col),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt_rounded,
                              size: 15, color: AppColors.brand700),
                          const SizedBox(width: 3),
                          Text('NEW OFFER',
                              style: TextStyle(
                                  color: AppColors.brand700,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                  letterSpacing: 0.5)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    AnimatedBuilder(
                      animation: _bar,
                      builder: (_, __) {
                        final left = (secs - (_bar.value * secs))
                            .ceil()
                            .clamp(0, secs);
                        return Text('${left}s',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: 13));
                      },
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _busy ? null : () => _dismiss('later'),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(Icons.close_rounded,
                            size: 20, color: AppColors.textFaint),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ServiceTitle(o.serviceName, titleSize: 17),
                const SizedBox(height: 6),
                if (o.address.isNotEmpty)
                  _row(Icons.place_outlined, o.address),
                if (o.crewRequired > 0)
                  _row(
                      Icons.group_outlined,
                      '${o.crewRequired} ${o.crewRequired == 1 ? "person" : "people"}'
                      '${o.vanName.isNotEmpty ? " · ${o.vanName}" : ""}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('You earn',
                        style: TextStyle(
                            color: AppColors.textMuted, fontSize: 13)),
                    const Spacer(),
                    Text('AED ${o.earnings.toStringAsFixed(2)}',
                        style: TextStyle(
                            color: AppColors.brand700,
                            fontWeight: FontWeight.w800,
                            fontSize: 19)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => _decide(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.rose,
                          side: BorderSide(
                              color: AppColors.rose.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Decline',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _busy ? null : () => _decide(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brand600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.2, color: Colors.white))
                            : const Text('Accept',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13.5)),
            ),
          ],
        ),
      );
}
