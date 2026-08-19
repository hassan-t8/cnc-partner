import 'package:flutter/material.dart';
import '../../core/notifications/push_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/brand_logo.dart';

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide(this.icon, this.title, this.body);
}

const _slides = [
  _Slide(Icons.inbox_outlined, 'Get job offers instantly',
      'Accept or decline dispatch offers in seconds, right from your phone.'),
  _Slide(Icons.checklist_outlined, 'Run jobs on the go',
      'Start with a customer code, capture before/after photos, and complete jobs.'),
  _Slide(Icons.groups_outlined, 'Manage your team',
      'Add workers and vans, track earnings, and keep your ratings high.'),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(authStorageProvider).setOnboarded();

    // Ask for notifications here, as onboarding ends, rather than after the
    // login wall. On iOS no permission means no APNs token, no APNs token
    // means no FCM token, and without one the device never registers at all
    // — so an install that has not signed in cannot be reached by a
    // broadcast. Registration follows the prompt because the token only
    // becomes obtainable once permission is granted.
    //
    // Declining is a normal answer and must not hold anyone at this screen,
    // so nothing here is allowed to throw.
    try {
      // Awaited: navigating out from under the system prompt would leave the
      // dialog floating over the next screen.
      await PushService.instance.requestPermission();
    } catch (_) {}
    // NOT awaited — a token fetch plus a network round trip, which held the
    // user on the last slide for as long as it took and has no bearing on
    // what happens next.
    PushService.instance.registerDeviceAnonymously();

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;

    // Landscape on a phone leaves roughly 360dp of height for the whole page.
    // The fixed chrome (Skip, dots, CTA, logo) took ~200 of it, and the slide
    // art alone was 255 — hence the bottom overflow. Everything below shrinks
    // on a short viewport rather than being clipped.
    final compact = MediaQuery.sizeOf(context).height < 560;
    final circle = compact ? 84.0 : 120.0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                  onPressed: _finish, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  // LayoutBuilder + scroll view: the slide still centres when
                  // there's room, and scrolls instead of overflowing when a
                  // large system font or a very short window leaves none.
                  return LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                          horizontal: 32, vertical: compact ? 8 : 0),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            minHeight:
                                box.maxHeight - (compact ? 16 : 0)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: circle,
                              height: circle,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                  color: AppColors.brand50,
                                  shape: BoxShape.circle),
                              child: Icon(s.icon,
                                  size: compact ? 40 : 56,
                                  color: AppColors.brand600),
                            ),
                            SizedBox(height: compact ? 16 : 32),
                            Text(s.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: compact ? 18 : 22,
                                    fontWeight: FontWeight.w800)),
                            SizedBox(height: compact ? 8 : 12),
                            Text(s.body,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: compact ? 13 : 14,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? AppColors.brand600
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 24, vertical: compact ? 10 : 24),
              child: SizedBox(
                width: double.infinity,
                height: compact ? 44 : 50,
                child: ElevatedButton(
                  onPressed: () {
                    if (last) {
                      _finish();
                    } else {
                      _controller.nextPage(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOut);
                    }
                  },
                  child: Text(last ? 'Get started' : 'Next'),
                ),
              ),
            ),
            // The logo is the first thing worth losing when height is scarce —
            // it's decoration, and the CTA below it is not.
            if (!compact) ...[
              const BrandLogo(size: 28),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
