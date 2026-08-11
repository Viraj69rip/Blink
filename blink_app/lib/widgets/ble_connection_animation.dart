import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

/// States shown by the BLINK pairing OLED simulation.
enum BleConnectionAnimState {
  idle,
  scanning,
  connecting,
  connected,
  failed,
}

/// The pairing animation uses the same 128 x 64 "app mode" composition as
/// the OLED simulator on the BLINK website: wordmark, status, five signal
/// bars and a soft orbiting status light.
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _completionTimer;
  bool _completionSent = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _durationFor(widget.state),
    );
    _playFor(widget.state);
  }

  Duration _durationFor(BleConnectionAnimState state) => switch (state) {
        BleConnectionAnimState.scanning => const Duration(milliseconds: 1500),
        BleConnectionAnimState.connecting => const Duration(milliseconds: 1750),
        BleConnectionAnimState.connected => const Duration(milliseconds: 2200),
        BleConnectionAnimState.failed => const Duration(milliseconds: 1300),
        BleConnectionAnimState.idle => const Duration(milliseconds: 1800),
      };

  void _playFor(BleConnectionAnimState state) {
    _completionTimer?.cancel();
    _completionSent = false;
    _controller
      ..stop()
      ..duration = _durationFor(state)
      ..value = 0;

    switch (state) {
      case BleConnectionAnimState.idle:
        break;
      case BleConnectionAnimState.failed:
        _controller.repeat(reverse: true);
      case BleConnectionAnimState.scanning:
      case BleConnectionAnimState.connecting:
      case BleConnectionAnimState.connected:
        _controller.repeat();
    }

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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ??
        false;
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
                    animation: _controller,
                    builder: (context, _) => CustomPaint(
                      painter: _BleOledPainter(
                        state: widget.state,
                        phase: disableAnimations ? 0.32 : _controller.value,
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

_ConnectionStatus _statusFor(BleConnectionAnimState state) => switch (state) {
      BleConnectionAnimState.idle =>
        const _ConnectionStatus('READY', BlinkColors.textTertiary),
      BleConnectionAnimState.scanning =>
        const _ConnectionStatus('SCANNING', BlinkColors.oledAccent),
      BleConnectionAnimState.connecting =>
        const _ConnectionStatus('CONNECTING', BlinkColors.oledAccent),
      BleConnectionAnimState.connected =>
        const _ConnectionStatus('CONNECTED', BlinkColors.oledAccent),
      BleConnectionAnimState.failed =>
        const _ConnectionStatus('NOT FOUND', BlinkColors.danger),
    };

class _BleOledPainter extends CustomPainter {
  const _BleOledPainter({
    required this.state,
    required this.phase,
  });

  final BleConnectionAnimState state;
  final double phase;

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
    final t = phase * 2 * pi;
    final isConnected = state == BleConnectionAnimState.connected;
    final isConnecting = state == BleConnectionAnimState.connecting;
    final isScanning = state == BleConnectionAnimState.scanning;
    final isFailed = state == BleConnectionAnimState.failed;

    final reveal = isConnecting
        ? Curves.easeOutCubic.transform((phase * 2.25).clamp(0.0, 1.0))
        : 1.0;
    final wordmarkAlpha = isConnecting
        ? Curves.easeOut.transform((phase * 3.3).clamp(0.0, 1.0))
        : 1.0;

    _paintCenteredText(
      canvas,
      'BLINK',
      top: 7,
      style: TextStyle(
        color: BlinkColors.textPrimary.withValues(alpha: wordmarkAlpha),
        fontFamily: 'monospace',
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
        letterSpacing: 2.35,
      ),
    );
    _paintCenteredText(
      canvas,
      status.label,
      top: 21,
      style: TextStyle(
        color: status.color.withValues(alpha: isFailed ? 0.85 : 0.72),
        fontFamily: 'monospace',
        fontWeight: FontWeight.w600,
        fontSize: 5.5,
        letterSpacing: 1.25,
      ),
    );

    _paintSignalBars(
      canvas,
      t: t,
      reveal: reveal,
      color: status.color,
      animate: !isFailed,
      intensity: isScanning ? 1.5 : (isConnected ? 0.62 : 1.0),
      failed: isFailed,
    );

    final center = Offset(64, 35);
    final orbitX = center.dx + cos(t * (isScanning ? 1.35 : 0.75)) * 10;
    final orbitY = center.dy + sin(t * (isScanning ? 1.65 : 0.9)) * 3.8;
    final dot = isFailed
        ? Offset(64, 35)
        : Offset(orbitX, orbitY);
    final breath = 0.5 + 0.5 * sin(t * (isScanning ? 2.4 : 1.5));
    _paintStatusDot(
      canvas,
      center: dot,
      color: status.color,
      intensity: isFailed ? 0.35 : (0.65 + breath * 0.35),
    );

    if (isScanning || isConnecting) {
      _paintSearchingRings(
        canvas,
        center: center,
        color: status.color,
        phase: phase,
      );
    }
    if (isConnected) {
      _paintConnectedSparkles(canvas, t: t, color: status.color);
    }
    if (isFailed) {
      _paintRetryMark(canvas, color: status.color, phase: phase);
    }
  }

  void _paintSignalBars(
    Canvas canvas, {
    required double t,
    required double reveal,
    required Color color,
    required bool animate,
    required double intensity,
    required bool failed,
  }) {
    const barWidth = 6.0;
    const gap = 7.0;
    const baseY = 51.0;
    const startX = 34.0;
    for (var index = 0; index < 5; index++) {
      final baseHeight = 4 + index * 3.8;
      final wobble = animate ? sin(t * 2.7 + index * 1.2) * intensity : 0.0;
      final height = max(2.0, (baseHeight + wobble) * reveal);
      final rect = Rect.fromLTWH(
        startX + index * (barWidth + gap),
        baseY - height,
        barWidth,
        height,
      );
      if (failed && index > 1) {
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
            ..color = color.withValues(alpha: 0.38 + index * 0.11),
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
    for (final ring in <double>[7.0, 4.8]) {
      canvas.drawCircle(
        center,
        ring,
        Paint()..color = color.withValues(alpha: 0.035 * intensity),
      );
    }
    canvas.drawCircle(
      center,
      2.45,
      Paint()..color = color.withValues(alpha: 0.28 * intensity),
    );
    canvas.drawCircle(center, 1.3, Paint()..color = color);
  }

  void _paintSearchingRings(
    Canvas canvas, {
    required Offset center,
    required Color color,
    required double phase,
  }) {
    for (var index = 0; index < 2; index++) {
      final p = (phase + index * 0.48) % 1.0;
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

  void _paintConnectedSparkles(
    Canvas canvas, {
    required double t,
    required Color color,
  }) {
    for (var index = 0; index < 5; index++) {
      final angle = t * 0.45 + index * (2 * pi / 5);
      final distance = 15 + sin(t * 1.6 + index) * 2.5;
      final center = Offset(
        64 + cos(angle) * distance,
        35 + sin(angle) * distance * 0.42,
      );
      canvas.drawCircle(
        center,
        0.75 + (index.isEven ? 0.35 : 0),
        Paint()..color = color.withValues(alpha: 0.42),
      );
    }
  }

  void _paintRetryMark(Canvas canvas,
      {required Color color, required double phase}) {
    final alpha = 0.45 + phase * 0.35;
    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(61, 32), const Offset(67, 38), paint);
    canvas.drawLine(const Offset(67, 32), const Offset(61, 38), paint);
  }

  void _paintCenteredText(
    Canvas canvas,
    String text, {
    required double top,
    required TextStyle style,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    painter.paint(canvas, Offset(64 - painter.width / 2, top));
  }

  @override
  bool shouldRepaint(covariant _BleOledPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.phase != phase;
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
