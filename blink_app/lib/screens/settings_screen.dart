import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';
import '../widgets/firmware_update_sheet.dart';
import '../widgets/glass_container.dart';

/// Settings screen — device configuration, app preferences, and firmware info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoBrightness = true;

  @override
  Widget build(BuildContext context) {
    return Selector<RobotStateProvider, (int, bool, bool)>(
      selector: (_, state) => (
        state.batteryLevel,
        state.capacitiveTouchEnabled,
        state.idleAnimationsEnabled,
      ),
      builder: (context, deviceState, _) {
        final batteryLevel = deviceState.$1;
        final capacitiveTouchEnabled = deviceState.$2;
        final idleAnimationsEnabled = deviceState.$3;
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
                'Settings',
                style: BlinkTypography.displayLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'DEVICE & APP CONFIGURATION',
                style: BlinkTypography.labelSmall.copyWith(
                  letterSpacing: 3.0,
                ),
              ),

              const SizedBox(height: 24),

              // ── Device Section ─────────────────────────────────────
              const _SectionLabel(label: 'DEVICE'),
              const SizedBox(height: 10),

              GlassContainer(
                padding: const EdgeInsets.all(0),
                child: Selector<RobotStateProvider,
                    (BleConnectionState, String, String?)>(
                  selector: (_, s) => (
                    s.connectionState,
                    s.deviceName,
                    s.bleStatusMessage,
                  ),
                  builder: (context, snap, _) {
                    final conn = snap.$1;
                    final name = snap.$2;
                    final msg = snap.$3;
                    final connected = conn == BleConnectionState.connected;
                    final scanning = conn == BleConnectionState.scanning;
                    final subtitle = scanning
                        ? (msg ?? 'Scanning…')
                        : connected
                            ? '$name • Connected'
                            : (msg ?? 'Tap to scan & connect');

                    return Column(
                      children: [
                        _SettingsTile(
                          icon: Icons.bluetooth_rounded,
                          title: 'Bluetooth',
                          subtitle: subtitle,
                          onTap: () async {
                            final state = context.read<RobotStateProvider>();
                            if (connected) {
                              await state.disconnect();
                            } else if (!scanning) {
                              await state.scanAndConnect();
                            }
                          },
                          trailing: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connected
                                  ? BlinkColors.accent
                                  : scanning
                                      ? Colors.amber
                                      : BlinkColors.textTertiary,
                            ),
                          ),
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.schedule_rounded,
                          title: 'Sync Time',
                          subtitle: 'Push phone clock to robot RTC',
                          onTap: () async {
                            await context
                                .read<RobotStateProvider>()
                                .syncTimeNow();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Time sync sent over BLE'),
                                ),
                              );
                            }
                          },
                          trailing: const Icon(
                            Icons.sync_rounded,
                            color: BlinkColors.textTertiary,
                            size: 18,
                          ),
                        ),
                        const _Divider(),
                        _SettingsTile(
                          icon: Icons.battery_charging_full_rounded,
                          title: 'Battery',
                          subtitle: '$batteryLevel% remaining',
                          trailing: Text(
                            '$batteryLevel%',
                            style: BlinkTypography.mono.copyWith(fontSize: 13),
                          ),
                        ),
                        const _Divider(),
                        const _FirmwareUpdateTile(),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ── Display Section ────────────────────────────────────
              const _SectionLabel(label: 'DISPLAY'),
              const SizedBox(height: 10),

              GlassContainer(
                padding: const EdgeInsets.all(0),
                child: Column(
                  children: [
                    _SettingsToggleTile(
                      icon: Icons.brightness_6_rounded,
                      title: 'Auto Brightness',
                      subtitle: 'Adjust OLED based on ambient light',
                      value: _autoBrightness,
                      onChanged: (val) {
                        setState(() {
                          _autoBrightness = val;
                        });
                      },
                    ),
                    const _Divider(),
                    _SettingsToggleTile(
                      icon: Icons.animation_rounded,
                      title: 'Idle Animations',
                      subtitle: 'Smooth ambient face expressions',
                      value: idleAnimationsEnabled,
                      onChanged: (val) {
                        state.setIdleAnimations(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Sensors Section ────────────────────────────────────
              const _SectionLabel(label: 'SENSORS'),
              const SizedBox(height: 10),

              GlassContainer(
                padding: const EdgeInsets.all(0),
                child: Column(
                  children: [
                    _SettingsToggleTile(
                      icon: Icons.touch_app_rounded,
                      title: 'Capacitive Touch',
                      subtitle: 'Enable petting interactions',
                      value: capacitiveTouchEnabled,
                      onChanged: (_) => state.toggleCapacitiveTouch(),
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.sensors_rounded,
                      title: 'Sensitivity',
                      subtitle: 'Medium',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Sensitivity settings not available in this demo.')),
                        );
                      },
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: BlinkColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── About Section ──────────────────────────────────────
              const _SectionLabel(label: 'APP'),
              const SizedBox(height: 10),

              GlassContainer(
                padding: const EdgeInsets.all(0),
                child: Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.info_outline_rounded,
                      title: 'App Version',
                      subtitle: 'BLINK Companion v4.0.0',
                      trailing: Text(
                        '4.0.0',
                        style: BlinkTypography.monoSmall,
                      ),
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.description_rounded,
                      title: 'Licenses',
                      subtitle: 'Open-source licenses',
                      onTap: () {
                        showLicensePage(
                          context: context,
                          applicationName: 'BLINK',
                          applicationVersion: 'v4.0.0',
                          applicationLegalese: '© 2026 BLINK Project',
                        );
                      },
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: BlinkColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    const _Divider(),
                    _SettingsTile(
                      icon: Icons.restart_alt_rounded,
                      title: 'Factory Reset',
                      subtitle: 'Reset robot to defaults',
                      onTap: () => _showFactoryResetDialog(context, state),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: BlinkColors.accent.withValues(alpha: 0.7),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 120),
            ],
          ),
        );
      },
    );
  }

  void _showFactoryResetDialog(BuildContext context, RobotStateProvider state) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => AlertDialog(
        backgroundColor: BlinkColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.5,
          ),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: BlinkColors.accent,
              size: 22,
            ),
            const SizedBox(width: 10),
            Text(
              'Factory Reset',
              style: BlinkTypography.titleMedium,
            ),
          ],
        ),
        content: Text(
          'This will reset all robot settings, expressions, and preferences to their default values.\n\nThis action cannot be undone.',
          style: BlinkTypography.bodyMedium.copyWith(
            color: BlinkColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCEL',
              style: BlinkTypography.labelSmall.copyWith(
                letterSpacing: 2.0,
                color: BlinkColors.textTertiary,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await state.factoryReset();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: BlinkColors.textPrimary,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        state.connectionState == BleConnectionState.connected
                            ? 'Robot reset — BLINK boot replayed'
                            : 'App reset (connect to sync robot)',
                        style: BlinkTypography.monoSmall.copyWith(
                          color: BlinkColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: BlinkColors.surface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: BlinkColors.accent.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              );
            },
            child: Text(
              'RESET',
              style: BlinkTypography.labelSmall.copyWith(
                letterSpacing: 2.0,
                color: BlinkColors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ── HELPER WIDGETS ─────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════

class _FirmwareUpdateTile extends StatelessWidget {
  const _FirmwareUpdateTile();

  @override
  Widget build(BuildContext context) {
    return Selector<
        RobotStateProvider,
        (
          bool,
          String?,
          bool,
          bool,
          double,
          String?,
          String?,
          BleConnectionState,
          bool,
          String?,
          String?
        )>(
      selector: (_, state) => (
        state.hasPendingFirmwareUpdate,
        state.pendingFirmwareFileName,
        state.firmwareUpdateSupported,
        state.firmwareUpdateInProgress,
        state.firmwareUpdateProgress,
        state.firmwareUpdateMessage,
        state.installedFirmwareVersion,
        state.connectionState,
        state.isFirmwareUpdateAvailable,
        state.githubFirmwareVersion,
        state.robotFirmwareVersion,
      ),
      builder: (context, firmware, _) {
        final pending = firmware.$1;
        final fileName = firmware.$2;
        final supported = firmware.$3;
        final installing = firmware.$4;
        final progress = firmware.$5;
        final message = firmware.$6;
        final version = firmware.$7;
        final connected = firmware.$8 == BleConnectionState.connected;
        final updateAvailable = firmware.$9;
        final githubVersion = firmware.$10;
        final robotVersion = firmware.$11;
        final subtitle = installing
            ? (message ?? 'Installing ${(progress * 100).round()}%')
            : pending
                ? '${fileName ?? 'Firmware downloaded'} · ready to install'
                : updateAvailable && connected
                    ? 'Update v$robotVersion → v$githubVersion available'
                    : connected && !supported
                        ? 'USB-flash once to enable in-app updates'
                        : version == null
                            ? 'Connected to check for updates'
                            : updateAvailable
                                ? 'Update v$githubVersion available'
                                : 'Installed v$version';

        return _SettingsTile(
          icon: Icons.system_update_alt_rounded,
          title: 'Firmware Update',
          subtitle: subtitle,
          onTap: () => _showFirmwareSheet(context),
          trailing: installing
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: progress == 0 ? null : progress,
                    color: BlinkColors.accent,
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  pending || updateAvailable
                      ? Icons.notification_important_rounded
                      : Icons.chevron_right_rounded,
                  color: pending || updateAvailable
                      ? BlinkColors.accent
                      : BlinkColors.textTertiary,
                  size: 20,
                ),
        );
      },
    );
  }

  void _showFirmwareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const FirmwareUpdateSheet(),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: BlinkTypography.labelSmall.copyWith(
        letterSpacing: 3.0,
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

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
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: BlinkColors.textSecondary, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          BlinkTypography.titleMedium.copyWith(fontSize: 14)),
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

class _SettingsToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? BlinkColors.accent.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: value ? BlinkColors.accent : BlinkColors.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: BlinkTypography.titleMedium.copyWith(fontSize: 14)),
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
              activeThumbColor: BlinkColors.accent,
              activeTrackColor: BlinkColors.accent.withValues(alpha: 0.3),
              inactiveThumbColor: BlinkColors.textTertiary,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}
