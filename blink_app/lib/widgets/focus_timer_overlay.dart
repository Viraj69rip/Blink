import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// A clean modal overlay for the Pomodoro Focus Timer.
/// Displays a large monospace countdown with start/pause/reset controls.
class FocusTimerOverlay extends StatelessWidget {
  const FocusTimerOverlay({super.key});

  /// Show the timer overlay as a modal bottom sheet.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const FocusTimerOverlay(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, (bool, int)>(
      selector: (_, state) => (state.timerRunning, state.timerSeconds),
      builder: (context, timerState, _) {
        final isRunning = timerState.$1;
        final timerSeconds = timerState.$2;
        final state = context.read<RobotStateProvider>();
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          decoration: BoxDecoration(
            color: BlinkColors.surface,
            borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
            border: Border.all(
              color: BlinkColors.cardBorder,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ────────────────────────────────────────
              Text(
                'FOCUS TIMER',
                style: BlinkTypography.labelSmall.copyWith(
                  color: BlinkColors.textTertiary,
                  letterSpacing: 3.0,
                ),
              ),
              const SizedBox(height: 32),

              // ── Timer Display ─────────────────────────────────
              Text(
                _formatTimer(timerSeconds),
                style: BlinkTypography.monoLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'POMODORO · ${BlinkConstants.pomodoroMinutes} MIN',
                style: BlinkTypography.monoSmall,
              ),

              const SizedBox(height: 40),

              // ── Progress Bar ──────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: AnimatedContainer(
                  duration: const Duration(seconds: 1),
                  curve: Curves.linear,
                  child: LinearProgressIndicator(
                    value: 1.0 -
                        (timerSeconds /
                            (BlinkConstants.pomodoroMinutes * 60)),
                    backgroundColor: BlinkColors.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      BlinkColors.accent,
                    ),
                    minHeight: 3,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // ── Controls ──────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Reset button
                  _ControlButton(
                    icon: Icons.refresh_rounded,
                    onTap: () => state.resetTimer(),
                  ),

                  const SizedBox(width: 24),

                  // Play/Pause button (primary)
                  _ControlButton(
                    icon: isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    isPrimary: true,
                    onTap: () {
                      if (isRunning) {
                        state.pauseTimer();
                      } else {
                        state.startTimer();
                      }
                    },
                  ),

                  const SizedBox(width: 24),

                  // Close button
                  _ControlButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  String _formatTimer(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }
}

/// Minimalist circular control button.
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    this.isPrimary = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BlinkConstants.animDuration,
        curve: BlinkConstants.animCurve,
        width: isPrimary ? 64 : 48,
        height: isPrimary ? 64 : 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isPrimary
              ? BlinkColors.accent.withValues(alpha: 0.15)
              : BlinkColors.surfaceVariant,
          border: Border.all(
            color: isPrimary
                ? BlinkColors.accent.withValues(alpha: 0.5)
                : BlinkColors.cardBorder,
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: isPrimary ? BlinkColors.accent : BlinkColors.textSecondary,
          size: isPrimary ? 28 : 20,
        ),
      ),
    );
  }
}
