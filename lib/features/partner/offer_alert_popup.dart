import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/app_toast.dart';
import 'partner_models.dart';
import 'partner_repository.dart';

/// inDrive-style in-app ALERT for a freshly-arrived dispatch offer.
///
/// Pops over whatever the partner is looking at, shows the offer summary with a
/// 30-second countdown bar, and lets them Accept / Decline right away — or
/// dismiss (X / tap-outside / timeout) to "decide later", in which case the
/// offer simply stays in the Requests tab. It is purely an attention-grabbing
/// alert; the Requests list remains the source of truth.
///
/// Returns the action taken: 'accept' | 'decline' | 'later'.
Future<String> showOfferAlert(
  BuildContext context,
  WidgetRef ref,
  Offer offer, {
  Duration window = const Duration(seconds: 30),
}) async {
  final res = await showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'New offer',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
      return Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.92 + 0.08 * curved.value,
          child: Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _OfferAlertCard(
                ref: ref, offer: offer, window: window),
            ),
          ),
        ),
      );
    },
  );
  return res ?? 'later';
}

class _OfferAlertCard extends ConsumerStatefulWidget {
  final WidgetRef ref;
  final Offer offer;
  final Duration window;
  const _OfferAlertCard(
      {required this.ref, required this.offer, required this.window});

  @override
  ConsumerState<_OfferAlertCard> createState() => _OfferAlertCardState();
}

class _OfferAlertCardState extends ConsumerState<_OfferAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bar;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bar = AnimationController(vsync: this, duration: widget.window)
      ..addStatusListener((s) {
        // Auto-dismiss as "decide later" when the bar runs out.
        if (s == AnimationStatus.completed && mounted && !_busy) {
          Navigator.of(context).maybePop('later');
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  Future<void> _decide(bool accept) async {
    if (_busy) return;
    setState(() => _busy = true);
    _bar.stop();
    final repo = ref.read(partnerRepositoryProvider);
    try {
      if (accept) {
        await repo.acceptOffer(widget.offer.id);
        AppToast.success('Booking accepted');
      } else {
        await repo.declineOffer(widget.offer.id);
        AppToast.success('Declined — passed to the next partner');
      }
      if (mounted) Navigator.of(context).pop(accept ? 'accept' : 'decline');
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
    final o = widget.offer;
    final secs = widget.window.inSeconds;
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
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
          children: [
            // Countdown bar (top edge).
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
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
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
                          final left =
                              (secs - (_bar.value * secs)).ceil().clamp(0, secs);
                          return Text('${left}s',
                              style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13));
                        },
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: _busy
                            ? null
                            : () => Navigator.of(context).maybePop('later'),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(Icons.close_rounded,
                              size: 20, color: AppColors.textFaint),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(o.serviceName.isEmpty ? 'Service' : o.serviceName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                  const SizedBox(height: 8),
                  if (o.address.isNotEmpty)
                    _row(Icons.place_outlined, o.address),
                  if (o.crewRequired > 0)
                    _row(Icons.group_outlined,
                        '${o.crewRequired} ${o.crewRequired == 1 ? "person" : "people"}'
                        '${o.vanName.isNotEmpty ? " · ${o.vanName}" : ""}'),
                  const SizedBox(height: 10),
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
                              fontSize: 20)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _decide(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.rose,
                            side: BorderSide(
                                color: AppColors.rose.withValues(alpha: 0.5)),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Decline',
                              style:
                                  TextStyle(fontWeight: FontWeight.w700)),
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
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
