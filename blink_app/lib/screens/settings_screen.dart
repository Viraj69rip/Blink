import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';
import '../utils/app_info.dart';
import '../widgets/firmware_update_sheet.dart';
import '../widgets/blink_components.dart';

/// Settings screen — device configuration, app preferences, and firmware info.
///
/// Stateless: every control it renders is backed by [RobotStateProvider], so
/// there is no local UI state left to hold.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Deliberately no root Consumer: the provider notifies at up to 10 Hz while
    // BLE is streaming, and a Consumer here rebuilt every card in the screen on
    // each one. Each section subscribes to just the fields it renders instead.
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: BlinkConstants.paddingH,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 16),

          // ── Header ─────────────────────────────────────────────
          const Text(
            'Settings',
            style: BlinkTypography.displayLarge,
          ),
          const SizedBox(height: 4),
          const SectionLabel(label: 'DEVICE & APP CONFIGURATION'),

          const SizedBox(height: 24),

          // ── Device Section ─────────────────────────────────────
          const SectionLabel(label: 'DEVICE'),
          const SizedBox(height: 10),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Selector<RobotStateProvider,
                (BleConnectionState, String, String?, int)>(
              selector: (_, s) => (
                s.connectionState,
                s.deviceName,
                s.bleStatusMessage,
                s.batteryLevel,
              ),
              builder: (context, snap, _) {
                final conn = snap.$1;
                final name = snap.$2;
                final msg = snap.$3;
                final battery = snap.$4;
                final connected = conn == BleConnectionState.connected;
                final scanning = conn == BleConnectionState.scanning;
                final subtitle = scanning
                    ? (msg ?? 'Scanning…')
                    : connected
                        ? '$name • Connected'
                        : (msg ?? 'Tap to scan & connect');

                return Column(
                  children: [
                    SettingsTile(
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
                    const BlinkDivider(),
                    SettingsTile(
                      icon: Icons.schedule_rounded,
                      title: 'Sync Time',
                      subtitle: 'Push phone clock to robot RTC',
                      onTap: () async {
                        await context.read<RobotStateProvider>().syncTimeNow();
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
                    const BlinkDivider(),
                    SettingsTile(
                      icon: Icons.battery_charging_full_rounded,
                      title: 'Battery',
                      subtitle: '$battery% remaining',
                      trailing: Text(
                        '$battery%',
                        style: BlinkTypography.mono.copyWith(fontSize: 13),
                      ),
                    ),
                    const BlinkDivider(),
                    const _FirmwareUpdateTile(),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Display Section ────────────────────────────────────
          const SectionLabel(label: 'DISPLAY'),
          const SizedBox(height: 10),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Selector<RobotStateProvider, (int, bool, bool)>(
              selector: (_, s) => (
                s.displayBrightness,
                s.idleAnimationsEnabled,
                s.buzzerEnabled,
              ),
              builder: (context, snap, _) {
                final brightness = snap.$1;
                return Column(
                  children: [
                    SettingsTile(
                      icon: Icons.brightness_6_rounded,
                      title: 'Display Brightness',
                      subtitle:
                          'OLED contrast — ${RobotStateProvider.brightnessLabel(brightness)}',
                      onTap: () => context
                          .read<RobotStateProvider>()
                          .cycleDisplayBrightness(),
                      trailing: Text(
                        RobotStateProvider.brightnessLabel(brightness)
                            .toUpperCase(),
                        style: BlinkTypography.monoSmall,
                      ),
                    ),
                    const BlinkDivider(),
                    SettingsToggleTile(
                      icon: Icons.animation_rounded,
                      title: 'Idle Animations',
                      subtitle: 'Smooth ambient face expressions',
                      value: snap.$2,
                      onChanged: (val) => context
                          .read<RobotStateProvider>()
                          .setIdleAnimations(val),
                    ),
                    const BlinkDivider(),
                    SettingsToggleTile(
                      icon: Icons.volume_up_rounded,
                      title: 'Buzzer Sound',
                      subtitle: 'Enable sound effects for expressions',
                      value: snap.$3,
                      onChanged: (val) => context
                          .read<RobotStateProvider>()
                          .setBuzzerEnabled(val),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Weather & Mood Section ─────────────────────────────
          const SectionLabel(label: 'WEATHER & MOOD'),
          const SizedBox(height: 10),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Consumer<RobotStateProvider>(
              builder: (context, provider, _) {
                final moodData = provider.weatherMoodData;
                return Column(
                  children: [
                    SettingsTile(
                      icon: Icons.wb_sunny_rounded,
                      title: 'Auto Mood Sync',
                      subtitle: moodData != null
                          ? '${moodData.moodLabel} • ${moodData.weather.condition} ${moodData.weather.temperature.toInt()}°C'
                          : 'Syncing weather…',
                      trailing: Icon(
                        moodData != null ? Icons.check_circle : Icons.sync,
                        color: moodData != null
                            ? BlinkColors.accent
                            : BlinkColors.textTertiary,
                        size: 20,
                      ),
                    ),
                    const BlinkDivider(),
                    SettingsTile(
                      icon: Icons.refresh_rounded,
                      title: 'Sync Now',
                      subtitle: 'Force weather & time sync to robot',
                      onTap: () async {
                        await provider.forceWeatherSync();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Weather & time sync sent'),
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
                    const BlinkDivider(),
                    SettingsToggleTile(
                      icon: Icons.schedule_rounded,
                      title: 'Auto Sync',
                      subtitle: 'Automatically sync weather every 30 min',
                      value: provider.weatherAutoSyncEnabled,
                      onChanged: (val) {
                        provider.setWeatherAutoSync(val);
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Sensors Section ────────────────────────────────────
          const SectionLabel(label: 'SENSORS'),
          const SizedBox(height: 10),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Selector<RobotStateProvider, (bool, int)>(
              selector: (_, s) => (
                s.capacitiveTouchEnabled,
                s.touchSensitivity,
              ),
              builder: (context, snap, _) => Column(
                children: [
                  SettingsToggleTile(
                    icon: Icons.touch_app_rounded,
                    title: 'Capacitive Touch',
                    subtitle: 'Enable petting interactions',
                    value: snap.$1,
                    onChanged: (_) => context
                        .read<RobotStateProvider>()
                        .toggleCapacitiveTouch(),
                  ),
                  const BlinkDivider(),
                  SettingsTile(
                    icon: Icons.sensors_rounded,
                    title: 'Sensitivity',
                    subtitle: 'How light a touch BLINK reacts to',
                    onTap: () => context
                        .read<RobotStateProvider>()
                        .cycleTouchSensitivity(),
                    trailing: Text(
                      RobotStateProvider.sensitivityLabel(snap.$2)
                          .toUpperCase(),
                      style: BlinkTypography.monoSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── App Section ────────────────────────────────────────
          const SectionLabel(label: 'APP'),
          const SizedBox(height: 10),

          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'App Version',
                  subtitle: 'BLINK Companion v${AppInfo.version}',
                  trailing: Text(
                    AppInfo.versionLabel,
                    style: BlinkTypography.monoSmall,
                  ),
                ),
                const BlinkDivider(),
                const _AppUpdateTile(),
                const BlinkDivider(),
                SettingsTile(
                  icon: Icons.description_rounded,
                  title: 'Licenses',
                  subtitle: 'Open-source licenses',
                  onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'BLINK',
                      applicationVersion: 'v${AppInfo.version}',
                      applicationLegalese: '© 2026 BLINK Project',
                    );
                  },
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: BlinkColors.textTertiary,
                    size: 20,
                  ),
                ),
                const BlinkDivider(),
                SettingsTile(
                  icon: Icons.restart_alt_rounded,
                  title: 'Factory Reset',
                  subtitle: 'Reset robot to defaults',
                  onTap: () => _showFactoryResetDialog(
                    context,
                    context.read<RobotStateProvider>(),
                  ),
                  trailing: Icon(
                    Icons.chevron_right_rounded,
                    color: BlinkColors.accent.withValues(alpha: 0.7),
                    size: 20,
                  ),
                ),
                const BlinkDivider(),
                SettingsTile(
                  icon: Icons.delete_forever_rounded,
                  title: 'Reset App Data',
                  subtitle: 'Forget BLINK and clear every app preference',
                  onTap: () => _showResetEverythingDialog(
                    context,
                    context.read<RobotStateProvider>(),
                  ),
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
  }

  void _showFactoryResetDialog(BuildContext context, RobotStateProvider state) {
    _showResetDialog(
      context: context,
      title: 'Factory Reset',
      body: 'This will reset all robot settings, expressions, and preferences '
          'to their default values.\n\nThis action cannot be undone.',
      run: state.factoryReset,
      // Evaluated after the reset: a queued RESET only actually reached the
      // robot if the link was still up.
      result: () => state.connectionState == BleConnectionState.connected
          ? 'Robot reset — BLINK boot replayed'
          : 'App reset (connect to sync robot)',
    );
  }

  void _showResetEverythingDialog(
    BuildContext context,
    RobotStateProvider state,
  ) {
    _showResetDialog(
      context: context,
      title: 'Reset App Data',
      body: 'This resets the robot, then forgets the paired BLINK and erases '
          'every preference, cached weather location, and downloaded update on '
          'this phone.\n\nYou will need to scan and pair again. This action '
          'cannot be undone.',
      confirmLabel: 'ERASE',
      run: state.resetEverything,
      result: () => 'App data erased — BLINK forgotten',
    );
  }

  /// Shared confirm-then-run flow for both reset actions.
  ///
  /// [result] is called *after* [run] completes so the confirmation message can
  /// reflect the post-reset state rather than the state at button-press time.
  void _showResetDialog({
    required BuildContext context,
    required String title,
    required String body,
    required Future<void> Function() run,
    required String Function() result,
    String confirmLabel = 'RESET',
  }) {
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
            Expanded(
              child: Text(
                title,
                style: BlinkTypography.titleMedium,
              ),
            ),
          ],
        ),
        content: Text(
          body,
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
              await run();
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
                      Expanded(
                        child: Text(
                          result(),
                          style: BlinkTypography.monoSmall.copyWith(
                            color: BlinkColors.textPrimary,
                          ),
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
              confirmLabel,
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

// ════════════════════════════════════════════════════════════════════════════
// ── HELPER WIDGETS ─────────────────────────────────────────────────────────
// ════════════════════════════════════════════════════════════════════════════

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

        return SettingsTile(
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

class _AppUpdateTile extends StatelessWidget {
  const _AppUpdateTile();

  @override
  Widget build(BuildContext context) {
    return Selector<
        RobotStateProvider,
        (bool, bool, double, bool, String?, String?, bool)>(
      selector: (_, s) => (
        s.isAppUpdateAvailable,
        s.isDownloadingApk,
        s.apkDownloadProgress,
        s.hasDownloadedApk,
        s.appUpdateError,
        s.githubFirmwareVersion,
        s.checkingGitHubFirmware,
      ),
      builder: (context, data, _) {
        final updateAvailable = data.$1;
        final downloading = data.$2;
        final progress = data.$3;
        final downloaded = data.$4;
        final error = data.$5;
        final version = data.$6;
        final checking = data.$7;
        final state = context.read<RobotStateProvider>();

        final subtitle = checking
            ? 'Checking for updates…'
            : error != null
                ? 'Update failed — tap to retry'
                : downloading
                    ? 'Downloading ${(progress * 100).round()}%'
                    : downloaded
                        ? 'v$version downloaded — tap to install'
                        : updateAvailable
                            ? 'v$version available — tap to download'
                            : 'App is up to date';

        return SettingsTile(
          icon: Icons.system_update_rounded,
          title: 'Update App',
          subtitle: subtitle,
          onTap: () async {
            if (downloading || checking) return;
            if (downloaded) {
              final apkPath = state.pendingApkPath;
              if (apkPath != null) {
                _installApk(context, apkPath);
              }
            } else if (updateAvailable || error != null) {
              try {
                await state.downloadAppUpdate();
                if (context.mounted) {
                  final path = state.pendingApkPath;
                  if (path != null) {
                    _installApk(context, path);
                  }
                }
              } catch (_) {}
            } else {
              await state.checkGitHubFirmware();
            }
          },
          trailing: downloading
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
                  updateAvailable || downloaded
                      ? Icons.download_rounded
                      : Icons.check_circle_outline_rounded,
                  color: updateAvailable || downloaded
                      ? BlinkColors.accent
                      : BlinkColors.textTertiary,
                  size: 20,
                ),
        );
      },
    );
  }

  void _installApk(BuildContext context, String apkPath) {
    try {
      final uri = Uri.file(apkPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.install_mobile_rounded,
                  color: BlinkColors.textPrimary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'APK saved — open your file manager to install from:\n${uri.pathSegments.last}',
                  style: BlinkTypography.monoSmall
                      .copyWith(color: BlinkColors.textPrimary),
                ),
              ),
            ],
          ),
          backgroundColor: BlinkColors.surface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: BlinkColors.accent.withValues(alpha: 0.3),
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open installer: $e')),
      );
    }
  }
}
