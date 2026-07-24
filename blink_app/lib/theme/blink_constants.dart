import 'package:flutter/animation.dart';

/// Animation and layout constants for the BLINK design system.
class BlinkConstants {
  BlinkConstants._();

  // ── Animation Durations ──────────────────────────────────────

  /// Standard micro-interaction duration (toggle, tap feedback)
  static const Duration animDuration = Duration(milliseconds: 300);

  /// Hero/large element animation duration
  static const Duration animDurationSlow = Duration(milliseconds: 600);

  /// Quick feedback (press, release)
  static const Duration animDurationFast = Duration(milliseconds: 150);

  /// Card expand/collapse duration
  static const Duration animDurationExpand = Duration(milliseconds: 350);

  /// Nav bar indicator slide duration
  static const Duration animDurationNav = Duration(milliseconds: 250);

  // ── Animation Curves ─────────────────────────────────────────

  /// Primary curve — smooth deceleration
  static const Curve animCurve = Curves.easeOutCubic;

  /// Entrance curve
  static const Curve animCurveIn = Curves.easeInCubic;

  /// Symmetric curve for looping animations
  static const Curve animCurveSymmetric = Curves.easeInOut;

  // ── Layout Constants ─────────────────────────────────────────

  /// Standard card border radius
  static const double borderRadius = 24.0;

  /// Small border radius
  static const double borderRadiusSmall = 16.0;

  /// Standard horizontal padding
  static const double paddingH = 20.0;

  /// Standard vertical spacing between sections
  static const double sectionSpacing = 16.0;

  /// Grid gap for bento layout
  static const double gridGap = 12.0;

  // ── Robot Face Constants ─────────────────────────────────────

  /// Eye blink interval range (min seconds)
  static const int blinkIntervalMin = 2;

  /// Eye blink interval range (max seconds)
  static const int blinkIntervalMax = 5;

  /// Eye blink animation duration
  static const Duration blinkDuration = Duration(milliseconds: 150);

  /// Night hours (local time) — robot gets sleepy
  static const int nightStartHour = 22;
  static const int nightEndHour = 6;

  /// How often to roll for a random night yawn
  static const Duration nightCheckInterval = Duration(seconds: 35);

  /// % chance per check to start yawn → sleep cycle
  static const int nightYawnChance = 22;

  /// Yawn animation before falling asleep
  static const Duration yawnDuration = Duration(milliseconds: 3200);

  /// Deep sleep duration on OLED / app face
  static const Duration sleepDuration = Duration(minutes: 2);

  // ── Focus Timer Constants ────────────────────────────────────

  /// Default Pomodoro duration in minutes
  static const int pomodoroMinutes = 25;

  /// Short break duration in minutes
  static const int shortBreakMinutes = 5;
}
