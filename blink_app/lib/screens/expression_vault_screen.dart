import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// Expression Vault — a catalog of animation packages for the BLINK robot.
/// Asymmetric grid layout with expandable cards showing individual frames.
class ExpressionVaultScreen extends StatelessWidget {
  const ExpressionVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, (int, String)>(
      selector: (_, state) => (
        state.selectedExpressionPack,
        state.currentExpression,
      ),
      builder: (context, selection, _) {
        final selectedPack = selection.$1;
        final currentExpression = selection.$2;
        final state = context.read<RobotStateProvider>();
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: BlinkConstants.paddingH,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: MediaQuery.of(context).padding.top + 16),

              // ── Header ─────────────────────────────────────────────
              Text(
                'Expression\nVault',
                style: BlinkTypography.displayLarge.copyWith(
                  height: 1.1,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'ANIMATION PACKAGES',
                style: BlinkTypography.labelSmall.copyWith(
                  letterSpacing: 3.0,
                ),
              ),

              const SizedBox(height: 24),

              // ── Expression Packs ───────────────────────────────────
              ..._expressionPacks.asMap().entries.map((entry) {
                final index = entry.key;
                final pack = entry.value;
                final isExpanded = selectedPack == index;

                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: BlinkConstants.gridGap,
                  ),
                  child: _ExpressionPackCard(
                    pack: pack,
                    isExpanded: isExpanded,
                    isActive: currentExpression == pack.name,
                    onTap: () => state.toggleExpressionPack(index),
                    onSelectExpression: (name) {
                      state.setExpression(name);
                    },
                  ),
                );
              }),

              const SizedBox(height: 120),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ── DATA MODEL ─────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _ExpressionPack {
  final String name;
  final String description;
  final IconData icon;
  final int frameCount;
  final List<_ExpressionFrame> frames;

  const _ExpressionPack({
    required this.name,
    required this.description,
    required this.icon,
    required this.frameCount,
    required this.frames,
  });
}

class _ExpressionFrame {
  final String name;
  final IconData icon;

  const _ExpressionFrame({required this.name, required this.icon});
}

/// Available animation packages for the BLINK robot.
const List<_ExpressionPack> _expressionPacks = [
  _ExpressionPack(
    name: 'Idle Core',
    description: 'Default resting expressions and ambient animations',
    icon: Icons.auto_awesome_rounded,
    frameCount: 6,
    frames: [
      _ExpressionFrame(name: 'Neutral', icon: Icons.sentiment_neutral_rounded),
      _ExpressionFrame(name: 'Blink', icon: Icons.visibility_rounded),
      _ExpressionFrame(name: 'Curious', icon: Icons.psychology_rounded),
      _ExpressionFrame(name: 'Happy', icon: Icons.sentiment_satisfied_rounded),
      _ExpressionFrame(name: 'Sleepy', icon: Icons.bedtime_rounded),
      _ExpressionFrame(name: 'Wink', icon: Icons.face_rounded),
    ],
  ),
  _ExpressionPack(
    name: 'Focus Mode',
    description: 'Productivity companion faces for deep work sessions',
    icon: Icons.center_focus_strong_rounded,
    frameCount: 4,
    frames: [
      _ExpressionFrame(
          name: 'Determined', icon: Icons.local_fire_department_rounded),
      _ExpressionFrame(name: 'Zen', icon: Icons.self_improvement_rounded),
      _ExpressionFrame(name: 'Timer', icon: Icons.timer_rounded),
      _ExpressionFrame(name: 'Complete', icon: Icons.check_circle_rounded),
    ],
  ),
  _ExpressionPack(
    name: 'Overload',
    description: 'Glitch effects and high-energy reactive animations',
    icon: Icons.flash_on_rounded,
    frameCount: 5,
    frames: [
      _ExpressionFrame(name: 'Glitch', icon: Icons.blur_on_rounded),
      _ExpressionFrame(name: 'Shock', icon: Icons.bolt_rounded),
      _ExpressionFrame(name: 'Error', icon: Icons.error_rounded),
      _ExpressionFrame(name: 'Reboot', icon: Icons.restart_alt_rounded),
      _ExpressionFrame(name: 'Rage', icon: Icons.whatshot_rounded),
    ],
  ),
  _ExpressionPack(
    name: 'Sleep Cycle',
    description: 'Calm, ambient faces for nighttime and rest modes',
    icon: Icons.dark_mode_rounded,
    frameCount: 4,
    frames: [
      _ExpressionFrame(name: 'Drowsy', icon: Icons.nights_stay_rounded),
      _ExpressionFrame(name: 'Asleep', icon: Icons.bedtime_rounded),
      _ExpressionFrame(name: 'Dream', icon: Icons.cloud_rounded),
      _ExpressionFrame(name: 'Wake', icon: Icons.wb_sunny_rounded),
    ],
  ),
];

// ═══════════════════════════════════════════════════════════════════════════
// ── EXPRESSION PACK CARD ───────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _ExpressionPackCard extends StatelessWidget {
  final _ExpressionPack pack;
  final bool isExpanded;
  final bool isActive;
  final VoidCallback onTap;
  final ValueChanged<String> onSelectExpression;

  const _ExpressionPackCard({
    required this.pack,
    required this.isExpanded,
    required this.isActive,
    required this.onTap,
    required this.onSelectExpression,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: BlinkConstants.animDurationExpand,
        curve: BlinkConstants.animCurve,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: BlinkColors.surface,
          borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
          border: Border.all(
            color: isActive
                ? BlinkColors.accent.withValues(alpha: 0.35)
                : isExpanded
                    ? BlinkColors.textTertiary.withValues(alpha: 0.2)
                    : BlinkColors.cardBorder,
            width: isActive ? 1.2 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Pack Header ──────────────────────────────────────────
            Row(
              children: [
                // Pack icon
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
                    pack.icon,
                    color: isActive
                        ? BlinkColors.accent
                        : BlinkColors.textSecondary,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 14),

                // Pack name + description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(pack.name, style: BlinkTypography.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        pack.description,
                        style: BlinkTypography.bodyMedium.copyWith(
                          fontSize: 12,
                          color: BlinkColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Frame count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BlinkColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${pack.frameCount}',
                    style: BlinkTypography.mono.copyWith(
                      fontSize: 12,
                      color: BlinkColors.textTertiary,
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Expand/collapse chevron
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: BlinkConstants.animDuration,
                  curve: BlinkConstants.animCurve,
                  child: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: BlinkColors.textTertiary,
                    size: 20,
                  ),
                ),
              ],
            ),

            // ── Expanded Content: Individual Frames ──────────────────
            AnimatedCrossFade(
              duration: BlinkConstants.animDurationExpand,
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              firstCurve: BlinkConstants.animCurve,
              secondCurve: BlinkConstants.animCurve,
              sizeCurve: BlinkConstants.animCurve,
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Column(
                  children: [
                    // Divider
                    Container(
                      height: 0.5,
                      color: BlinkColors.cardBorder,
                    ),
                    const SizedBox(height: 12),

                    // Frame grid
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: pack.frames.map((frame) {
                        return _FrameChip(
                          frame: frame,
                          isActive: isActive,
                          onTap: () => onSelectExpression(frame.name),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ── FRAME CHIP ─────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _FrameChip extends StatefulWidget {
  final _ExpressionFrame frame;
  final bool isActive;
  final VoidCallback onTap;

  const _FrameChip({
    required this.frame,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FrameChip> createState() => _FrameChipState();
}

class _FrameChipState extends State<_FrameChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BlinkConstants.animDuration,
          curve: BlinkConstants.animCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                _isHovered ? BlinkColors.surfaceVariant : BlinkColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? BlinkColors.textTertiary.withValues(alpha: 0.3)
                  : BlinkColors.cardBorder,
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.frame.icon,
                size: 16,
                color: widget.isActive
                    ? BlinkColors.accent
                    : BlinkColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.frame.name,
                style: BlinkTypography.monoSmall.copyWith(
                  fontSize: 11,
                  color: _isHovered
                      ? BlinkColors.textPrimary
                      : BlinkColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
