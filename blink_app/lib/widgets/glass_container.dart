import 'package:flutter/material.dart';

import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';

/// A static liquid-glass surface for large cards.
///
/// Large [BackdropFilter] layers force the GPU to re-sample everything behind
/// each card while scrolling. Most BLINK pages sit on an opaque black canvas,
/// so the visual result is almost identical with this painted glass surface
/// and substantially cheaper to render. The real blurred glass is reserved
/// for the small floating navigation bar where it is most noticeable.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final bool animateShimmer;
  final double opacity;
  final double borderOpacity;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 30.0,
    this.borderRadius = 24.0,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.animateShimmer = false,
    this.opacity = 0.08,
    this.borderOpacity = 0.12,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: width,
        height: height,
        margin: margin,
        child: CustomPaint(
          painter: _LiquidGlassPainter(
            borderRadius: borderRadius,
            surfaceOpacity: opacity,
            borderOpacity: borderOpacity,
          ),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A liquid-glass container with a low-cost animated active state.
class GlassToggleContainer extends StatelessWidget {
  final Widget child;
  final bool isActive;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  const GlassToggleContainer({
    super.key,
    required this.child,
    this.isActive = false,
    this.onTap,
    this.padding,
    this.borderRadius = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BlinkConstants.animDuration,
        curve: BlinkConstants.animCurve,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isActive
                  ? BlinkColors.accent.withValues(alpha: 0.16)
                  : const Color(0xFF2A2A2E).withValues(alpha: 0.58),
              isActive
                  ? BlinkColors.accent.withValues(alpha: 0.06)
                  : const Color(0xFF17171A).withValues(alpha: 0.70),
            ],
          ),
          borderRadius: radius,
          border: Border.all(
            color: isActive
                ? BlinkColors.accent.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.12),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Padding(
          padding: padding ?? const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );
  }
}

class _LiquidGlassPainter extends CustomPainter {
  final double borderRadius;
  final double surfaceOpacity;
  final double borderOpacity;

  const _LiquidGlassPainter({
    required this.borderRadius,
    required this.surfaceOpacity,
    required this.borderOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF303035).withValues(alpha: surfaceOpacity + 0.22),
          const Color(0xFF19191C).withValues(alpha: surfaceOpacity + 0.15),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: surfaceOpacity + 0.06),
          Colors.transparent,
        ],
        stops: const [0, 0.42],
      ).createShader(rect);
    canvas.drawRRect(rrect, highlightPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: borderOpacity + 0.08),
          Colors.white.withValues(alpha: borderOpacity * 0.35),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.4), borderPaint);
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassPainter oldDelegate) {
    return oldDelegate.borderRadius != borderRadius ||
        oldDelegate.surfaceOpacity != surfaceOpacity ||
        oldDelegate.borderOpacity != borderOpacity;
  }
}
