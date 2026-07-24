import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/robot_state_provider.dart';
import '../theme/blink_constants.dart';
import '../theme/blink_theme.dart';
import '../widgets/drawing_canvas.dart';

/// Drawing page — sketches are mapped to the robot's 128×64 OLED over BLE.
class DrawingScreen extends StatefulWidget {
  const DrawingScreen({super.key});

  @override
  State<DrawingScreen> createState() => _DrawingScreenState();
}

class _DrawingScreenState extends State<DrawingScreen> {
  final GlobalKey<DrawingCanvasState> _canvasKey =
      GlobalKey<DrawingCanvasState>();

  @override
  Widget build(BuildContext context) {
    final connected = context.select<RobotStateProvider, bool>(
      (s) => s.connectionState == BleConnectionState.connected,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        BlinkConstants.paddingH,
        MediaQuery.of(context).padding.top + 16,
        BlinkConstants.paddingH,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Draw', style: BlinkTypography.displayLarge),
          const SizedBox(height: 4),
          Text(
            'PIXEL GRID · 128 × 64 OLED',
            style: BlinkTypography.labelSmall.copyWith(letterSpacing: 3),
          ),
          const SizedBox(height: 8),
          Text(
            connected
                ? 'Each white cell matches a real OLED pixel on BLINK.'
                : 'Connect to BLINK to draw on the matching OLED pixel grid.',
            style: BlinkTypography.bodyMedium.copyWith(
              color: BlinkColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // ── Expression Panel ──
          _ExpressionPanel(enabled: connected),

          const SizedBox(height: 10),

          // ── Canvas ──
          Expanded(
            child: DrawingCanvas(
              key: _canvasKey,
              enabled: connected,
            ),
          ),

          const SizedBox(height: 14),

          // ── Action buttons ──
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'CLEAR',
                  icon: Icons.delete_outline_rounded,
                  onTap: () async {
                    await _canvasKey.currentState?.clearAll();
                    if (context.mounted) {
                      await context.read<RobotStateProvider>().clearDrawing();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: 'EXIT DRAW',
                  icon: Icons.close_rounded,
                  accent: false,
                  onTap: () =>
                      context.read<RobotStateProvider>().exitDrawMode(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Expression buttons that send face commands to the robot.
class _ExpressionPanel extends StatelessWidget {
  const _ExpressionPanel({required this.enabled});

  final bool enabled;

  static const List<_ExpressionItem> _expressions = [
    _ExpressionItem('Happy', Icons.sentiment_very_satisfied_rounded, 'HAPPY'),
    _ExpressionItem('Sad', Icons.sentiment_dissatisfied_rounded, 'SAD'),
    _ExpressionItem('Angry', Icons.mood_bad_rounded, 'ANGRY'),
    _ExpressionItem('Love', Icons.favorite_rounded, 'LOVE'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _expressions.map((expr) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: _ExpressionButton(
              item: expr,
              enabled: enabled,
              onTap: () {
                context.read<RobotStateProvider>().sendExpression(expr.command);
              },
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ExpressionItem {
  const _ExpressionItem(this.label, this.icon, this.command);
  final String label;
  final IconData icon;
  final String command;
}

class _ExpressionButton extends StatefulWidget {
  const _ExpressionButton({
    required this.item,
    required this.enabled,
    required this.onTap,
  });

  final _ExpressionItem item;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ExpressionButton> createState() => _ExpressionButtonState();
}

class _ExpressionButtonState extends State<_ExpressionButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (widget.enabled) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: BlinkConstants.animDurationFast,
        curve: BlinkConstants.animCurve,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _pressed && widget.enabled
              ? BlinkColors.accent.withValues(alpha: 0.18)
              : BlinkColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _pressed && widget.enabled
                ? BlinkColors.accent.withValues(alpha: 0.5)
                : BlinkColors.cardBorder,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.item.icon,
              size: 22,
              color: widget.enabled
                  ? (_pressed ? BlinkColors.accent : BlinkColors.textPrimary)
                  : BlinkColors.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(
              widget.item.label,
              style: BlinkTypography.labelSmall.copyWith(
                fontSize: 10,
                letterSpacing: 0.8,
                color: widget.enabled
                    ? (_pressed
                        ? BlinkColors.accent
                        : BlinkColors.textSecondary)
                    : BlinkColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: accent
          ? BlinkColors.accent.withValues(alpha: 0.15)
          : BlinkColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: accent
                  ? BlinkColors.accent.withValues(alpha: 0.5)
                  : BlinkColors.cardBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: accent ? BlinkColors.accent : BlinkColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: BlinkTypography.labelSmall.copyWith(
                  color:
                      accent ? BlinkColors.accent : BlinkColors.textSecondary,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
