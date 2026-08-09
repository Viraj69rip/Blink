import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'providers/robot_state_provider.dart';
import 'services/firmware_update_service.dart';
import 'services/weather_mood_service.dart';
import 'theme/blink_theme.dart';

import 'navigation/blink_nav_bar.dart';

import 'screens/splash_screen.dart';
import 'screens/command_center_screen.dart';
import 'screens/drawing_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/about_screen.dart';

/// BLINK — Desktop Robot Companion App
///
/// A Nothing OS–inspired control interface for the BLINK robot,
/// powered by ESP32-C3 with BLE connectivity.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirmwareUpdateService.instance.initialize();

  // Lock to portrait orientation for optimal layout
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

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
            itemCount: 4,
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
    final child = switch (index) {
      0 => const CommandCenterScreen(key: PageStorageKey('command')),
      1 => const DrawingScreen(key: PageStorageKey('draw')),
      2 => const SettingsScreen(key: PageStorageKey('settings')),
      3 => const AboutScreen(key: PageStorageKey('about')),
      _ => throw RangeError.index(index, const [0, 1, 2, 3]),
    };

    // Offscreen tabs keep their scroll state but no longer consume animation
    // frames. Small, local repaint boundaries inside animated widgets isolate
    // their paint work without forcing a whole tab to repaint.
    return TickerMode(enabled: _currentIndex == index, child: child);
  }
}
