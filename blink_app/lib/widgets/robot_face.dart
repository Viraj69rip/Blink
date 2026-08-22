import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../models/robot_animation_snapshot.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';
import '../utils/text_painter_cache.dart';

/// Stylized robot face widget with animated blinking eyes.
/// When connected, mirrors live ESP32 OLED state over BLE (~10 Hz + extrapolation).
/// When offline, runs the same night yawn → 2 min sleep cycle locally.
class RobotFace extends StatefulWidget {
  const RobotFace({super.key});

  @override
  State<RobotFace> createState() => _RobotFaceState();
}

class _RobotFaceState extends State<RobotFace> with TickerProviderStateMixin {
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;
  late AnimationController _yawnController;
  late Animation<double> _yawnAnimation;
  final Random _random = Random();

  Timer? _nextBlinkTimer;
  Timer? _nightCheckTimer;
  Timer? _sleepWakeTimer;

  /// Repaint clock for the two states that animate off nothing but the wall
  /// clock: a synced face (extrapolated between ~10 Hz snapshots) and the local
  /// sleep loop. A [Ticker] rather than a `Timer.periodic` so the repaints land
  /// on the frame pipeline instead of drifting against it, and so they stop
  /// automatically while the app is backgrounded or this route is offscreen.
  late final Ticker _ticker;
  bool _tickerRunning = false;
  Duration _lastTick = Duration.zero;

  double _sleepPhase = 0;
  bool _localNightYawn = false;
  bool _wasSynced = false;

  bool get _localIsNight {
    final hour = DateTime.now().hour;
    return hour >= BlinkConstants.nightStartHour ||
        hour < BlinkConstants.nightEndHour;
  }

  @override
  void initState() {
    super.initState();

    _blinkController = AnimationController(
      vsync: this,
      duration: BlinkConstants.blinkDuration,
    );
    _blinkAnimation = Tween<double>(begin: 1.0, end: 0.05).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );

    _yawnController = AnimationController(
      vsync: this,
      duration: BlinkConstants.yawnDuration,
    );
    _yawnAnimation = CurvedAnimation(
      parent: _yawnController,
      curve: Curves.easeInOut,
    );

    _blinkController.addStatusListener((status) {
      if (_localFaceState != RobotFaceState.idle) return;
      if (status == AnimationStatus.completed) {
        _blinkController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _scheduleNextBlink();
      }
    });

    _yawnController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _enterLocalSleep();
      }
    });

    _scheduleNextBlink();
    _startNightChecks();
    _ticker = createTicker(_onTick);
  }

  /// Advances the wall-clock-driven parts of the face. [elapsed] is monotonic
  /// from the moment the ticker started, so the sleep phase now tracks real
  /// time instead of accumulating one timer callback's worth of drift each tick.
  void _onTick(Duration elapsed) {
    final dt = elapsed - _lastTick;
    _lastTick = elapsed;
    if (_localFaceState == RobotFaceState.sleep) {
      // The old 50 ms timer added 0.05 per tick, i.e. exactly 1.0 per second —
      // the same unit the synced path derives from `elapsedMs / 1000`.
      setState(() => _sleepPhase += dt.inMicroseconds / 1000000.0);
      return;
    }
    if (_wasSynced) setState(() {});
  }

  /// Runs the ticker only while something actually needs per-frame repaints.
  void _syncTicker() {
    final wanted =
        _wasSynced || _localFaceState == RobotFaceState.sleep;
    if (wanted == _tickerRunning) return;
    _tickerRunning = wanted;
    if (wanted) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final synced = context.read<RobotStateProvider>().isRobotSynced;
    if (_wasSynced && !synced) {
      _localNightYawn = false;
      _yawnController.reset();
      _sleepWakeTimer?.cancel();
      _scheduleNextBlink();
    }
    _wasSynced = synced;
    _syncTicker();
  }

  RobotFaceState get _localFaceState {
    if (_localNightYawn) {
      if (_yawnController.isAnimating ||
          (_yawnController.value > 0 && _yawnController.value < 1)) {
        return RobotFaceState.yawn;
      }
      if (_sleepWakeTimer?.isActive == true) return RobotFaceState.sleep;
    }
    return RobotFaceState.idle;
  }

  void _startNightChecks() {
    _nightCheckTimer?.cancel();
    _nightCheckTimer = Timer.periodic(BlinkConstants.nightCheckInterval, (_) {
      if (!mounted) return;
      if (context.read<RobotStateProvider>().isRobotSynced) return;
      if (!_localIsNight) return;
      if (_localFaceState != RobotFaceState.idle) return;
      if (_random.nextInt(100) < BlinkConstants.nightYawnChance) {
        _startLocalYawn();
      }
    });
  }

  void _startLocalYawn() {
    _localNightYawn = true;
    _nextBlinkTimer?.cancel();
    _blinkController.stop();
    _yawnController.forward(from: 0);
    setState(() {});
  }

  void _enterLocalSleep() {
    _yawnController.stop();
    _sleepPhase = 0;
    _sleepWakeTimer?.cancel();
    _sleepWakeTimer = Timer(BlinkConstants.sleepDuration, _wakeFromLocalSleep);
    setState(() {});
    // Read after the timer is armed: `_localFaceState` only reports sleep once
    // `_sleepWakeTimer` is active.
    _syncTicker();
  }

  void _wakeFromLocalSleep() {
    if (!mounted) return;
    _localNightYawn = false;
    setState(() {});
    _syncTicker();
    _scheduleNextBlink();
  }

  void _scheduleNextBlink() {
    if (_localFaceState != RobotFaceState.idle) return;
    _nextBlinkTimer?.cancel();
    final isNight = _localIsNight;
    final minSec = isNight
        ? BlinkConstants.blinkIntervalMin + 1
        : BlinkConstants.blinkIntervalMin;
    final maxSec = isNight
        ? BlinkConstants.blinkIntervalMax + 2
        : BlinkConstants.blinkIntervalMax;
    final delay = Duration(
      milliseconds: (_random.nextInt(maxSec - minSec) + minSec) * 1000,
    );
    _nextBlinkTimer = Timer(delay, () {
      if (mounted && _localFaceState == RobotFaceState.idle) {
        _blinkController.forward(from: 0);
      }
    });
  }

  int _extrapolateMs(RobotAnimationSnapshot snapshot, int baseMs) {
    return baseMs +
        DateTime.now().difference(snapshot.receivedAt).inMilliseconds;
  }

  double _idleBlinkOpenness(int uptimeMs, bool isNight) {
    final period = isNight ? 4800 : 3200;
    final blinkLen = isNight ? 280 : 220;
    final baseEyeH = isNight ? 14.0 : 18.0;
    final cycle = uptimeMs % period;
    if (cycle <= period - blinkLen) return baseEyeH / 18.0;
    final p = (cycle - (period - blinkLen)) / blinkLen;
    final lid = p < 0.5
        ? Curves.easeInOut.transform(p * 2)
        : Curves.easeInOut.transform((1 - p) * 2);
    final eyeH = baseEyeH - lid * (baseEyeH - 2);
    return (eyeH / 18.0).clamp(0.05, 1.0);
  }

  double _yawnEyeOpenness(double p) {
    if (p < 0.22) return 1.0 - (p / 0.22) * 0.55;
    if (p < 0.58) return 0.45 - ((p - 0.22) / 0.36) * 0.38;
    return max(0.0, 0.07 - ((p - 0.58) / 0.42) * 0.06);
  }

  @override
  void dispose() {
    _nextBlinkTimer?.cancel();
    _nightCheckTimer?.cancel();
    _sleepWakeTimer?.cancel();
    _ticker.dispose();
    _blinkController.dispose();
    _yawnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncSnapshot = context.select<RobotStateProvider, RobotAnimationSnapshot?>(
      (p) => p.isRobotSynced ? p.robotAnimation : null,
    );

    if (syncSnapshot != null) {
      return _buildSyncedFace(syncSnapshot);
    }
    return _buildLocalFace();
  }

  Widget _buildSyncedFace(RobotAnimationSnapshot snapshot) {
    final faceState = snapshot.state;
    final isNight = snapshot.isNight;
    final elapsedMs = _extrapolateMs(snapshot, snapshot.elapsedMs);
    final uptimeMs = _extrapolateMs(snapshot, snapshot.uptimeMs);

    double eyeOpen;
    double yawnProgress = 0;
    double sleepPhase = elapsedMs / 1000.0;

    switch (faceState) {
      case RobotFaceState.boot:
        eyeOpen = 0.2;
      case RobotFaceState.idle:
        eyeOpen = _idleBlinkOpenness(uptimeMs, isNight);
      case RobotFaceState.tickled:
        eyeOpen = 0.85;
      case RobotFaceState.dizzy:
        eyeOpen = 0.7;
      case RobotFaceState.yawn:
        yawnProgress = (elapsedMs / BlinkConstants.yawnDuration.inMilliseconds)
            .clamp(0.0, 1.0);
        eyeOpen = _yawnEyeOpenness(yawnProgress);
      case RobotFaceState.sleep:
        eyeOpen = 0;
      case RobotFaceState.appMode:
        eyeOpen = snapshot.focusActive ? 0.45 : 0.65;
      case RobotFaceState.happy:
        eyeOpen = 0.9;
      case RobotFaceState.sad:
        eyeOpen = 0.55;
      case RobotFaceState.angry:
        eyeOpen = 0.8;
      case RobotFaceState.love:
        eyeOpen = 1.0;
    }

    return RepaintBoundary(
      child: CustomPaint(
        size: const Size(double.infinity, 200),
        painter: _RobotFacePainter(
          state: faceState,
          eyeOpenness: eyeOpen,
          yawnProgress: yawnProgress,
          sleepPhase: sleepPhase,
          animMs: faceState == RobotFaceState.idle ? uptimeMs : elapsedMs,
          isNight: isNight,
          focusActive: snapshot.focusActive,
          drawMode: snapshot.drawMode,
          eyeColor: BlinkColors.textPrimary,
          mouthColor: BlinkColors.textTertiary,
          accentColor: BlinkColors.accent,
        ),
      ),
    );
  }

  Widget _buildLocalFace() {
    return AnimatedBuilder(
      animation: Listenable.merge([_blinkAnimation, _yawnAnimation]),
      builder: (context, _) {
        final faceState = _localFaceState;
        final isNight = _localIsNight;

        double eyeOpen;
        double yawnProgress = 0;
        final sleepPhase = _sleepPhase;

        switch (faceState) {
          case RobotFaceState.yawn:
            yawnProgress = _yawnAnimation.value;
            eyeOpen = _yawnEyeOpenness(yawnProgress);
          case RobotFaceState.sleep:
            eyeOpen = 0;
          case RobotFaceState.idle:
            eyeOpen = _blinkAnimation.value * (isNight ? 0.78 : 1.0);
          default:
            eyeOpen = _blinkAnimation.value;
        }

        return RepaintBoundary(
          child: CustomPaint(
            size: const Size(double.infinity, 200),
            painter: _RobotFacePainter(
              state: faceState,
              eyeOpenness: eyeOpen,
              yawnProgress: yawnProgress,
              sleepPhase: sleepPhase,
              animMs: 0,
              isNight: isNight,
              focusActive: false,
              drawMode: false,
              eyeColor: BlinkColors.textPrimary,
              mouthColor: BlinkColors.textTertiary,
              accentColor: BlinkColors.accent,
            ),
          ),
        );
      },
    );
  }
}

class _RobotFacePainter extends CustomPainter {
  final RobotFaceState state;
  final double eyeOpenness;
  final double yawnProgress;
  final double sleepPhase;
  final int animMs;
  final bool isNight;
  final bool focusActive;
  final bool drawMode;
  final Color eyeColor;
  final Color mouthColor;
  final Color accentColor;

  _RobotFacePainter({
    required this.state,
    required this.eyeOpenness,
    required this.yawnProgress,
    required this.sleepPhase,
    required this.animMs,
    required this.isNight,
    required this.focusActive,
    required this.drawMode,
    required this.eyeColor,
    required this.mouthColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    switch (state) {
      case RobotFaceState.boot:
        _drawBoot(canvas, size);
        return;
      case RobotFaceState.sleep:
        _drawSleep(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.tickled:
        _drawTickled(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.dizzy:
        _drawDizzy(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.appMode:
        _drawAppMode(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.happy:
        _drawHappy(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.sad:
        _drawSad(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.angry:
        _drawAngry(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.love:
        _drawLove(canvas, size, centerX, centerY);
        return;
      case RobotFaceState.yawn:
      case RobotFaceState.idle:
        _drawStandardFace(canvas, size, centerX, centerY);
    }
  }

  // ── Expression faces (firmware states 7–10) ──────────────────
  //
  // These mirror the shapes the OLED draws so the in-app preview and the robot
  // read as the same character.  Kept deliberately simple: two eye forms plus a
  // mouth curve, because that is all a 128×64 monochrome panel can express.

  void _drawHappy(Canvas canvas, Size size, double cx, double cy) {
    final bounce = sin(animMs / 260.0).abs() * 3;
    final eyeY = cy - size.height * 0.06 - bounce;
    final spacing = size.width * 0.12;
    final arcPaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Happy eyes are upward arcs (^ ^), the classic Mochi smile-eye.
    for (final offset in [-spacing, spacing]) {
      final path = Path()
        ..moveTo(cx + offset - 15, eyeY + 7)
        ..quadraticBezierTo(cx + offset, eyeY - 11, cx + offset + 15, eyeY + 7);
      canvas.drawPath(path, arcPaint);
    }

    final smilePaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + size.height * 0.13 + bounce * 0.5),
        width: size.width * 0.2,
        height: size.height * 0.14,
      ),
      0.15,
      pi - 0.3,
      false,
      smilePaint,
    );

    final blush = Paint()..color = accentColor.withValues(alpha: 0.3);
    canvas.drawCircle(Offset(cx - size.width * 0.21, cy + 6), 4, blush);
    canvas.drawCircle(Offset(cx + size.width * 0.21, cy + 6), 4, blush);
  }

  void _drawSad(Canvas canvas, Size size, double cx, double cy) {
    // Slow droop, plus a tear that falls and resets.
    final droop = 2 + sin(animMs / 900.0) * 1.5;
    final eyeY = cy - size.height * 0.03 + droop;
    final spacing = size.width * 0.12;
    final eyeWidth = size.width * 0.14;
    final eyeHeight = size.height * 0.3 * eyeOpenness.clamp(0.0, 1.0);

    final eyePaint = Paint()..color = eyeColor;
    for (final offset in [-spacing, spacing]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + offset, eyeY),
            width: eyeWidth,
            height: eyeHeight.clamp(2.0, double.infinity),
          ),
          Radius.circular(eyeWidth * 0.3),
        ),
        eyePaint,
      );
    }

    // Sad brows slope inward and down.
    final browPaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - spacing - eyeWidth * 0.7, eyeY - eyeHeight * 0.5 - 14),
      Offset(cx - spacing + eyeWidth * 0.6, eyeY - eyeHeight * 0.5 - 6),
      browPaint,
    );
    canvas.drawLine(
      Offset(cx + spacing - eyeWidth * 0.6, eyeY - eyeHeight * 0.5 - 6),
      Offset(cx + spacing + eyeWidth * 0.7, eyeY - eyeHeight * 0.5 - 14),
      browPaint,
    );

    final tearProgress = (animMs % 2600) / 2600.0;
    if (tearProgress < 0.75) {
      final t = tearProgress / 0.75;
      final tearPaint = Paint()
        ..color = eyeColor.withValues(alpha: (1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(cx + spacing, eyeY + eyeHeight * 0.5 + 6 + t * 26),
        2.4,
        tearPaint,
      );
    }

    final frownPaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + size.height * 0.24),
        width: size.width * 0.17,
        height: size.height * 0.11,
      ),
      pi + 0.2,
      pi - 0.4,
      false,
      frownPaint,
    );
  }

  void _drawAngry(Canvas canvas, Size size, double cx, double cy) {
    // Fast, small tremor — reads as tension without becoming dizzy.
    final tremor = sin(animMs / 45.0) * 1.6;
    final eyeY = cy - size.height * 0.04;
    final spacing = size.width * 0.12;
    final eyeWidth = size.width * 0.15;
    final eyeHeight = size.height * 0.22 * eyeOpenness.clamp(0.0, 1.0);

    final eyePaint = Paint()..color = eyeColor;
    for (final offset in [-spacing, spacing]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + offset + tremor, eyeY),
            width: eyeWidth,
            height: eyeHeight.clamp(2.0, double.infinity),
          ),
          const Radius.circular(2),
        ),
        eyePaint,
      );
    }

    // Heavy brows angled down toward the nose.
    final browPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - spacing - eyeWidth * 0.7 + tremor, eyeY - eyeHeight - 6),
      Offset(cx - spacing + eyeWidth * 0.7 + tremor, eyeY - eyeHeight + 4),
      browPaint,
    );
    canvas.drawLine(
      Offset(cx + spacing - eyeWidth * 0.7 + tremor, eyeY - eyeHeight + 4),
      Offset(cx + spacing + eyeWidth * 0.7 + tremor, eyeY - eyeHeight - 6),
      browPaint,
    );

    // Gritted mouth: a short zigzag.
    final mouthPaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final mouthY = cy + size.height * 0.2;
    final halfWidth = size.width * 0.09;
    final path = Path()..moveTo(cx - halfWidth + tremor, mouthY);
    const steps = 4;
    for (var i = 1; i <= steps; i++) {
      final x = cx - halfWidth + (2 * halfWidth) * (i / steps) + tremor;
      path.lineTo(x, mouthY + (i.isEven ? -3.5 : 3.5));
    }
    canvas.drawPath(path, mouthPaint);
  }

  void _drawLove(Canvas canvas, Size size, double cx, double cy) {
    final pulse = 1 + sin(animMs / 320.0) * 0.12;
    final eyeY = cy - size.height * 0.05;
    final spacing = size.width * 0.12;

    for (final offset in [-spacing, spacing]) {
      _drawHeart(canvas, Offset(cx + offset, eyeY), 11 * pulse, eyeColor);
    }

    final smilePaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + size.height * 0.14),
        width: size.width * 0.16,
        height: size.height * 0.11,
      ),
      0.2,
      pi - 0.4,
      false,
      smilePaint,
    );

    // Small hearts drifting up and fading.
    for (var i = 0; i < 3; i++) {
      final cycle = ((animMs / 1500.0 + i * 0.33) % 1.0);
      final rise = Curves.easeOut.transform(cycle);
      final hx = cx + size.width * (0.2 + i * 0.04) + sin(cycle * pi * 2) * 5;
      final hy = cy - size.height * 0.05 - rise * 42;
      _drawHeart(
        canvas,
        Offset(hx, hy),
        3.5 + i,
        accentColor.withValues(alpha: (1 - rise).clamp(0.0, 1.0) * 0.8),
      );
    }
  }

  /// Filled heart centred on [center] with half-width [r].
  void _drawHeart(Canvas canvas, Offset center, double r, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()..moveTo(center.dx, center.dy + r * 0.9);
    path.cubicTo(
      center.dx - r * 1.5, center.dy - r * 0.3,
      center.dx - r * 0.55, center.dy - r * 1.3,
      center.dx, center.dy - r * 0.35,
    );
    path.cubicTo(
      center.dx + r * 0.55, center.dy - r * 1.3,
      center.dx + r * 1.5, center.dy - r * 0.3,
      center.dx, center.dy + r * 0.9,
    );
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawStandardFace(Canvas canvas, Size size, double centerX, double centerY) {
    final breath = sin((state == RobotFaceState.idle ? animMs : 0) / 700.0) * 2.5;
    final bob = state == RobotFaceState.idle ? breath : sin(yawnProgress * pi) * 1.2;
    final eyeY = centerY - size.height * 0.05 + bob;
    final eyeWidth = size.width * 0.15;
    final eyeHeight = size.height * 0.35 * eyeOpenness.clamp(0.0, 1.0);
    final eyeSpacing = size.width * 0.12;
    final eyeRadius = eyeWidth * 0.3;

    if (isNight) _drawMoon(canvas, size.width - 28, 22);

    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.fill;

    if (state == RobotFaceState.yawn &&
        yawnProgress > 0.25 &&
        yawnProgress < 0.72) {
      final browLift = sin((yawnProgress - 0.25) / 0.47 * pi) * 4;
      final browPaint = Paint()
        ..color = eyeColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(centerX - eyeSpacing - eyeWidth * 0.6, eyeY - eyeHeight - 8 - browLift),
        Offset(centerX - eyeSpacing + eyeWidth * 0.3, eyeY - eyeHeight - 10 - browLift),
        browPaint,
      );
      canvas.drawLine(
        Offset(centerX + eyeSpacing - eyeWidth * 0.3, eyeY - eyeHeight - 10 - browLift),
        Offset(centerX + eyeSpacing + eyeWidth * 0.6, eyeY - eyeHeight - 8 - browLift),
        browPaint,
      );
    }

    for (final cx in [centerX - eyeSpacing, centerX + eyeSpacing]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, eyeY),
            width: eyeWidth,
            height: eyeHeight.clamp(2.0, double.infinity),
          ),
          Radius.circular(eyeRadius),
        ),
        eyePaint,
      );
    }

    if (eyeOpenness > 0.5 && state == RobotFaceState.idle) {
      _drawEyeGrid(canvas, centerX, eyeY, eyeWidth, eyeHeight, eyeSpacing);
    }

    if (state == RobotFaceState.yawn) {
      _drawYawnMouth(canvas, centerX, centerY + bob, size);
    } else {
      final mouthPaint = Paint()
        ..color = mouthColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final mouthY = centerY + size.height * 0.22 + bob * 0.2;
      final mouthWidth = size.width * 0.08;
      canvas.drawLine(
        Offset(centerX - mouthWidth, mouthY),
        Offset(centerX + mouthWidth, mouthY),
        mouthPaint,
      );
    }

    _drawFaceDots(canvas, centerX, centerY);
  }

  void _drawSleep(Canvas canvas, Size size, double cx, double cy) {
    final breath = sin(sleepPhase / 2.4) * 2.0;
    final y = cy + breath;
    _drawClosedEyes(canvas, size, cx, y);
    _drawSleepSmile(canvas, cx, y, size);
    _drawFloatingZzz(canvas, size, cx, y);
    if (isNight) _drawMoon(canvas, size.width - 28, 22);
  }

  void _drawTickled(Canvas canvas, Size size, double cx, double cy) {
    final bounce = sin(animMs / 95.0).abs() * 5;
    final wobble = sin(animMs / 70.0) * 2;
    final eyeY = cy - size.height * 0.05 - bounce;
    final arcPaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (final offset in [-size.width * 0.12, size.width * 0.12]) {
      final path = Path();
      path.moveTo(cx + offset - 16 + wobble, eyeY + 8);
      path.quadraticBezierTo(
        cx + offset + wobble,
        eyeY - 10,
        cx + offset + 16 + wobble,
        eyeY + 8,
      );
      canvas.drawPath(path, arcPaint);
    }

    final smilePaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(cx, cy + size.height * 0.12 + bounce / 2),
        width: size.width * 0.22,
        height: size.height * 0.12,
      ),
      0.1,
      pi - 0.2,
      false,
      smilePaint,
    );

    final sparkle = Paint()..color = eyeColor;
    for (var s = 0; s < 5; s++) {
      final ang = animMs / 120.0 + s * 1.256;
      final sx = cx + cos(ang) * (size.width * 0.18 + s * 6);
      final sy = cy - size.height * 0.08 + sin(ang * 1.3) * (size.height * 0.08 + s * 2);
      canvas.drawCircle(Offset(sx, sy), 1.5, sparkle);
    }
  }

  void _drawDizzy(Canvas canvas, Size size, double cx, double cy) {
    final shakeX = sin(animMs / 70.0 * 2.1) * 4;
    final shakeY = cos(animMs / 70.0 * 1.6) * 3;
    final spiralPaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (final offset in [-size.width * 0.12, size.width * 0.12]) {
      var prev = Offset(cx + offset + shakeX, cy - size.height * 0.05 + shakeY);
      for (var i = 1; i <= 24; i++) {
        final r = i * 0.45;
        final ang = animMs / 70.0 + i * 0.45 * (offset < 0 ? 1 : -1);
        final next = Offset(
          cx + offset + shakeX + cos(ang) * r,
          cy - size.height * 0.05 + shakeY + sin(ang) * r,
        );
        canvas.drawLine(prev, next, spiralPaint);
        prev = next;
      }
    }

    final mouthPaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    var prevM = Offset(cx - size.width * 0.12 + shakeX, cy + size.height * 0.18 + shakeY);
    for (var x = 0.0; x <= size.width * 0.24; x += 2) {
      final px = cx - size.width * 0.12 + x + shakeX;
      final py = cy + size.height * 0.18 +
          sin((x + animMs / 18.0) * 0.08) * 6 +
          shakeY;
      canvas.drawLine(prevM, Offset(px, py), mouthPaint);
      prevM = Offset(px, py);
    }
  }

  void _drawBoot(Canvas canvas, Size size) {
    final p = (animMs / 2200.0).clamp(0.0, 1.0);
    final tp = cachedTextPainter(
      'BLINK',
      TextStyle(
        color: eyeColor,
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 4,
      ),
    );
    final y = size.height * 0.35 + (1 - Curves.easeOut.transform(p)) * 18;
    tp.paint(canvas, Offset((size.width - tp.width) / 2, y));

    if (p < 0.18) {
      final dotPaint = Paint()..color = eyeColor;
      final q = Curves.easeInOut.transform(p / 0.18);
      final r = 1.5 + q * 3;
      for (var i = 0; i < 5; i++) {
        canvas.drawCircle(
          Offset(size.width * 0.34 + i * 16, size.height * 0.45),
          r,
          dotPaint,
        );
      }
    }
  }

  void _drawAppMode(Canvas canvas, Size size, double cx, double cy) {
    if (drawMode) {
      final label = cachedTextPainter(
        'DRAW',
        TextStyle(
          color: accentColor,
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 3,
        ),
      );
      label.paint(canvas, Offset((size.width - label.width) / 2, cy - 8));
      return;
    }

    final bob = sin(animMs / 800.0) * 1.5;
    final eyeWidth = size.width * 0.13;
    final eyeHeight = size.height * 0.18 * eyeOpenness.clamp(0.2, 1.0);
    final eyeSpacing = size.width * 0.11;
    final eyeY = cy - size.height * 0.08 + bob;
    final eyePaint = Paint()..color = eyeColor;

    for (final offset in [-eyeSpacing, eyeSpacing]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx + offset, eyeY),
            width: eyeWidth,
            height: eyeHeight,
          ),
          Radius.circular(eyeWidth * 0.3),
        ),
        eyePaint,
      );
    }

    if (focusActive) {
      final label = cachedTextPainter(
        'FOCUS',
        TextStyle(
          color: eyeColor,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      );
      label.paint(canvas, Offset((size.width - label.width) / 2, cy + size.height * 0.08));
    }
  }

  void _drawEyeGrid(
    Canvas canvas,
    double centerX,
    double eyeY,
    double eyeWidth,
    double eyeHeight,
    double eyeSpacing,
  ) {
    final gridPaint = Paint()
      ..color = BlinkColors.surface.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final pixelSize = eyeWidth / 5;
    for (final eyeCenterX in [centerX - eyeSpacing, centerX + eyeSpacing]) {
      for (double x = eyeCenterX - eyeWidth / 2;
          x < eyeCenterX + eyeWidth / 2;
          x += pixelSize) {
        canvas.drawLine(
          Offset(x, eyeY - eyeHeight / 2),
          Offset(x, eyeY + eyeHeight / 2),
          gridPaint,
        );
      }
    }
  }

  void _drawYawnMouth(Canvas canvas, double cx, double cy, Size size) {
    final grow = yawnProgress < 0.48
        ? Curves.easeInOut.transform(yawnProgress / 0.48)
        : Curves.easeInOut.transform(1 - (yawnProgress - 0.48) / 0.52);
    final mouthPaint = Paint()
      ..color = mouthColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final rx = size.width * 0.04 + grow * size.width * 0.09;
    final ry = size.height * 0.02 + grow * size.height * 0.08;
    final mouthY = cy + size.height * 0.2;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, mouthY), width: rx * 2, height: ry * 2),
      mouthPaint,
    );
  }

  void _drawClosedEyes(Canvas canvas, Size size, double cx, double cy) {
    final spacing = size.width * 0.12;
    final eyePaint = Paint()
      ..color = eyeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (final eyeCx in [cx - spacing, cx + spacing]) {
      final path = Path()
        ..moveTo(eyeCx - size.width * 0.07, cy)
        ..quadraticBezierTo(
          eyeCx,
          cy + size.height * 0.04,
          eyeCx + size.width * 0.07,
          cy,
        );
      canvas.drawPath(path, eyePaint);
    }
  }

  void _drawSleepSmile(Canvas canvas, double cx, double cy, Size size) {
    final mouthY = cy + size.height * 0.2;
    final smilePaint = Paint()
      ..color = mouthColor.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx - size.width * 0.05, mouthY)
      ..quadraticBezierTo(cx, mouthY + 4, cx + size.width * 0.05, mouthY);
    canvas.drawPath(path, smilePaint);

    final blush = Paint()
      ..color = accentColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx - size.width * 0.22, cy + 8), 3, blush);
    canvas.drawCircle(Offset(cx + size.width * 0.22, cy + 8), 3, blush);
  }

  void _drawFloatingZzz(Canvas canvas, Size size, double cx, double cy) {
    final textStyle = TextStyle(
      color: BlinkColors.textSecondary.withValues(alpha: 0.85),
      fontWeight: FontWeight.w500,
    );
    for (var i = 0; i < 3; i++) {
      final cycle = ((sleepPhase / 0.9 + i * 0.34) % 1.0);
      final drift = Curves.easeInOut.transform(cycle);
      final x = cx + size.width * 0.12 + i * 14 + drift * 16;
      final y = cy - size.height * 0.18 - drift * 28 + sin(sleepPhase + i) * 2;
      final tp = cachedTextPainter(
        i.isEven ? 'z' : 'Z',
        textStyle.copyWith(fontSize: 10.0 + i * 4.0),
      );
      tp.paint(canvas, Offset(x, y));
    }
  }

  void _drawFaceDots(Canvas canvas, double centerX, double centerY) {
    final dotPaint = Paint()
      ..color = BlinkColors.textTertiary.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX - 56, centerY), 2, dotPaint);
    canvas.drawCircle(Offset(centerX + 56, centerY), 2, dotPaint);
  }

  void _drawMoon(Canvas canvas, double x, double y) {
    final moonPaint = Paint()
      ..color = BlinkColors.textSecondary.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x, y), 8, moonPaint);
    final cutPaint = Paint()
      ..color = BlinkColors.background
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(x + 5, y - 2), 7, cutPaint);
  }

  @override
  bool shouldRepaint(covariant _RobotFacePainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.eyeOpenness != eyeOpenness ||
        oldDelegate.yawnProgress != yawnProgress ||
        oldDelegate.sleepPhase != sleepPhase ||
        oldDelegate.animMs != animMs ||
        oldDelegate.isNight != isNight ||
        oldDelegate.focusActive != focusActive ||
        oldDelegate.drawMode != drawMode;
  }
}
