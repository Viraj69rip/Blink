import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/blink_theme.dart';
import '../utils/text_painter_cache.dart';

/// States shown by the BLINK pairing OLED simulation.
enum BleConnectionAnimState {
  idle,
  scanning,
  connecting,
  connected,
  failed,
}

// ── Spec constants, ported from website/src/components/Demo.jsx `drawApp` ────
//
// The website draws into a 256 x 128 canvas using fractions of w/h, so every
// value below is that same fraction resolved against the real OLED's 128 x 64.
// Fractions are resolution-independent, which is why the numbers transfer
// exactly rather than approximately.

/// Seamless loop length for the App Mode scene.
///
/// `drawApp` animates on `sin(t*3)`, `cos(t*1.5)` and `sin(t*1.8)`. The shortest
/// `t` making all three complete a whole number of turns is `2π * 10/3`, so the
/// scene repeats exactly every 20.944 s. Driving the controller at any other
/// duration either runs the scene at the wrong speed (the old code looped in
/// 1.5–2.2 s) or visibly jumps at the wrap.
const double _kLoopSeconds = 20.9439510239; // 2 * pi * 10 / 3
const Duration _kLoopDuration = Duration(milliseconds: 20944);

/// Any periodic frequency used here must be a multiple of 0.3 rad/s, otherwise
/// it will not close over [_kLoopSeconds] and the loop will visibly tick.
const double _kBarFreq = 3.0; // spec
const double _kDotFreqX = 1.5; // spec
const double _kDotFreqY = 1.8; // spec
const double _kSparkleOrbitFreq = 0.6;
const double _kSparkleBreathFreq = 1.5;
const double _kPulseFreq = 1.5;

/// Horizontal centre of the display, `w * 0.5`. The website centres the
/// wordmark, status line and dot orbit on it.
const double _kCenterX = 64.0;

// Wordmark: bold (h * 0.16)px monospace, #818cf8, baseline at h * 0.22.
const double _kWordmarkSize = 10.24;
const double _kWordmarkBaseline = 14.08;

// Status line: (h * 0.08)px monospace, white @ 0.5, baseline at h * 0.34.
const double _kStatusSize = 5.12;
const double _kStatusBaseline = 21.76;

// Signal bars: 5 bars, x = w*0.25 + i*(w*0.1), width w*0.05, base at h*0.72,
// height h*0.3*((i+1)/5) wobbling by h*0.04.
const int _kBarCount = 5;
const double _kBarStartX = 32.0;
const double _kBarPitch = 12.8;
const double _kBarWidth = 6.4;
const double _kBarBaseY = 46.08;
const double _kBarStep = 3.84;
const double _kBarWobble = 2.56;

// Status dot: orbits w*0.08 / h*0.06 around the display centre. Core is
// #6366f1 at r = w*0.025 under an 8px glow; halo is white @ 0.08 at r = w*0.055.
const double _kDotCenterX = _kCenterX;
const double _kDotCenterY = 32.0;
const double _kDotOrbitX = 10.24;
const double _kDotOrbitY = 3.84;
const double _kDotCoreRadius = 3.2;
const double _kDotHaloRadius = 7.04;
const double _kDotGlowBlur = 4.0; // canvas shadowBlur 8, halved to OLED units

/// The pairing animation reproduces the "App Mode" composition from the OLED
/// simulator on the BLINK website: indigo wordmark, status line, five signal
/// bars and a softly orbiting status light.
///
/// [size] is the outer width. The widget maintains the OLED's 2:1 ratio rather
/// than stretching the animation into a square.
class BleConnectionAnimation extends StatefulWidget {
  const BleConnectionAnimation({
    super.key,
    required this.state,
    this.size = 280,
    this.onComplete,
  });

  final BleConnectionAnimState state;
  final double size;
  final VoidCallback? onComplete;

  @override
  State<BleConnectionAnimation> createState() =>
      _BleConnectionAnimationState();
}

class _BleConnectionAnimationState extends State<BleConnectionAnimation>
    with TickerProviderStateMixin {
  /// Scene clock. Runs continuously at the spec rate and is never restarted by
  /// a state change — the composition is the same scene throughout, so
  /// re-seeding it would make the bars and dot jump on every transition.
  late final AnimationController _timebase;

  /// One-shot entrance, restarted whenever the state changes. Drives the
  /// reveal and wordmark fade so those play once instead of every 20.9 s.
  late final AnimationController _entry;

  Timer? _completionTimer;
  bool _completionSent = false;

  @override
  void initState() {
    super.initState();
    _timebase = AnimationController(vsync: this, duration: _kLoopDuration)
      ..repeat();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _playFor(widget.state);
  }

  void _playFor(BleConnectionAnimState state) {
    _completionTimer?.cancel();
    _completionSent = false;
    _entry
      ..stop()
      ..value = 0
      ..forward();

    if (state == BleConnectionAnimState.connected && widget.onComplete != null) {
      // Let the successful connection read clearly before the overlay exits.
      _completionTimer = Timer(const Duration(milliseconds: 1150), () {
        if (!mounted || _completionSent) return;
        _completionSent = true;
        widget.onComplete?.call();
      });
    }
  }

  @override
  void didUpdateWidget(covariant BleConnectionAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _playFor(widget.state);
    }
  }

  @override
  void dispose() {
    _completionTimer?.cancel();
    _timebase.dispose();
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final outerWidth = widget.size.clamp(160.0, 520.0);
    final inset = (outerWidth * 0.045).clamp(8.0, 16.0);

    return Semantics(
      liveRegion: true,
      label: '${_statusFor(widget.state).label} BLINK connection status',
      child: RepaintBoundary(
        child: SizedBox(
          width: outerWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF202534), Color(0xFF0B0D13)],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(inset),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: AspectRatio(
                  aspectRatio: 2,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_timebase, _entry]),
                    builder: (context, _) => CustomPaint(
                      painter: _BleOledPainter(
                        state: widget.state,
                        // Seconds since the loop started, matching the
                        // website's `t = (ts - start) / 1000`.
                        t: disableAnimations
                            ? _kLoopSeconds * 0.32
                            : _timebase.value * _kLoopSeconds,
                        entry: disableAnimations ? 1.0 : _entry.value,
                      ),
                    ),
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

class _ConnectionStatus {
  const _ConnectionStatus(this.label, this.color);

  final String label;
  final Color color;
}

/// [color] tints the bars, dot and status text. The website scene is indigo
/// throughout; only a failed pair departs from it.
_ConnectionStatus _statusFor(BleConnectionAnimState state) => switch (state) {
      BleConnectionAnimState.idle =>
        const _ConnectionStatus('READY', BlinkColors.pairIndigo),
      BleConnectionAnimState.scanning =>
        const _ConnectionStatus('SCANNING', BlinkColors.pairIndigo),
      BleConnectionAnimState.connecting =>
        const _ConnectionStatus('CONNECTING', BlinkColors.pairIndigo),
      BleConnectionAnimState.connected =>
        const _ConnectionStatus('CONNECTED', BlinkColors.pairIndigo),
      BleConnectionAnimState.failed =>
        const _ConnectionStatus('NOT FOUND', BlinkColors.danger),
    };

/// Laying out a [TextPainter] every frame for two short, rarely-changing
/// strings is pure waste. See [cachedTextPainter] for the caching rules.
class _BleOledPainter extends CustomPainter {
  const _BleOledPainter({
    required this.state,
    required this.t,
    required this.entry,
  });

  final BleConnectionAnimState state;

  /// Scene time in seconds, 0 .. [_kLoopSeconds].
  final double t;

  /// One-shot entrance progress for the current state, 0 .. 1.
  final double entry;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);

    canvas.save();
    canvas.scale(size.width / 128, size.height / 64);
    _paintOled(canvas);
    canvas.restore();
  }

  void _paintOled(Canvas canvas) {
    final status = _statusFor(state);
    final isConnected = state == BleConnectionAnimState.connected;
    final isConnecting = state == BleConnectionAnimState.connecting;
    final isScanning = state == BleConnectionAnimState.scanning;
    final isFailed = state == BleConnectionAnimState.failed;

    // Connecting is the only state that grows the bars in from nothing; every
    // other state shows the settled scene immediately.
    final reveal = isConnecting
        ? Curves.easeOutCubic.transform(entry.clamp(0.0, 1.0))
        : 1.0;
    final wordmarkAlpha = isConnecting
        ? Curves.easeOut.transform((entry * 1.6).clamp(0.0, 1.0))
        : 1.0;

    _paintCenteredText(
      canvas,
      'BLINK',
      baseline: _kWordmarkBaseline,
      style: TextStyle(
        color: BlinkColors.pairIndigo.withValues(alpha: wordmarkAlpha),
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
        fontSize: _kWordmarkSize,
      ),
    );
    _paintCenteredText(
      canvas,
      status.label,
      baseline: _kStatusBaseline,
      style: TextStyle(
        color: isFailed
            ? BlinkColors.danger.withValues(alpha: 0.85)
            : BlinkColors.textPrimary.withValues(alpha: 0.5),
        fontFamily: 'monospace',
        fontSize: _kStatusSize,
      ),
    );

    _paintSignalBars(
      canvas,
      reveal: reveal,
      color: status.color,
      animate: !isFailed,
      failed: isFailed,
    );

    const center = Offset(_kDotCenterX, _kDotCenterY);
    final dot = isFailed
        ? center
        : Offset(
            _kDotCenterX + cos(t * _kDotFreqX) * _kDotOrbitX,
            _kDotCenterY + sin(t * _kDotFreqY) * _kDotOrbitY,
          );
    _paintStatusDot(
      canvas,
      center: dot,
      color: isFailed ? BlinkColors.danger : BlinkColors.pairIndigoDeep,
      intensity: isFailed ? 0.45 : 1.0,
    );

    if (isScanning || isConnecting) {
      _paintSearchingRings(canvas, center: center, color: status.color);
    }
    if (isConnected) {
      _paintConnectedSparkles(canvas, color: status.color);
    }
    if (isFailed) {
      _paintRetryMark(canvas, color: status.color);
    }
  }

  void _paintSignalBars(
    Canvas canvas, {
    required double reveal,
    required Color color,
    required bool animate,
    required bool failed,
  }) {
    for (var index = 0; index < _kBarCount; index++) {
      final baseHeight = _kBarStep * (index + 1);
      final wobble =
          animate ? sin(t * _kBarFreq + index * 1.2) * _kBarWobble : 0.0;
      final height = max(0.0, (baseHeight + wobble) * reveal);
      if (height <= 0) continue;
      final rect = Rect.fromLTWH(
        _kBarStartX + index * _kBarPitch,
        _kBarBaseY - height,
        _kBarWidth,
        height,
      );
      if (failed && index > 1) {
        // Out of range: the tall bars are drawn as empty outlines.
        canvas.drawRect(
          rect,
          Paint()
            ..color = BlinkColors.textPrimary.withValues(alpha: 0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.7,
        );
      } else {
        canvas.drawRect(
          rect,
          Paint()
            ..color = color.withValues(
              alpha: 0.4 + (index / _kBarCount) * 0.6,
            ),
        );
      }
    }
  }

  void _paintStatusDot(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required double intensity,
  }) {
    // Stands in for the website's `shadowBlur = 8` on the core.
    canvas.drawCircle(
      center,
      _kDotCoreRadius,
      Paint()
        ..color = color.withValues(alpha: 0.55 * intensity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, _kDotGlowBlur),
    );
    canvas.drawCircle(
      center,
      _kDotCoreRadius,
      Paint()..color = color.withValues(alpha: intensity),
    );
    // Drawn last, exactly as in the source: a wide, very faint white lift.
    canvas.drawCircle(
      center,
      _kDotHaloRadius,
      Paint()
        ..color = BlinkColors.textPrimary.withValues(alpha: 0.08 * intensity),
    );
  }

  void _paintSearchingRings(
    Canvas canvas, {
    required Offset center,
    required Color color,
  }) {
    // 13 ring cycles per scene loop divides [_kLoopSeconds] evenly, so the
    // rings do not jump when the timebase wraps.
    final ringPhase = (t / (_kLoopSeconds / 13)) % 1.0;
    for (var index = 0; index < 2; index++) {
      final p = (ringPhase + index * 0.48) % 1.0;
      canvas.drawCircle(
        center,
        6 + p * 15,
        Paint()
          ..color = color.withValues(alpha: (1 - p) * 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75,
      );
    }
  }

  void _paintConnectedSparkles(Canvas canvas, {required Color color}) {
    for (var index = 0; index < 5; index++) {
      final angle = t * _kSparkleOrbitFreq + index * (2 * pi / 5);
      final distance =
          15 + sin(t * _kSparkleBreathFreq + index) * 2.5;
      final center = Offset(
        _kDotCenterX + cos(angle) * distance,
        _kDotCenterY + sin(angle) * distance * 0.42,
      );
      canvas.drawCircle(
        center,
        0.75 + (index.isEven ? 0.35 : 0),
        Paint()..color = color.withValues(alpha: 0.42),
      );
    }
  }

  void _paintRetryMark(Canvas canvas, {required Color color}) {
    final pulse = 0.5 + 0.5 * sin(t * _kPulseFreq);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45 + pulse * 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(61, 29), const Offset(67, 35), paint);
    canvas.drawLine(const Offset(67, 29), const Offset(61, 35), paint);
  }

  void _paintCenteredText(
    Canvas canvas,
    String text, {
    required double baseline,
    required TextStyle style,
  }) {
    final painter = cachedTextPainter(text, style);
    // Canvas `fillText` puts the alphabetic baseline at y and centres on x;
    // TextPainter paints from the top-left, so lift it by the ascent.
    final ascent =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(
      canvas,
      Offset(_kCenterX - painter.width / 2, baseline - ascent),
    );
  }

  @override
  bool shouldRepaint(covariant _BleOledPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.t != t ||
      oldDelegate.entry != entry;
}

/// Full-screen pairing feedback. It hides itself after a successful pairing so
/// a connected robot never leaves an invisible input-blocking overlay behind.
class BleConnectionOverlay extends StatefulWidget {
  const BleConnectionOverlay({
    super.key,
    required this.state,
    this.onDismiss,
  });

  final BleConnectionAnimState state;
  final VoidCallback? onDismiss;

  @override
  State<BleConnectionOverlay> createState() => _BleConnectionOverlayState();
}

class _BleConnectionOverlayState extends State<BleConnectionOverlay> {
  bool _dismissed = false;

  @override
  void didUpdateWidget(covariant BleConnectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _dismissed = false;
  }

  void _dismiss() {
    if (_dismissed) return;
    setState(() => _dismissed = true);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed || widget.state == BleConnectionAnimState.idle) {
      return const SizedBox.shrink();
    }

    final status = _statusFor(widget.state);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BleConnectionAnimation(
                  state: widget.state,
                  size: 300,
                  onComplete: widget.state == BleConnectionAnimState.connected
                      ? _dismiss
                      : null,
                ),
                const SizedBox(height: 28),
                Text(
                  _overlayMessage(widget.state),
                  textAlign: TextAlign.center,
                  style: BlinkTypography.mono.copyWith(
                    color: status.color,
                    fontSize: 13,
                    letterSpacing: 2.1,
                  ),
                ),
                if (widget.state == BleConnectionAnimState.failed) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: _dismiss,
                    child: Text(
                      'CLOSE',
                      style: BlinkTypography.labelSmall.copyWith(
                        color: BlinkColors.textPrimary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _overlayMessage(BleConnectionAnimState state) => switch (state) {
        BleConnectionAnimState.scanning => 'LOOKING FOR BLINK',
        BleConnectionAnimState.connecting => 'SECURING CONNECTION',
        BleConnectionAnimState.connected => 'BLINK IS READY',
        BleConnectionAnimState.failed => 'BLINK WAS NOT FOUND',
        BleConnectionAnimState.idle => '',
      };
}
