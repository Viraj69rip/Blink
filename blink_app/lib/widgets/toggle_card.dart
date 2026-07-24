import 'package:flutter/material.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// A reusable bento-style toggle card with smooth animated state transitions.
/// Used for Capacitive Touch, mmWave Radar, and similar feature toggles.
class ToggleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const ToggleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
                ? BlinkColors.accent.withValues(alpha: 0.35)
                : BlinkColors.cardBorder,
            width: isActive ? 1.2 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Icon + Status Indicator ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                AnimatedContainer(
                  duration: BlinkConstants.animDuration,
                  curve: BlinkConstants.animCurve,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? BlinkColors.accent.withValues(alpha: 0.1)
                        : BlinkColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? BlinkColors.accent
                        : BlinkColors.textTertiary,
                    size: 22,
                  ),
                ),
                // Active state dot
                AnimatedContainer(
                  duration: BlinkConstants.animDuration,
                  curve: BlinkConstants.animCurve,
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive
                        ? BlinkColors.accent
                        : BlinkColors.textTertiary.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),

            const Spacer(),

            // ── Title + Subtitle ────────────────────────────────
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
