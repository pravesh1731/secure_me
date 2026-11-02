import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_shell.dart';
import 'screens/locked_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/session.dart';
import 'widgets/common.dart';

const _onboardingSeenKey = 'onboarding_seen';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  final session = Session();
  runApp(SecureMeApp(session: session, prefs: prefs));
  await session.init();
}

class SecureMeApp extends StatelessWidget {
  const SecureMeApp({super.key, required this.session, required this.prefs});
  final Session session;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      session: session,
      child: MaterialApp(
        title: 'Secure-Me',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: _Root(prefs: prefs),
      ),
    );
  }
}

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final base = ColorScheme.fromSeed(seedColor: Brand.navy, brightness: brightness);
  final accent = ColorScheme.fromSeed(seedColor: Brand.coral, brightness: brightness);
  // Navy drives the scheme; the logo's coral is the accent (tertiary roles).
  // In dark mode primary stays the lighter navy tone so it reads on dark surfaces.
  final scheme = base.copyWith(
    primary: light ? Brand.navy : null,
    onPrimary: light ? Colors.white : null,
    tertiary: Brand.coral,
    onTertiary: Colors.white,
    tertiaryContainer: accent.primaryContainer,
    onTertiaryContainer: accent.onPrimaryContainer,
  );
  final background = light ? const Color(0xFFF4F6FB) : scheme.surface;
  final typography = ThemeData(brightness: brightness).textTheme;
  final textTheme = typography.copyWith(
    headlineMedium: typography.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
    headlineSmall: typography.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
    titleLarge: typography.titleLarge?.copyWith(fontWeight: FontWeight.w700),
    titleMedium: typography.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: typography.labelLarge?.copyWith(fontWeight: FontWeight.w600),
  );
  const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)));
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  OutlineInputBorder inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    textTheme: textTheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleSpacing: 16,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: light ? 0.35 : 0.5),
      border: inputBorder(scheme.outlineVariant),
      enabledBorder: inputBorder(scheme.outlineVariant),
      focusedBorder: inputBorder(scheme.primary, 2),
      errorBorder: inputBorder(scheme.error),
      focusedErrorBorder: inputBorder(scheme.error, 2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Brand.coral,
      linearTrackColor: Brand.coral.withValues(alpha: 0.15),
      linearMinHeight: 5,
      borderRadius: BorderRadius.circular(4),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: buttonShape, padding: buttonPadding, textStyle: textTheme.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: buttonShape, padding: buttonPadding, textStyle: textTheme.labelLarge),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: buttonShape, textStyle: textTheme.labelLarge),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: light ? Brand.navy : scheme.primaryContainer,
        selectedForegroundColor: light ? Colors.white : scheme.onPrimaryContainer,
        textStyle: textTheme.labelLarge,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: light ? 0.6 : 1)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : scheme.surfaceContainer,
      indicatorColor: Brand.coral.withValues(alpha: light ? 0.16 : 0.28),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: background,
      indicatorColor: Brand.coral.withValues(alpha: light ? 0.16 : 0.28),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light ? Brand.navy : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6)),
  );
}

/// Switches between onboarding, auth, lock and home based on [Session.status],
/// with a blocking progress overlay while keys are generated or unwrapped.
class _Root extends StatefulWidget {
  const _Root({required this.prefs});
  final SharedPreferences prefs;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  late bool _showOnboarding = !(widget.prefs.getBool(_onboardingSeenKey) ?? false);

  void _finishOnboarding() {
    setState(() => _showOnboarding = false);
    widget.prefs.setBool(_onboardingSeenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    final page = switch (session.status) {
      SessionStatus.loading => const _Splash(),
      // Only signed-out users see the intro, so existing users aren't interrupted.
      SessionStatus.signedOut when _showOnboarding => OnboardingScreen(onDone: _finishOnboarding),
      SessionStatus.signedOut => const AuthScreen(),
      SessionStatus.locked => const LockedScreen(),
      SessionStatus.ready => const HomeShell(),
    };
    return Stack(
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: page),
        if (session.busyMessage != null) BusyOverlay(message: session.busyMessage!),
      ],
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 96),
            SizedBox(height: 28),
            SizedBox(width: 120, child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
