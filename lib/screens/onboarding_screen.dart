// FILE: lib/screens/onboarding_screen.dart
/// §2 — three onboarding pages with Skip / Next, shown once per install.
///
/// The flag is [AppConstants.keyOnboarded]; the splash screen checks it before
/// deciding where to send the user, so the pages cannot reappear after the
/// first completed run.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/role_colors.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_OnboardPage> _pages = <_OnboardPage>[
    _OnboardPage(
      icon: Icons.sos_rounded,
      color: RoleColors.user,
      title: 'Roadside help,\nthree taps away',
      body:
          'Flat tyre, dead battery, empty tank or a breakdown. Tell RoadResQ '
          'what happened and a verified crew is dispatched to your GPS '
          'position.',
    ),
    _OnboardPage(
      icon: Icons.local_shipping_rounded,
      color: RoleColors.mechanic,
      title: 'Watch the crew\ncome to you',
      body:
          'Live map, live status and live ETA. Chat with the mechanic, call '
          'them directly, and confirm arrival with a one-time 6-digit token '
          'so nobody can claim a job they did not attend.',
    ),
    _OnboardPage(
      icon: Icons.handshake_rounded,
      color: RoleColors.assistant,
      title: 'Earn as a crew\npartner',
      body:
          'Mechanics and assistants get a job feed, navigation, attendance and '
          'transparent earnings. One account, four roles — you choose how you '
          'work.',
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstants.keyOnboarded, true);
    } catch (_) {
      // Onboarding preference is a convenience, not a gate. Continue anyway so
      // a storage failure cannot trap the user on this screen.
    }
    if (!mounted) return;
    context.go('/role-select');
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _pages[_page];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  _isLast ? 'Done' : 'Skip',
                  style: const TextStyle(inherit: true),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final item = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: RoleColors.tint(item.color, opacity: 0.12),
                            border: Border.all(
                              color: RoleColors.tint(item.color, opacity: 0.4),
                              width: 2,
                            ),
                          ),
                          child: Icon(item.icon, size: 64, color: item.color),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          item.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            inherit: true,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          item.body,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            inherit: true,
                            color: RoleColors.neutral,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                final active = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? page.color : RoleColors.tint(page.color, opacity: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                );
              }),
            ),
            const SizedBox(height: 26),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: page.color),
                  onPressed: _next,
                  child: Text(
                    _isLast ? 'Get started' : 'Next',
                    style: const TextStyle(
                      inherit: true,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage {
  const _OnboardPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;
}
