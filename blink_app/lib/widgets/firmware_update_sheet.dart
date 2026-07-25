import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// Shared bottom-sheet content for firmware update management.
/// Used by both the command center banner and the settings screen.
class FirmwareUpdateSheet extends StatelessWidget {
  const FirmwareUpdateSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<
        RobotStateProvider,
        (
          bool,
          String?,
          String?,
          bool,
          bool,
          double,
          String?,
          BleConnectionState,
          bool,
          bool,
          bool,
          String?,
          String?,
          String?
        )>(
      selector: (_, state) => (
        state.hasPendingFirmwareUpdate,
        state.pendingFirmwareFileName,
        state.installedFirmwareVersion,
        state.firmwareUpdateSupported,
        state.firmwareUpdateInProgress,
        state.firmwareUpdateProgress,
        state.firmwareUpdateMessage ?? state.firmwareUpdateError,
        state.connectionState,
        state.githubFirmwareConfigured,
        state.checkingGitHubFirmware,
        state.hasGitHubFirmware,
        state.githubFirmwareVersion,
        state.githubFirmwareAssetName,
        state.githubFirmwareError,
      ),
      builder: (context, firmware, _) {
        final pending = firmware.$1;
        final fileName = firmware.$2;
        final installedVersion = firmware.$3;
        final supported = firmware.$4;
        final installing = firmware.$5;
        final progress = firmware.$6;
        final message = firmware.$7;
        final connected = firmware.$8 == BleConnectionState.connected;
        final githubConfigured = firmware.$9;
        final checkingGitHub = firmware.$10;
        final githubAvailable = firmware.$11;
        final githubVersion = firmware.$12;
        final githubAsset = firmware.$13;
        final githubError = firmware.$14;
        final canInstall = pending && connected && supported && !installing;
        final state = context.read<RobotStateProvider>();

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: BlinkColors.surface,
              borderRadius: BorderRadius.circular(BlinkConstants.borderRadius),
              border: Border.all(color: BlinkColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FIRMWARE UPDATE',
                    style: BlinkTypography.labelSmall
                        .copyWith(letterSpacing: 2.5)),
                const SizedBox(height: 12),
                Text(
                  installedVersion == null
                      ? 'BLINK firmware'
                      : 'Installed v$installedVersion',
                  style: BlinkTypography.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  pending
                      ? '${fileName ?? 'Selected .bin'} is ready. A daily reminder stays on until installation succeeds.'
                      : 'Choose the compiled BLINK .bin file to prepare an update.',
                  style: BlinkTypography.bodyMedium
                      .copyWith(color: BlinkColors.textSecondary, height: 1.4),
                ),
                if (connected && !supported) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This robot needs the one-time USB flash of firmware v3.1 before it can receive later updates over BLE.',
                    style: BlinkTypography.bodyMedium
                        .copyWith(color: BlinkColors.accent, height: 1.4),
                  ),
                ],
                const SizedBox(height: 18),
                if (githubConfigured) ...[
                  Text(
                    githubAvailable
                        ? 'GitHub release v${githubVersion ?? 'latest'} · ${githubAsset ?? 'firmware.bin'}'
                        : (githubError ??
                            'Check the latest published firmware release.'),
                    style: BlinkTypography.bodyMedium.copyWith(
                      color: githubAvailable
                          ? BlinkColors.textSecondary
                          : BlinkColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: checkingGitHub
                              ? null
                              : () => state.checkGitHubFirmware(),
                          icon: checkingGitHub
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('CHECK GITHUB'),
                        ),
                      ),
                      if (githubAvailable) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: installing
                                ? null
                                : () async {
                                    try {
                                      await state.downloadGitHubFirmware();
                                    } catch (_) {}
                                  },
                            icon: const Icon(Icons.cloud_download_rounded,
                                size: 18),
                            label: const Text('GET RELEASE'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else
                  Text(
                    'GitHub releases are not configured for this APK. Build with --dart-define=BLINK_GITHUB_REPOSITORY=owner/repository.',
                    style: BlinkTypography.bodyMedium.copyWith(
                      color: BlinkColors.textTertiary,
                      height: 1.4,
                    ),
                  ),
                if (installing || message != null) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: installing ? progress : null,
                    minHeight: 4,
                    backgroundColor: BlinkColors.surfaceVariant,
                    valueColor:
                        const AlwaysStoppedAnimation(BlinkColors.accent),
                  ),
                  const SizedBox(height: 8),
                  Text(message ?? 'Installing…',
                      style: BlinkTypography.monoSmall),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: installing
                            ? null
                            : () async {
                                await state.chooseFirmwareUpdate();
                              },
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('CHOOSE .BIN'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: canInstall
                            ? () async {
                                try {
                                  await state.installFirmwareUpdate();
                                } catch (_) {}
                              }
                            : null,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('INSTALL'),
                      ),
                    ),
                  ],
                ),
                if (pending && !installing) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: state.discardFirmwareUpdate,
                    child: const Text('DISCARD PENDING UPDATE'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
