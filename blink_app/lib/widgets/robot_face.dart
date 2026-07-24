import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/robot_animation_snapshot.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

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
  Timer? _sleepAnimTimer;
  Timer? _syncRepaintTimer;

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
    _syncRepaintTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted) return;
      final synced = context.read<RobotStateProvider>().isRobotSynced;
      if (synced) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final synced = context.read<RobotStateProvider>().isRobotSynced;
    if (_wasSynced && !synced) {
      _localNightYawn = false;
      _yawnController.reset();
      _sleepAnimTimer?.cancel();
      _sleepWakeTimer?.cancel();
      _scheduleNextBlink();
    }
    _wasSynced = synced;
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
    _sleepAnimTimer?.cancel();
    _sleepAnimTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || _localFaceState != RobotFaceState.sleep) return;
      setState(() => _sleepPhase += 0.05);
    });
    _sleepWakeTimer?.cancel();
    _sleepWakeTimer = Timer(BlinkConstants.sleepDuration, _wakeFromLocalSleep);
    setState(() {});
  }

  void _wakeFromLocalSleep() {
    if (!mounted) return;
    _localNightYawn = false;
    _sleepAnimTimer?.cancel();
    setState(() {});
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
    _sleepAnimTimer?.cancel();
    _syncRepaintTimer?.cancel();
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
      case RobotFaceState.yawn:
      case RobotFaceState.idle:
        _drawStandardFace(canvas, size, centerX, centerY);
    }
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
    final textStyle = TextStyle(
      color: eyeColor,
      fontSize: 28,
      fontWeight: FontWeight.w700,
      letterSpacing: 4,
    );
    final tp = TextPainter(
      text: TextSpan(text: 'BLINK', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
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
      final label = TextPainter(
        text: TextSpan(
          text: 'DRAW',
          style: TextStyle(
            color: accentColor,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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
      final label = TextPainter(
        text: TextSpan(
          text: 'FOCUS',
          style: TextStyle(
            color: eyeColor,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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
      final tp = TextPainter(
        text: TextSpan(
          text: i.isEven ? 'z' : 'Z',
          style: textStyle.copyWith(fontSize: 10.0 + i * 4.0),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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
