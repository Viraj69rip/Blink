import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// BLE Connection Animation Widget
/// Matches the website OLED simulator 'app' mode animation
/// Shows animated bars, floating dot, and sparkle particles on connect
class BleConnectionAnimation extends StatefulWidget {
  const BleConnectionAnimation({
    super.key,
    required this.state,
    this.size = 200,
    this.onComplete,
  });

  final BleConnectionAnimState state;
  final double size;
  final VoidCallback? onComplete;

  @override
  State<BleConnectionAnimation> createState() => _BleConnectionAnimationState();
}

enum BleConnectionAnimState {
  idle,
  scanning,
  connecting,
  connected,
  failed,
}

class _BleConnectionAnimationState extends State<BleConnectionAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _progress;
  late Animation<double> _pulse;
  late Animation<double> _dotOrbit;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    
    _progress = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    
    _dotOrbit = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.linear),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.state == BleConnectionAnimState.connected) {
        widget.onComplete?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant BleConnectionAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_progress, _pulse, _dotOrbit]),
      builder: (context, _) {
        final progress = _progress.value;
        final pulse = _pulse.value;
        final dotOrbit = _dotOrbit.value;
        
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _BleConnectionPainter(
            state: widget.state,
            progress: progress,
            pulse: pulse,
            dotOrbit: dotOrbit,
            size: widget.size,
          ),
        );
      },
    );
  }
}

class _BleConnectionPainter extends CustomPainter {
  final BleConnectionAnimState state;
  final double progress;
  final double pulse;
  final double dotOrbit;
  final double size;

  _BleConnectionPainter({
    required this.state,
    required this.progress,
    required this.pulse,
    required this.dotOrbit,
    required this.size,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final centerX = size / 2;
    final centerY = size / 2;
    final scale = size / 200.0; // Base design size is 200

    // Background (OLED black)
    final bgPaint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size, size), bgPaint);

    // Draw "BLINK" text
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 28 * scale,
      fontWeight: FontWeight.w700,
      letterSpacing: 4,
      fontFamily: 'monospace',
    );
    
    final textSpan = TextSpan(text: 'BLINK', style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    
    final textX = centerX - textPainter.width / 2;
    final textY = 20 * scale;
    
    // Fade in text during connecting
    double textOpacity = 1.0;
    if (state == BleConnectionAnimState.connecting) {
      textOpacity = progress < 0.3 ? progress / 0.3 : 1.0;
    }
    textPainter.paint(
      canvas, 
      Offset(textX, textY),
      opacity: textOpacity.clamp(0.0, 1.0),
    );

    // Status text
    String statusText;
    Color statusColor = Colors.white;
    
    switch (state) {
      case BleConnectionAnimState.scanning:
        statusText = 'SCANNING...';
        statusColor = Colors.amber;
        break;
      case BleConnectionAnimState.connecting:
        statusText = 'CONNECTING...';
        statusColor = Colors.cyanAccent;
        break;
      case BleConnectionAnimState.connected:
        statusText = 'CONNECTED!';
        statusColor = BlinkColors.accent;
        break;
      case BleConnectionAnimState.failed:
        statusText = 'FAILED';
        statusColor = Colors.redAccent;
        break;
      default:
        statusText = '';
    }

    if (statusText.isNotEmpty) {
      final statusStyle = TextStyle(
        color: statusColor,
        fontSize: 10 * scale,
        fontWeight: FontWeight.w500,
        fontFamily: 'monospace',
        letterSpacing: 1.5,
      );
      final statusSpan = TextSpan(text: statusText, style: statusStyle);
      final statusPainter = TextPainter(
        text: statusSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      statusPainter.paint(
        canvas,
        Offset(centerX - statusPainter.width / 2, 40 * scale),
      );
    }

    // Animated bars (5 bars like website demo)
    const int barCount = 5;
    for (int i = 0; i < barCount; i++) {
      final baseHeight = 19.2 * scale * ((i + 1) / barCount);
      final phaseOffset = i * 1.2;
      
      double barHeight;
      if (state == BleConnectionAnimState.connecting) {
        barHeight = baseHeight * progress + 
            sin(dotOrbit * 2 * pi * 4 + phaseOffset) * 1.5 * scale;
      } else if (state == BleConnectionAnimState.connected) {
        barHeight = baseHeight + 
            sin(dotOrbit * 2 * pi * 2 + phaseOffset) * 1.0 * scale;
      } else if (state == BleConnectionAnimState.scanning) {
        barHeight = baseHeight + 
            sin(dotOrbit * 2 * pi * 3 + phaseOffset) * 2.5 * scale;
      } else {
        // Failed - outline only for bars beyond 2
        barHeight = baseHeight;
      }
      
      final h = barHeight.clamp(1.0 * scale, double.infinity);
      final bx = (32 + i * 13) * scale;
      final barX = centerX - (barCount * 13 / 2) * scale + i * 13 * scale;
      final barY = (46 - h) * scale;
      final barW = 6 * scale;

      final barPaint = Paint()
        ..color = (state == BleConnectionAnimState.failed && i > 2) 
            ? Colors.white.withValues(alpha: 0.3) 
            : (state == BleConnectionAnimState.connected 
                ? BlinkColors.accent.withValues(alpha: 0.8 + 0.2 * sin(dotOrbit * 2 * pi))
                : Colors.white.withValues(alpha: 0.4 + (i / barCount) * 0.6));
      
      if (state == BleConnectionAnimState.failed && i > 2) {
        // Draw frame only
        final framePaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawRect(
          Rect.fromLTWH(barX, barY, barW, h),
          framePaint,
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(barX, barY, barW, h),
          barPaint,
        );
      }
    }

    // Floating dot (like website)
    final dotRadius = 2.5 * scale;
    final orbitRadius = 10 * scale;
    final dotX = centerX + cos(dotOrbit * 2 * pi * 1.5) * orbitRadius;
    final dotY = centerY - 8 * scale + sin(dotOrbit * 2 * pi * 1.8) * 4 * scale;

    // Dot glow
    final glowPaint = Paint()
      ..color = state == BleConnectionAnimState.connected 
          ? BlinkColors.accent 
          : (state == BleConnectionAnimState.connecting 
              ? Colors.cyanAccent 
              : Colors.amber)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * scale);
    canvas.drawCircle(Offset(dotX, dotY), dotRadius * 2, glowPaint);

    // Dot core
    final dotPaint = Paint()
      ..color = state == BleConnectionAnimState.connected 
          ? BlinkColors.accent 
          : (state == BleConnectionAnimState.connecting 
              ? Colors.cyanAccent 
              : Colors.amber);
    canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);

    // Outer ring
    final ringPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(Offset(dotX, dotY), dotRadius * 2, ringPaint);

    // Sparkle particles on connect
    if (state == BleConnectionAnimState.connected && progress > 0.3) {
      final sparkleProgress = (progress - 0.3) / 0.7;
      for (int i = 0; i < 6; i++) {
        final sp = (dotOrbit * 2 + i * 1.05) % 1.0;
        final radius = (15.0 + 20.0 * sparkleProgress) * scale;
        final sx = centerX + cos(sp * 2 * pi) * radius;
        final sy = centerY - 8 * scale + sin(sp * 2 * pi + i) * (8.0 + 12.0 * sparkleProgress) * scale;
        
        if (sx > 2 * scale && sx < size - 2 * scale && sy > 2 * scale && sy < size - 2 * scale) {
          final sparklePaint = Paint()
            ..color = BlinkColors.accent.withValues(alpha: 0.8 * (1.0 - sparkleProgress));
          canvas.drawCircle(Offset(sx, sy), 1.5 * scale, sparklePaint);
        }
      }
    }

    // Pulsing ring on connect
    if (state == BleConnectionAnimState.connected) {
      final ringRadius = (20 + 30 * pulse) * scale;
      final ringAlpha = (1.0 - pulse) * 0.4;
      final pulsePaint = Paint()
        ..color = BlinkColors.accent.withValues(alpha: ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale;
      canvas.drawCircle(Offset(centerX, centerY - 8 * scale), ringRadius, pulsePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BleConnectionPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.dotOrbit != dotOrbit;
  }
}

/// Overlay widget for BLE connection state with animation
class BleConnectionOverlay extends StatelessWidget {
  const BleConnectionOverlay({
    super.key,
    required this.state,
    this.onDismiss,
  });

  final BleConnectionAnimState state;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (state == BleConnectionAnimState.idle) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.9),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BleConnectionAnimation(
              state: state,
              size: 280,
              onComplete: state == BleConnectionAnimState.connected ? onDismiss : null,
            ),
            const SizedBox(height: 32),
            Text(
              _getStatusText(state),
              style: BlinkTypography.mono.copyWith(
                fontSize: 16,
                letterSpacing: 3,
                color: _getStatusColor(state),
              ),
            ),
            if (state == BleConnectionAnimState.failed) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: onDismiss,
                child: Text(
                  'TRY AGAIN',
                  style: BlinkTypography.labelSmall.copyWith(
                    color: BlinkColors.accent,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getStatusText(BleConnectionAnimState state) {
    switch (state) {
      case BleConnectionAnimState.scanning:
        return 'SCANNING FOR BLINK...';
      case BleConnectionAnimState.connecting:
        return 'CONNECTING...';
      case BleConnectionAnimState.connected:
        return 'CONNECTED!';
      case BleConnectionAnimState.failed:
        return 'CONNECTION FAILED';
      default:
        return '';
    }
  }

  Color _getStatusColor(BleConnectionAnimState state) {
    switch (state) {
      case BleConnectionAnimState.scanning:
        return Colors.amber;
      case BleConnectionAnimState.connecting:
        return Colors.cyanAccent;
      case BleConnectionAnimState.connected:
        return BlinkColors.accent;
      case BleConnectionAnimState.failed:
        return Colors.redAccent;
      default:
        return Colors.white;
    }
  }
}