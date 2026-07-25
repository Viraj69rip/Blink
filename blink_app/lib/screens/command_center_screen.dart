import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';
import '../widgets/firmware_update_sheet.dart';
import '../widgets/pulsing_dot.dart';
import '../widgets/robot_face.dart';
import '../widgets/toggle_card.dart';
import '../widgets/focus_timer_overlay.dart';

/// The Command Center — primary dashboard view for BLINK.
/// Displays connection status, live robot face preview, sensor controls,
/// and firmware deployment action.
class CommandCenterScreen extends StatelessWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: BlinkConstants.paddingH,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top + 16),

          // ── Top Status Bar ─────────────────────────────────────
          const _StatusBar(),

          // ── Update Available Banner ──────────────────────────────
          const _UpdateBanner(),

          const SizedBox(height: BlinkConstants.sectionSpacing),

          // ── Section Label ──────────────────────────────────────
          Text(
            'LIVE PREVIEW',
            style: BlinkTypography.labelSmall.copyWith(
              letterSpacing: 3.0,
            ),
          ),

          const SizedBox(height: 10),

          // ── Hero Live Preview ──────────────────────────────────
          const _HeroPreview(),

          const SizedBox(height: BlinkConstants.sectionSpacing + 4),

          // ── Bento Grid Label ───────────────────────────────────
          Text(
            'CONTROLS',
            style: BlinkTypography.labelSmall.copyWith(
              letterSpacing: 3.0,
            ),
          ),

          const SizedBox(height: 10),

          // ── Sensor & Utility Grid (Bento Box) ──────────────────
          const _BentoGrid(),

          const SizedBox(height: BlinkConstants.sectionSpacing + 4),

          // ── Connect / Disconnect ───────────────────────────────
          const _ConnectButton(),

          const SizedBox(height: 120),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ── STATUS BAR ─────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, _StatusSnapshot>(
      selector: (_, state) => _StatusSnapshot(
        connectionState: state.connectionState,
        deviceName: state.deviceName,
        batteryLevel: state.batteryLevel,
      ),
      builder: (context, state, _) {
        final isConnected =
            state.connectionState == BleConnectionState.connected;
        final statusText = isConnected
            ? '${state.deviceName} • Connected'
            : state.connectionState == BleConnectionState.scanning
                ? 'Scanning...'
                : 'Disconnected';

        return Row(
          children: [
            // Connection indicator dot
            if (isConnected) ...[
              const PulsingDot(size: 8),
              const SizedBox(width: 10),
            ],

            // Device name + status
            Expanded(
              child: Text(
                statusText,
                style: BlinkTypography.monoSmall.copyWith(
                  color: isConnected
                      ? BlinkColors.textSecondary
                      : BlinkColors.textTertiary,
                  letterSpacing: 1.5,
                ),
              ),
            ),

            // ── Battery Widget ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: BlinkColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: BlinkColors.cardBorder,
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Battery icon
                  _BatteryIcon(level: state.batteryLevel),
                  const SizedBox(width: 6),
                  // Battery percentage
                  Text(
                    '${state.batteryLevel}%',
                    style: BlinkTypography.mono.copyWith(
                      fontSize: 12,
                      color: state.batteryLevel > 20
                          ? BlinkColors.textPrimary
                          : BlinkColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatusSnapshot {
  final BleConnectionState connectionState;
  final String deviceName;
  final int batteryLevel;

  const _StatusSnapshot({
    required this.connectionState,
    required this.deviceName,
    required this.batteryLevel,
  });

  @override
  bool operator ==(Object other) =>
      other is _StatusSnapshot &&
      other.connectionState == connectionState &&
      other.deviceName == deviceName &&
      other.batteryLevel == batteryLevel;

  @override
  int get hashCode => Object.hash(connectionState, deviceName, batteryLevel);
}

/// Minimal battery icon using CustomPaint.
class _BatteryIcon extends StatelessWidget {
  final int level;

  const _BatteryIcon({required this.level});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(22, 12),
      painter: _BatteryPainter(
        level: level,
        color: level > 20 ? BlinkColors.textSecondary : BlinkColors.accent,
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  final int level;
  final Color color;

  _BatteryPainter({required this.level, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final outlinePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Battery body
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width - 3, size.height),
      const Radius.circular(2),
    );
    canvas.drawRRect(bodyRect, outlinePaint);

    // Battery tip
    final tipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width - 3,
        size.height * 0.25,
        3,
        size.height * 0.5,
      ),
      const Radius.circular(1),
    );
    canvas.drawRRect(tipRect, fillPaint);

    // Fill level
    final fillWidth = (size.width - 6) * (level / 100);
    final fillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, fillWidth, size.height - 4),
      const Radius.circular(1),
    );
    canvas.drawRRect(fillRect, fillPaint);
  }

  @override
  bool shouldRepaint(covariant _BatteryPainter oldDelegate) {
    return oldDelegate.level != level;
  }
}

/// Banner shown when the connected robot's firmware is older than the latest
/// GitHub release.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, _UpdateBannerSnapshot>(
      selector: (_, state) => _UpdateBannerSnapshot(
        connected: state.connectionState == BleConnectionState.connected,
        updateAvailable: state.isFirmwareUpdateAvailable,
        robotVersion: state.installedFirmwareVersion,
        githubVersion: state.githubFirmwareVersion,
      ),
      builder: (context, data, _) {
        if (!data.connected || !data.updateAvailable) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GestureDetector(
            onTap: () => _openFirmwareSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: BlinkColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: BlinkColors.accent.withValues(alpha: 0.25),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.system_update_rounded,
                      color: BlinkColors.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: BlinkTypography.monoSmall.copyWith(
                          color: BlinkColors.textSecondary,
                          fontSize: 11,
                          height: 1.3,
                        ),
                        children: [
                          const TextSpan(text: 'Update available  '),
                          TextSpan(
                            text: 'v${data.robotVersion} → v${data.githubVersion}',
                            style: const TextStyle(
                              color: BlinkColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: BlinkColors.textTertiary, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openFirmwareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const FirmwareUpdateSheet(),
    );
  }
}

class _UpdateBannerSnapshot {
  final bool connected;
  final bool updateAvailable;
  final String? robotVersion;
  final String? githubVersion;

  const _UpdateBannerSnapshot({
    required this.connected,
    required this.updateAvailable,
    this.robotVersion,
    this.githubVersion,
  });

  @override
  bool operator ==(Object other) =>
      other is _UpdateBannerSnapshot &&
      other.connected == connected &&
      other.updateAvailable == updateAvailable &&
      other.robotVersion == robotVersion &&
      other.githubVersion == githubVersion;

  @override
  int get hashCode =>
      Object.hash(connected, updateAvailable, robotVersion, githubVersion);
}

// ═══════════════════════════════════════════════════════════════════════════
// ── HERO LIVE PREVIEW ──────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _HeroPreview extends StatelessWidget {
  const _HeroPreview();

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, String>(
      selector: (_, state) => state.currentExpression,
      builder: (context, expressionName, _) => Container(
        width: double.infinity,
        height: 260,
        decoration: BoxDecoration(
          color: BlinkColors.surface,
          borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
          border: Border.all(
            color: BlinkColors.cardBorder,
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // ── Subtle corner markers (OLED screen reference) ──────
            ..._buildCornerMarkers(),

            // ── Robot Face ─────────────────────────────────────────
            const Center(
              child: RobotFace(),
            ),

            // ── Expression label at bottom ─────────────────────────
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BlinkColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    expressionName.toUpperCase(),
                    style: BlinkTypography.monoSmall.copyWith(
                      letterSpacing: 2.0,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
            ),

            // ── 1.98" OLED label ───────────────────────────────────
            Positioned(
              top: 12,
              right: 16,
              child: Text(
                '1.98"',
                style: BlinkTypography.monoSmall.copyWith(
                  color: BlinkColors.textTertiary.withValues(alpha: 0.4),
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build subtle corner markers to mimic OLED screen bezels.
  List<Widget> _buildCornerMarkers() {
    const markerColor = BlinkColors.textTertiary;
    const markerSize = 16.0;
    const markerThickness = 0.5;
    const offset = 12.0;

    Widget marker({
      required Alignment alignment,
      required bool flipH,
      required bool flipV,
    }) {
      return Positioned(
        top: alignment == Alignment.topLeft || alignment == Alignment.topRight
            ? offset
            : null,
        bottom: alignment == Alignment.bottomLeft ||
                alignment == Alignment.bottomRight
            ? offset
            : null,
        left:
            alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                ? offset
                : null,
        right: alignment == Alignment.topRight ||
                alignment == Alignment.bottomRight
            ? offset
            : null,
        child: SizedBox(
          width: markerSize,
          height: markerSize,
          child: CustomPaint(
            painter: _CornerMarkerPainter(
              color: markerColor.withValues(alpha: 0.2),
              thickness: markerThickness,
              flipH: flipH,
              flipV: flipV,
            ),
          ),
        ),
      );
    }

    return [
      marker(alignment: Alignment.topLeft, flipH: false, flipV: false),
      marker(alignment: Alignment.topRight, flipH: true, flipV: false),
      marker(alignment: Alignment.bottomLeft, flipH: false, flipV: true),
      marker(alignment: Alignment.bottomRight, flipH: true, flipV: true),
    ];
  }
}

/// Paints an L-shaped corner marker.
class _CornerMarkerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool flipH;
  final bool flipV;

  _CornerMarkerPainter({
    required this.color,
    required this.thickness,
    required this.flipH,
    required this.flipV,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final x1 = flipH ? size.width : 0.0;
    final x2 = flipH ? 0.0 : size.width;
    final y1 = flipV ? size.height : 0.0;
    final y2 = flipV ? 0.0 : size.height;

    path.moveTo(x1, y2 * 0.6);
    path.lineTo(x1, y1);
    path.lineTo(x2 * 0.6, y1);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════════════════════════
// ── BENTO GRID ─────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _BentoGrid extends StatelessWidget {
  const _BentoGrid();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top row: 2 toggle cards side by side
        Row(
          children: [
            // Card A — Capacitive Touch
            Expanded(
              child: SizedBox(
                height: 160,
                child: Selector<RobotStateProvider, bool>(
                  selector: (_, state) => state.capacitiveTouchEnabled,
                  builder: (context, isEnabled, _) => ToggleCard(
                    title: 'Touch',
                    subtitle: 'CAPACITIVE',
                    icon: Icons.touch_app_rounded,
                    isActive: isEnabled,
                    onTap: context
                        .read<RobotStateProvider>()
                        .toggleCapacitiveTouch,
                  ),
                ),
              ),
            ),

            const SizedBox(width: BlinkConstants.gridGap),

            // Card B — custom passive-buzzer melody test
            Expanded(
              child: SizedBox(
                height: 160,
                child: ToggleCard(
                  title: 'Sound',
                  subtitle: 'CUSTOM TONE',
                  icon: Icons.music_note_rounded,
                  isActive: true,
                  onTap: context.read<RobotStateProvider>().playSoundTest,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: BlinkConstants.gridGap),

        // Bottom row: Focus Timer (full width)
        const _FocusTimerCard(),
      ],
    );
  }
}

/// Card C — Focus Timer (Pomodoro widget).
/// Shows current time in monospace; taps to open timer overlay.
class _FocusTimerCard extends StatelessWidget {
  const _FocusTimerCard();

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, _TimerSnapshot>(
      selector: (_, state) => _TimerSnapshot(
        isRunning: state.timerRunning,
        seconds: state.timerSeconds,
      ),
      builder: (context, state, _) => GestureDetector(
        onTap: () => FocusTimerOverlay.show(context),
        child: AnimatedContainer(
          duration: BlinkConstants.animDuration,
          curve: BlinkConstants.animCurve,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: state.timerRunning
                ? BlinkColors.surface
                : BlinkColors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
            border: Border.all(
              color: state.timerRunning
                  ? BlinkColors.accent.withValues(alpha: 0.35)
                  : BlinkColors.cardBorder,
              width: state.timerRunning ? 1.2 : 1.0,
            ),
          ),
          child: Row(
            children: [
              // Icon
              AnimatedContainer(
                duration: BlinkConstants.animDuration,
                curve: BlinkConstants.animCurve,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: state.timerRunning
                      ? BlinkColors.accent.withValues(alpha: 0.1)
                      : BlinkColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.timer_rounded,
                  color: state.timerRunning
                      ? BlinkColors.accent
                      : BlinkColors.textTertiary,
                  size: 22,
                ),
              ),

              const SizedBox(width: 16),

              // Title + Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus Timer',
                      style: BlinkTypography.titleMedium.copyWith(
                        color: state.timerRunning
                            ? BlinkColors.textPrimary
                            : BlinkColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'POMODORO',
                      style: BlinkTypography.monoSmall.copyWith(
                        color: state.timerRunning
                            ? BlinkColors.textSecondary
                            : BlinkColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Timer display
              Text(
                state.timerDisplay,
                style: BlinkTypography.mono.copyWith(
                  fontSize: 20,
                  letterSpacing: 2.0,
                  color: state.timerRunning
                      ? BlinkColors.accent
                      : BlinkColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimerSnapshot {
  final bool timerRunning;
  final int seconds;

  const _TimerSnapshot({required bool isRunning, required this.seconds})
      : timerRunning = isRunning;

  String get timerDisplay {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  bool operator ==(Object other) =>
      other is _TimerSnapshot &&
      other.timerRunning == timerRunning &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(timerRunning, seconds);
}

// ═══════════════════════════════════════════════════════════════════════════
// ── DEPLOY BUTTON ──────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _ConnectButton extends StatelessWidget {
  const _ConnectButton();

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, BleConnectionState>(
      selector: (_, s) => s.connectionState,
      builder: (context, conn, _) {
        final scanning = conn == BleConnectionState.scanning;
        final connected = conn == BleConnectionState.connected;
        final label = scanning
            ? 'SCANNING…'
            : connected
                ? 'DISCONNECT BLINK'
                : 'CONNECT BLINK';

        return GestureDetector(
          onTap: () async {
            final state = context.read<RobotStateProvider>();
            if (connected) {
              await state.disconnect();
            } else if (!scanning) {
              await state.scanAndConnect();
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
              border: Border.all(
                color: BlinkColors.accent.withValues(alpha: 0.6),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                label,
                style: BlinkTypography.mono.copyWith(
                  color: BlinkColors.accent,
                  fontSize: 13,
                  letterSpacing: 3.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
