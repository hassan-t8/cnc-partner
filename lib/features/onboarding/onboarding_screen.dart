import 'package:flutter/material.dart';
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
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _slides.length - 1;
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                              color: AppColors.brand50, shape: BoxShape.circle),
                          child: Icon(s.icon,
                              size: 56, color: AppColors.brand600),
                        ),
                        const SizedBox(height: 32),
                        Text(s.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Text(s.body,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                                height: 1.5)),
                      ],
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
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 50,
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
            const BrandLogo(size: 28),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
