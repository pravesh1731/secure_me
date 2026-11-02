import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../crypto/rsa_keys.dart';
import '../services/session.dart';

class SessionScope extends InheritedNotifier<Session> {
  const SessionScope({super.key, required Session session, required super.child})
      : super(notifier: session);

  static Session of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessionScope>()!.notifier!;

  /// For callbacks: reads the session without subscribing to rebuilds.
  static Session read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()!.notifier!;
}

class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ColoredBox(
          color: Colors.black38,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandAnimation(LottieAssets.unlock, size: 120),
                      const SizedBox(height: 8),
                      Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 16),
                      const LinearProgressIndicator(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Constrains content to a readable width and centres it on large screens.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 720});
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.step, required this.title, this.subtitle, required this.child});
  final int? step;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              if (step != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Brand.coral, Brand.coralDeep]),
                  ),
                  child: Text('$step', style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ]),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Key fingerprint in monospace groups, e.g. `AB12 CD34 …`.
class FingerprintText extends StatelessWidget {
  const FingerprintText(this.fingerprint, {super.key, this.groups, this.style});
  final String fingerprint;
  final int? groups;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      formatFingerprint(fingerprint, groups: groups) + (groups != null ? ' …' : ''),
      style: (style ?? Theme.of(context).textTheme.bodySmall)?.copyWith(fontFamily: 'monospace', letterSpacing: 0.5),
    );
  }
}

/// Coloured info/warning/error banner.
class Notice extends StatelessWidget {
  const Notice({super.key, required this.icon, required this.text, this.tone = NoticeTone.info, this.child});
  final IconData icon;
  final String text;
  final NoticeTone tone;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      NoticeTone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      NoticeTone.success => (scheme.primaryContainer, scheme.onPrimaryContainer),
      NoticeTone.warning => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      NoticeTone.error => (scheme.errorContainer, scheme.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(text, style: TextStyle(color: fg)),
            if (child != null) ...[const SizedBox(height: 8), child!],
          ]),
        ),
      ]),
    );
  }
}

enum NoticeTone { info, success, warning, error }

IconData iconForMime(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.movie_outlined;
  if (mime.startsWith('audio/')) return Icons.audiotrack_outlined;
  if (mime.startsWith('text/')) return Icons.notes_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.insert_drive_file_outlined;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Colours sampled from the Secure-Me logo.
abstract final class Brand {
  static const navy = Color(0xFF1D3250);
  static const coral = Color(0xFFFA6146);

  // Derived shades for gradients.
  static const navyLight = Color(0xFF2F4C7E);
  static const coralDeep = Color(0xFFE8452B);

  static const heroGradient = LinearGradient(
    colors: [navy, navyLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

abstract final class LottieAssets {
  static const encrypt = 'assets/lottie/onboarding_encrypt.json';
  static const send = 'assets/lottie/onboarding_send.json';
  static const unlock = 'assets/lottie/onboarding_unlock.json';
  static const success = 'assets/lottie/success.json';
}

/// A brand Lottie animation, looping unless [repeat] is false.
class BrandAnimation extends StatelessWidget {
  const BrandAnimation(this.asset, {super.key, required this.size, this.repeat = true});
  final String asset;
  final double size;
  final bool repeat;

  @override
  Widget build(BuildContext context) {
    return Lottie.asset(asset, width: size, height: size, repeat: repeat, fit: BoxFit.contain);
  }
}

/// Soft circular backdrop for the Lottie illustrations. It stays light in dark
/// mode too, since the artwork uses the navy from the logo.
class IllustrationCircle extends StatelessWidget {
  const IllustrationCircle({super.key, required this.size, required this.child, this.tint = Brand.navy});
  final double size;
  final Color tint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFFEDF1F7) : Colors.white;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.035),
      decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: dark ? 0.25 : 0.07)),
      child: ClipOval(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [base, Color.alphaBlend(tint.withValues(alpha: 0.12), base)],
              radius: 0.75,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Navy gradient banner at the top of a page.
class GradientHeader extends StatelessWidget {
  const GradientHeader({super.key, required this.title, required this.subtitle, this.trailing});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Brand.navy.withValues(alpha: 0.16), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Stack(children: [
        const Positioned(left: -40, top: -60, child: _Glow(size: 140, color: Brand.coral, alpha: 0.12)),
        const Positioned(left: -24, bottom: -50, child: _Glow(size: 110, color: Colors.white, alpha: 0.06)),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: text.titleLarge?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(subtitle, style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.78))),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ]),
        ),
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color, required this.alpha});
  final double size;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: alpha)),
    );
  }
}

/// Decorative glow circles for full-bleed hero areas.
class HeroGlows extends StatelessWidget {
  const HeroGlows({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(children: [
      Positioned(right: -70, top: -70, child: _Glow(size: 200, color: Brand.coral, alpha: 0.13)),
      Positioned(left: -70, bottom: -90, child: _Glow(size: 200, color: Colors.white, alpha: 0.05)),
    ]);
  }
}

/// The logo mark (paper plane + padlock) on a white tile. The tile keeps the
/// navy padlock legible on dark surfaces.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(color: Brand.navy.withValues(alpha: 0.18), blurRadius: size * 0.2, offset: Offset(0, size * 0.05)),
        ],
      ),
      child: Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain, filterQuality: FilterQuality.medium),
    );
  }
}

/// "Secure-Me" in the logo's two-tone style. "Secure" falls back to onSurface
/// in dark mode, where navy text would disappear; [onDark] is for navy banners.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.style, this.textAlign, this.onDark = false});
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secure = onDark
        ? Colors.white
        : theme.brightness == Brightness.light
            ? Brand.navy
            : theme.colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        style: (style ?? DefaultTextStyle.of(context).style).copyWith(fontWeight: FontWeight.w700),
        children: [
          TextSpan(text: 'Secure', style: TextStyle(color: secure)),
          const TextSpan(text: '-Me', style: TextStyle(color: Brand.coral)),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
