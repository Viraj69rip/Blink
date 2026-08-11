import 'package:flutter/material.dart';

/// BLINK Design System — Nothing OS inspired visual language.
/// Pure black backgrounds, charcoal cards, monochrome with single red accent.
class BlinkColors {
  BlinkColors._();

  /// Pure black background — optimized for OLED
  static const Color background = Color(0xFF000000);

  /// Deep charcoal for cards and containers
  static const Color surface = Color(0xFF121212);

  /// Surface variant for subtle elevation differences
  static const Color surfaceVariant = Color(0xFF1A1A1A);

  /// Primary text — high contrast white
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text — muted white
  static const Color textSecondary = Color(0xFF888888);

  /// Tertiary text — very subtle
  static const Color textTertiary = Color(0xFF555555);

  /// The single accent color — striking pure red
  /// Used ONLY for: active dot, action button, slider handles
  static const Color accent = Color(0xFFFF3333);

  /// Card border color — white at 10% opacity
  static const Color cardBorder = Color(0x1AFFFFFF);

  /// Divider color
  static const Color divider = Color(0x0DFFFFFF);

  /// OLED-style glow accent — bright cyan-white for active BLE states
  static const Color oledAccent = Color(0xFF33CCFF);

  /// Danger / error color for failed states
  static const Color danger = Color(0xFFFF4444);
}

/// Typography system using platform-native sans-serif + monospace faces.
///
/// This deliberately avoids runtime font downloads. Android ships Roboto and
/// a monospace face, so startup remains fast and the app works identically
/// offline while preserving the original visual hierarchy.
class BlinkTypography {
  BlinkTypography._();

  /// Large display header — clean sans-serif
  static const TextStyle displayLarge = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: BlinkColors.textPrimary,
    letterSpacing: -0.5,
  );

  /// Section header
  static const TextStyle headlineMedium = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: BlinkColors.textPrimary,
    letterSpacing: -0.3,
  );

  /// Card title
  static const TextStyle titleMedium = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: BlinkColors.textPrimary,
  );

  /// Body text
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: BlinkColors.textSecondary,
  );

  /// Small label text
  static const TextStyle labelSmall = TextStyle(
    fontFamily: 'sans-serif',
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: BlinkColors.textTertiary,
    letterSpacing: 1.2,
  );

  /// Monospace — for status values, battery %, timer numbers
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: BlinkColors.textPrimary,
    letterSpacing: 1.5,
  );

  /// Large monospace — for timer display
  static const TextStyle monoLarge = TextStyle(
    fontFamily: 'monospace',
    fontSize: 48,
    fontWeight: FontWeight.w300,
    color: BlinkColors.textPrimary,
    letterSpacing: 4.0,
  );

  /// Monospace small — for labels
  static const TextStyle monoSmall = TextStyle(
    fontFamily: 'monospace',
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: BlinkColors.textSecondary,
    letterSpacing: 1.5,
  );
}

/// Standard card decoration used across the app
class BlinkDecorations {
  BlinkDecorations._();

  /// Standard card container — charcoal fill, thin white border, rounded corners
  static BoxDecoration card = BoxDecoration(
    color: BlinkColors.surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: BlinkColors.cardBorder,
      width: 1,
    ),
  );

  /// Active card — with red accent border
  static BoxDecoration cardActive = BoxDecoration(
    color: BlinkColors.surface,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(
      color: BlinkColors.accent.withValues(alpha: 0.4),
      width: 1,
    ),
  );

  /// Subtle card — even more minimal
  static BoxDecoration cardSubtle = BoxDecoration(
    color: BlinkColors.surface.withValues(alpha: 0.5),
    borderRadius: BorderRadius.circular(16),
    border: Border.all(
      color: BlinkColors.cardBorder,
      width: 0.5,
    ),
  );
}
