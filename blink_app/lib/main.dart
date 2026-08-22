import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/robot_state_provider.dart';
import 'services/weather_mood_service.dart';
import 'theme/blink_theme.dart';
import 'utils/app_info.dart';

import 'navigation/blink_nav_bar.dart';

import 'screens/splash_screen.dart';
import 'screens/command_center_screen.dart';
import 'screens/drawing_screen.dart';
import 'screens/expression_vault_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/about_screen.dart';

/// BLINK — Desktop Robot Companion App
///
/// A Nothing OS–inspired control interface for the BLINK robot,
/// powered by ESP32-C3 with BLE connectivity.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Global error boundaries.
  //
  // The app previously had none, so a single throw on a background/plugin path
  // silently killed startup with no diagnostic.  Both handlers below swallow
  // the failure and keep the UI alive; `adb logcat -s flutter` shows the cause.
  // ---------------------------------------------------------------------------
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('[BLINK] Flutter error: ${details.exception}');
    if (details.stack != null) debugPrint('${details.stack}');
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('[BLINK] Uncaught async error: $error');
    debugPrint('$stack');
    // Returning true marks the error handled so the isolate is not torn down.
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) => const _BlinkErrorPane();

  // Never gate the first frame on platform services.  In particular, Android
  // can recreate the activity after an OTA/install intent while plugins are
  // still attaching.  RobotStateProvider starts the non-critical background
  // services once the widget tree is alive.
  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]));

  // Same reasoning: the version is only needed once Settings/About are on
  // screen, and AppInfo serves a correct fallback until this resolves.
  unawaited(AppInfo.load());

  // Set system UI overlay style — pure black status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: BlinkColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const BlinkApp());
}

/// Replaces the default grey/red error box so a single bad subtree never
/// presents the user with an unreadable release-mode error rectangle.
class _BlinkErrorPane extends StatelessWidget {
  const _BlinkErrorPane();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: BlinkColors.background,
      child: Center(
        child: Icon(
          Icons.error_outline_rounded,
          color: BlinkColors.textTertiary,
          size: 28,
        ),
      ),
    );
  }
}

/// Root application widget.
/// Wraps the app with Provider for reactive state management.
class BlinkApp extends StatelessWidget {
  const BlinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RobotStateProvider()),
        ChangeNotifierProvider.value(value: WeatherMoodService.instance),
      ],
      child: MaterialApp(
        title: 'BLINK',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: BlinkColors.background,
          colorScheme: const ColorScheme.dark(
            surface: BlinkColors.background,
            primary: BlinkColors.accent,
          ),
          // Disable default Material splash/ripple for custom interactions
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          // Custom page transitions
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: CupertinoPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        home: const SplashScreen(
          child: BlinkHome(),
        ),
      ),
    );
  }
}

/// Main home screen — manages page switching via custom glass bottom nav.
/// Uses PageView for smooth left-right slide transitions between tabs.
class BlinkHome extends StatefulWidget {
  const BlinkHome({super.key});

  @override
  State<BlinkHome> createState() => _BlinkHomeState();
}

class _BlinkHomeState extends State<BlinkHome> {
  int _currentIndex = 0;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;

    final currentPage = _pageController.hasClients
        ? _pageController.page ?? _currentIndex.toDouble()
        : _currentIndex.toDouble();
    final distance = (index - currentPage).abs();

    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 220 + (distance * 60).round()),
      curve: Curves.easeOutQuart,
    );
  }

  void _onPageChanged(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BlinkColors.background,
      // Use Stack + Positioned for glass nav bar overlay effect
      body: Stack(
        children: [
          // Page content with swipe transitions
          PageView.builder(
            controller: _pageController,
            itemCount: BlinkNavBar.tabCount,
            onPageChanged: _onPageChanged,
            // Tab changes are deliberately handled by the navbar. This keeps
            // vertical scrolling inside a screen from accidentally changing
            // pages when a drag has a slight horizontal component.
            physics: const NeverScrollableScrollPhysics(),
            // A builder creates a tab only when it is needed. This avoids
            // paying the layout and paint cost of every settings/vault card
            // during startup, while PageView retains visited tabs normally.
            itemBuilder: (context, index) => _buildTab(index),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: BlinkNavBar(
              currentIndex: _currentIndex,
              onTap: _onNavTap,
              pageController: _pageController,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index) {
    // Order must match BlinkNavBar's item list.
    final child = switch (index) {
      0 => const CommandCenterScreen(key: PageStorageKey('command')),
      1 => const DrawingScreen(key: PageStorageKey('draw')),
      2 => const ExpressionVaultScreen(key: PageStorageKey('vault')),
      3 => const SettingsScreen(key: PageStorageKey('settings')),
      4 => const AboutScreen(key: PageStorageKey('about')),
      _ => throw RangeError.index(index, const [0, 1, 2, 3, 4]),
    };

    // Offscreen tabs keep their scroll state but no longer consume animation
    // frames. Small, local repaint boundaries inside animated widgets isolate
    // their paint work without forcing a whole tab to repaint.
    return TickerMode(enabled: _currentIndex == index, child: child);
  }
}
