import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../widgets/common.dart';

const _pages = [
  (
    asset: LottieAssets.encrypt,
    tint: Brand.navy,
    title: 'Lock anything in seconds',
    body:
        'Messages, photos, videos and documents are encrypted on your device with '
        'AES-256 before they go anywhere.',
  ),
  (
    asset: LottieAssets.send,
    tint: Brand.coral,
    title: 'Send it any way you like',
    body:
        'Share the encrypted file over WhatsApp, email or USB. It never touches our '
        'servers and is useless to anyone else.',
  ),
  (
    asset: LottieAssets.unlock,
    tint: Brand.navy,
    title: 'Only they hold the key',
    body:
        'Only your recipient\'s private key can open it, and any tampering along the '
        'way is detected.',
  ),
];

/// First-run introduction: three animated pages, then [onDone].
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) return widget.onDone();
    _controller.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(
                    children: [
                      const AppLogo(size: 34),
                      const SizedBox(width: 10),
                      BrandWordmark(style: theme.textTheme.titleMedium),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(onPressed: _isLast ? null : widget.onDone, child: const Text('Skip')),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => _OnboardingPage(index: i, controller: _controller),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    children: [
                      _Dots(count: _pages.length, index: _index),
                      const Spacer(),
                      FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_isLast ? 'Get started' : 'Next'),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({required this.index, required this.controller});
  final int index;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _pages[index];
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // -1..1 as the page slides out; drives a light parallax and fade.
        final offset = controller.hasClients && controller.position.haveDimensions
            ? (controller.page! - index).clamp(-1.0, 1.0)
            : 0.0;
        final visibility = 1 - offset.abs();
        return LayoutBuilder(
          builder: (context, constraints) {
            final art = math.min(constraints.maxWidth - 48, constraints.maxHeight * 0.58).clamp(120.0, 340.0);
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.translate(
                      offset: Offset(offset * -60, 0),
                      child: Transform.scale(
                        scale: 0.85 + 0.15 * visibility,
                        child: IllustrationCircle(
                          size: art,
                          tint: page.tint,
                          child: BrandAnimation(page.asset, size: art),
                        ),
                      ),
                    ),
                    SizedBox(height: art * 0.12),
                    Opacity(
                      opacity: visibility,
                      child: Transform.translate(
                        offset: Offset(offset * 30, 0),
                        child: Column(
                          children: [
                            Text(page.title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 12),
                            Text(
                              page.body,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(right: 8),
            width: i == index ? 28 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index ? Brand.coral : inactive,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
