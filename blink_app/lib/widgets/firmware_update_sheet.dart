import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/robot_state_provider.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';

/// Shared bottom-sheet content for firmware update management.
/// Auto-checks GitHub releases and provides a single update flow.
class FirmwareUpdateSheet extends StatefulWidget {
  const FirmwareUpdateSheet({super.key});

  @override
  State<FirmwareUpdateSheet> createState() => _FirmwareUpdateSheetState();
}

class _FirmwareUpdateSheetState extends State<FirmwareUpdateSheet> {
  bool _hasTriggeredCheck = false;

  @override
  Widget build(BuildContext context) {
    // Trigger a GitHub check once when the sheet opens.
    if (!_hasTriggeredCheck) {
      _hasTriggeredCheck = true;
      final state = context.read<RobotStateProvider>();
      if (!state.checkingGitHubFirmware) {
        state.checkGitHubFirmware();
      }
    }

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
          String?,
          String?
        )>(
      selector: (_, s) => (
        s.hasPendingFirmwareUpdate,
        s.pendingFirmwareFileName,
        s.installedFirmwareVersion,
        s.firmwareUpdateSupported,
        s.firmwareUpdateInProgress,
        s.firmwareUpdateProgress,
        s.firmwareUpdateMessage ?? s.firmwareUpdateError,
        s.connectionState,
        s.checkingGitHubFirmware,
        s.hasGitHubFirmware,
        s.githubFirmwareVersion,
        s.githubFirmwareError,
      ),
      builder: (context, data, _) {
        final pending = data.$1;
        final fileName = data.$2;
        final installedVersion = data.$3;
        final supported = data.$4;
        final installing = data.$5;
        final progress = data.$6;
        final message = data.$7;
        final connected = data.$8 == BleConnectionState.connected;
        final checkingGitHub = data.$9;
        final githubAvailable = data.$10;
        final githubVersion = data.$11;
        final githubError = data.$12;
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
                if (checkingGitHub)
                  Text('Checking for updates…',
                      style: BlinkTypography.bodyMedium.copyWith(
                          color: BlinkColors.textTertiary))
                else if (githubError != null)
                  Text(githubError,
                      style: BlinkTypography.bodyMedium.copyWith(
                          color: BlinkColors.accent, height: 1.4))
                else if (githubAvailable)
                  Text(
                    pending
                        ? '${fileName ?? 'firmware.bin'} downloaded · ready to install'
                        : 'GitHub release v$githubVersion available',
                    style: BlinkTypography.bodyMedium.copyWith(
                      color: pending
                          ? BlinkColors.accent
                          : BlinkColors.textSecondary,
                      height: 1.4,
                    ),
                  )
                else
                  Text('No firmware release found.',
                      style: BlinkTypography.bodyMedium.copyWith(
                          color: BlinkColors.textTertiary)),
                if (connected && !supported) ...[
                  const SizedBox(height: 12),
                  Text(
                    'This robot needs a one-time USB flash before it can receive updates over BLE.',
                    style: BlinkTypography.bodyMedium
                        .copyWith(color: BlinkColors.accent, height: 1.4),
                  ),
                ],
                const SizedBox(height: 18),
                if (!githubAvailable && !checkingGitHub && githubError == null)
                  OutlinedButton.icon(
                    onPressed: () => state.checkGitHubFirmware(),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('CHECK FOR UPDATES'),
                  )
                else if (githubAvailable && !pending)
                  FilledButton.icon(
                    onPressed: installing
                        ? null
                        : () async {
                            try {
                              await state.downloadGitHubFirmware();
                            } catch (_) {}
                          },
                    icon: const Icon(Icons.cloud_download_rounded, size: 18),
                    label: Text('DOWNLOAD v$githubVersion'),
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
                if (pending && !installing) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canInstall
                          ? () async {
                              try {
                                await state.installFirmwareUpdate();
                              } catch (_) {}
                            }
                          : null,
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        connected && supported
                            ? 'INSTALL UPDATE'
                            : 'CONNECT BLINK TO INSTALL',
                      ),
                    ),
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
