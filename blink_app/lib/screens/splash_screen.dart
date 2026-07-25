import 'package:flutter/material.dart';
import '../theme/blink_theme.dart';
import '../widgets/dotted_logo.dart';

/// Animated splash screen displayed on app launch.
/// Shows the BLINK dot-matrix logo with a scanning red accent line,
/// then smoothly transitions to the main app.
class SplashScreen extends StatefulWidget {
  final Widget child;

  const SplashScreen({super.key, required this.child});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _lineController;
  late AnimationController _fadeController;
  late Animation<double> _logoOpacity;
  late Animation<double> _logoScale;
  late Animation<double> _lineProgress;
  late Animation<double> _versionOpacity;
  late Animation<double> _fadeOut;

  bool _showMain = false;

  @override
  void initState() {
    super.initState();

    // Logo fade-in + scale
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );

    // Red scanning line
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _lineProgress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _lineController, curve: Curves.easeInOut),
    );

    // Version text fade
    _versionOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _lineController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // Fade out transition
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeIn),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // Small delay for the engine to settle
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Phase 1: Logo fades in
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    // Phase 2: Red line scans across
    _lineController.forward();
    await Future.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;

    // Phase 3: Fade out splash, reveal main app
    _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    setState(() => _showMain = true);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _lineController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showMain) {
      return widget.child;
    }

    return Material(
      color: BlinkColors.background,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _logoController,
          _lineController,
          _fadeController,
        ]),
        builder: (context, _) {
          return Opacity(
            opacity: _fadeOut.value,
            child: Stack(
              children: [
                // ── Centered Logo ─────────────────────────────────
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo with scale + opacity animation
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: const DottedLogo(
                            dotSize: 5.0,
                            spacing: 3.0,
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Red Scanning Line ─────────────────────────
                      SizedBox(
                        width: 160,
                        height: 2,
                        child: CustomPaint(
                          painter: _ScanLinePainter(
                            progress: _lineProgress.value,
                            color: BlinkColors.accent,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── Version Text ──────────────────────────────
                      Opacity(
                        opacity: _versionOpacity.value,
                        child: Text(
                          'COMPANION APP',
                          style: BlinkTypography.labelSmall.copyWith(
                            letterSpacing: 6.0,
                            fontSize: 9,
                            color: BlinkColors.textTertiary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Bottom version ────────────────────────────────
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 40,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: _versionOpacity.value,
                    child: Center(
                      child: Text(
                        'v4.0.1',
                        style: BlinkTypography.mono.copyWith(
                          fontSize: 11,
                          color: BlinkColors.textTertiary.withValues(alpha: 0.5),
                          letterSpacing: 2.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Paints a scanning red line that sweeps left to right.
class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color,
          color,
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width * progress, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width * progress, size.height),
        const Radius.circular(1),
      ),
      paint,
    );

    // Glow effect at the leading edge
    if (progress < 1.0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      canvas.drawCircle(
        Offset(size.width * progress, size.height / 2),
        3,
        glowPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanLinePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
