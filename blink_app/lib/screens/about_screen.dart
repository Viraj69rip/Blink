import 'package:flutter/material.dart';
import '../theme/blink_theme.dart';
import '../theme/blink_constants.dart';
import '../utils/app_info.dart';
import '../widgets/glass_container.dart';
import '../widgets/dotted_logo.dart';

/// About screen — app info, credits, and robot identity.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: BlinkConstants.paddingH,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top + 40),

          // ── Hero Logo ──────────────────────────────────────────
          GlassContainer(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
            opacity: 0.05,
            blur: 30,
            child: Column(
              children: [
                // Dotted BLINK logo, large
                const DottedLogo(dotSize: 4.0, spacing: 2.5),
                const SizedBox(height: 20),
                Text(
                  'COMPANION APP',
                  style: BlinkTypography.labelSmall.copyWith(
                    letterSpacing: 6.0,
                    fontSize: 10,
                    color: BlinkColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BlinkColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: BlinkColors.accent.withValues(alpha: 0.3),
                      width: 0.5,
                    ),
                  ),
                  child: Text(
                    'v${AppInfo.version}',
                    style: BlinkTypography.mono.copyWith(
                      fontSize: 12,
                      color: BlinkColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Specs Card ─────────────────────────────────────────
          const GlassContainer(
            padding: EdgeInsets.all(0),
            child: Column(
              children: [
                _SpecRow(label: 'MCU', value: 'ESP32-C3'),
                _SpecDivider(),
                // Matches the panel the firmware actually drives:
                // U8G2_SSD1306_128X64_NONAME_F_HW_I2C.
                _SpecRow(label: 'DISPLAY', value: '0.96" OLED 128×64'),
                _SpecDivider(),
                _SpecRow(label: 'TOUCH', value: 'Capacitive Sensor'),
                _SpecDivider(),
                _SpecRow(label: 'IMU', value: 'MPU6050 6-Axis'),
                _SpecDivider(),
                _SpecRow(label: 'AUDIO', value: 'Piezo Buzzer'),
                _SpecDivider(),
                _SpecRow(label: 'CONNECTIVITY', value: 'BLE 5 (NimBLE)'),
                _SpecDivider(),
                _SpecRow(label: 'PROTOCOL', value: 'GATT Custom Service'),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Credits Card ───────────────────────────────────────
          GlassContainer(
            padding: const EdgeInsets.all(24),
            opacity: 0.04,
            child: Column(
              children: [
                Icon(
                  Icons.favorite_rounded,
                  color: BlinkColors.accent.withValues(alpha: 0.6),
                  size: 24,
                ),
                const SizedBox(height: 12),
                Text(
                  'Designed & Built with precision',
                  style: BlinkTypography.bodyMedium.copyWith(
                    color: BlinkColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'NOTHING INSPIRES EVERYTHING',
                  style: BlinkTypography.labelSmall.copyWith(
                    letterSpacing: 4.0,
                    fontSize: 9,
                    color: BlinkColors.textTertiary,
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
}

class _SpecRow extends StatelessWidget {
  final String label;
  final String value;
  const _SpecRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: BlinkTypography.labelSmall.copyWith(
              letterSpacing: 2.0,
              color: BlinkColors.textTertiary,
            ),
          ),
          Text(
            value,
            style: BlinkTypography.mono.copyWith(
              fontSize: 12,
              color: BlinkColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpecDivider extends StatelessWidget {
  const _SpecDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}
