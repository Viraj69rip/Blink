import 'package:flutter/material.dart';

import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// A glass-morphism card container with subtle border and background.
/// Used throughout the app for consistent card styling.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius,
    this.borderColor,
    this.backgroundColor,
    this.elevation = 0,
    this.onTap,
    this.enableFeedback = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double elevation;
  final VoidCallback? onTap;
  final bool enableFeedback;

  @override
  Widget build(BuildContext context) {
    final effectiveBorderRadius = borderRadius ?? BlinkConstants.borderRadius;
    final effectiveBorderColor = borderColor ?? BlinkColors.cardBorder;
    final effectiveBackgroundColor = backgroundColor ?? BlinkColors.surface;

    Widget card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveBackgroundColor,
        borderRadius: BorderRadius.circular(effectiveBorderRadius),
        border: Border.all(
          color: effectiveBorderColor,
          width: 1,
        ),
        boxShadow: elevation > 0
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: elevation * 4,
                  offset: Offset(0, elevation * 2),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(effectiveBorderRadius),
          enableFeedback: enableFeedback,
          child: card,
        ),
      );
    }

    return card;
  }
}

/// Animated glass card that responds to state changes with smooth transitions.
class AnimatedGlassCard extends StatefulWidget {
  const AnimatedGlassCard({
    super.key,
    required this.child,
    this.isActive = false,
    this.activeBorderColor,
    this.inactiveBorderColor,
    this.activeBackgroundColor,
    this.inactiveBackgroundColor,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius,
    this.duration,
    this.curve,
    this.onTap,
  });

  final Widget child;
  final bool isActive;
  final Color? activeBorderColor;
  final Color? inactiveBorderColor;
  final Color? activeBackgroundColor;
  final Color? inactiveBackgroundColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Duration? duration;
  final Curve? curve;
  final VoidCallback? onTap;

  @override
  State<AnimatedGlassCard> createState() => _AnimatedGlassCardState();
}

class _AnimatedGlassCardState extends State<AnimatedGlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _borderColor;
  late Animation<Color?> _backgroundColor;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration ?? BlinkConstants.animDuration,
      vsync: this,
    );

    _borderColor = ColorTween(
      begin: widget.inactiveBorderColor ?? BlinkColors.cardBorder,
      end: widget.activeBorderColor ?? BlinkColors.accent.withValues(alpha: 0.4),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve ?? BlinkConstants.animCurve,
    ));

    _backgroundColor = ColorTween(
      begin: widget.inactiveBackgroundColor ?? BlinkColors.surface.withValues(alpha: 0.5),
      end: widget.activeBackgroundColor ?? BlinkColors.surface,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve ?? BlinkConstants.animCurve,
    ));

    _scale = Tween<double>(begin: 1.0, end: 1.02).animate(CurvedAnimation(
      parent: _controller,
      curve: widget.curve ?? BlinkConstants.animCurve,
    ));

    if (widget.isActive) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedGlassCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
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
      animation: Listenable.merge([_borderColor, _backgroundColor, _scale]),
      builder: (context, _) {
        return Transform.scale(
          scale: widget.onTap != null ? _scale.value : 1.0,
          child: GlassCard(
            padding: widget.padding,
            margin: widget.margin,
            borderRadius: widget.borderRadius,
            borderColor: _borderColor.value,
            backgroundColor: _backgroundColor.value,
            onTap: widget.onTap,
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// A toggle card with animated switch and icon.
class ToggleCard extends StatelessWidget {
  const ToggleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.activeColor,
    this.inactiveColor,
    this.iconSize = 24,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final Color? activeColor;
  final Color? inactiveColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? BlinkColors.accent;
    final effectiveInactiveColor = inactiveColor ?? BlinkColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: BlinkConstants.animDuration,
        curve: BlinkConstants.animCurve,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isActive
              ? BlinkColors.surface
              : BlinkColors.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
          border: Border.all(
            color: isActive
                ? effectiveActiveColor.withValues(alpha: 0.35)
                : BlinkColors.cardBorder,
            width: isActive ? 1.2 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedContainer(
                  duration: BlinkConstants.animDuration,
                  curve: BlinkConstants.animCurve,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? effectiveActiveColor.withValues(alpha: 0.1)
                        : BlinkColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isActive ? effectiveActiveColor : effectiveInactiveColor,
                    size: iconSize,
                  ),
                ),
                if (isActive)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: BlinkColors.accent,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BlinkTypography.titleMedium.copyWith(
                    color: isActive
                        ? BlinkColors.textPrimary
                        : BlinkColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BlinkTypography.monoSmall.copyWith(
                    color: isActive
                        ? BlinkColors.textSecondary
                        : BlinkColors.textTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A section label with consistent styling.
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.label,
    this.style,
  });

  final String label;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: style ??
          BlinkTypography.labelSmall.copyWith(
            letterSpacing: 3.0,
          ),
    );
  }
}

/// A divider line with consistent styling.
class BlinkDivider extends StatelessWidget {
  const BlinkDivider({
    super.key,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.height = 0.5,
    this.color,
  });

  final EdgeInsetsGeometry margin;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      color: color ?? Colors.white.withValues(alpha: 0.06),
    );
  }
}

/// A settings tile with icon, title, subtitle, and trailing widget.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.backgroundColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: backgroundColor ?? Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor ?? BlinkColors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: BlinkTypography.titleMedium.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: BlinkTypography.monoSmall.copyWith(
                      color: BlinkColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// A settings toggle tile with a switch.
class SettingsToggleTile extends StatelessWidget {
  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? BlinkColors.accent;
    final effectiveInactiveColor = inactiveColor ?? BlinkColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? effectiveActiveColor.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: value ? effectiveActiveColor : effectiveInactiveColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BlinkTypography.titleMedium.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: BlinkTypography.monoSmall.copyWith(
                    color: BlinkColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Switch(
              value: value,
              onChanged: onChanged,
              thumbColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? effectiveActiveColor
                    : effectiveInactiveColor,
              ),
              activeTrackColor: effectiveActiveColor.withValues(alpha: 0.3),
              inactiveThumbColor: effectiveInactiveColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// An action button with consistent styling.
class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = true,
    this.fullWidth = true,
    this.disabled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;
  final bool fullWidth;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final bgColor = accent
        ? BlinkColors.accent.withValues(alpha: 0.15)
        : BlinkColors.surface;
    final borderColor = accent
        ? BlinkColors.accent.withValues(alpha: 0.5)
        : BlinkColors.cardBorder;
    final textColor = accent ? BlinkColors.accent : BlinkColors.textSecondary;
    final iconColor = accent ? BlinkColors.accent : BlinkColors.textSecondary;

    Widget button = Material(
      color: disabled ? bgColor.withValues(alpha: 0.5) : bgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: disabled ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: 14,
            // A content-sized button needs its own horizontal breathing room;
            // a full-width one gets it from the stretch.
            horizontal: fullWidth ? 0 : 20,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: disabled ? borderColor.withValues(alpha: 0.5) : borderColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            // Without this, a Row defaults to MainAxisSize.max and fills the
            // parent regardless — which is why fullWidth: false previously had
            // no visible effect in either branch.
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: disabled ? iconColor.withValues(alpha: 0.5) : iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: BlinkTypography.labelSmall.copyWith(
                  color: disabled
                      ? textColor.withValues(alpha: 0.5)
                      : textColor,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!fullWidth) {
      return button;
    }

    return SizedBox(
      width: double.infinity,
      child: button,
    );
  }
}

/// A shimmer loading placeholder.
class ShimmerPlaceholder extends StatefulWidget {
  const ShimmerPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius,
    this.baseColor,
    this.highlightColor,
  });

  final double width;
  final double height;
  final double? borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  @override
  State<ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.baseColor ?? BlinkColors.surfaceVariant;
    final highlightColor = widget.highlightColor ??
        Colors.white.withValues(alpha: 0.1);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius ?? 8),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _animation.value * 2, 0),
              end: Alignment(1.0 + _animation.value * 2, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Page transition with custom animation.
class BlinkPageRoute<T> extends PageRouteBuilder<T> {
  BlinkPageRoute({
    required Widget child,
    super.settings,
    Duration duration = const Duration(milliseconds: 300),
    Curve curve = Curves.easeOutCubic,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: curve,
                )),
                child: child,
              ),
            );
          },
        );
}

/// Hero-style transition for shared elements.
class BlinkHeroTransition extends StatelessWidget {
  const BlinkHeroTransition({
    super.key,
    required this.tag,
    required this.child,
    this.flightShuttleBuilder,
  });

  final String tag;
  final Widget child;
  final Widget Function(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection flightDirection,
    BuildContext fromHeroContext,
    BuildContext toHeroContext,
  )? flightShuttleBuilder;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: tag,
      flightShuttleBuilder: flightShuttleBuilder,
      child: child,
    );
  }
}
