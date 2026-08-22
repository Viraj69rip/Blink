/// Live animation frame from the ESP32 robot (STATE BLE notify).
class RobotAnimationSnapshot {
  final RobotFaceState state;
  final int elapsedMs;
  final int uptimeMs;
  final bool isNight;
  final bool focusActive;
  final bool drawMode;
  final int batteryPercent;
  final DateTime receivedAt;

  const RobotAnimationSnapshot({
    required this.state,
    required this.elapsedMs,
    required this.uptimeMs,
    required this.isNight,
    required this.focusActive,
    required this.drawMode,
    required this.batteryPercent,
    required this.receivedAt,
  });

  /// Firmware payload: `state,elapsedMs,uptimeMs,night,focus,draw,battery`
  ///
  /// An unknown state index is clamped to [RobotFaceState.idle] rather than
  /// rejecting the whole frame.  The strict range check used to drop every
  /// notify for states 7–10 (happy/sad/angry/love), which is why triggering an
  /// expression from the app froze the live preview and the battery readout.
  static RobotAnimationSnapshot? tryParse(String raw) {
    final parts = raw.split(',');
    if (parts.length < 4) return null;
    final stateIndex = int.tryParse(parts[0].trim());
    if (stateIndex == null) return null;

    final state = (stateIndex >= 0 && stateIndex < RobotFaceState.values.length)
        ? RobotFaceState.values[stateIndex]
        : RobotFaceState.idle;

    final elapsed = int.tryParse(parts[1].trim()) ?? 0;
    final uptime = int.tryParse(parts[2].trim()) ?? 0;
    final night = parts[3].trim() == '1';
    final focus = parts.length > 4 && parts[4].trim() == '1';
    final draw = parts.length > 5 && parts[5].trim() == '1';
    final battery = parts.length > 6 ? (int.tryParse(parts[6].trim()) ?? 0) : 0;

    return RobotAnimationSnapshot(
      state: state,
      elapsedMs: elapsed,
      uptimeMs: uptime,
      isNight: night,
      focusActive: focus,
      drawMode: draw,
      batteryPercent: battery.clamp(0, 100),
      receivedAt: DateTime.now(),
    );
  }

  String get expressionLabel => switch (state) {
        RobotFaceState.boot => 'Booting',
        RobotFaceState.idle => 'Idle Core',
        RobotFaceState.tickled => 'Tickled',
        RobotFaceState.dizzy => 'Dizzy',
        RobotFaceState.yawn => 'Yawning',
        RobotFaceState.sleep => 'Sleeping',
        RobotFaceState.appMode when drawMode => 'Drawing',
        RobotFaceState.appMode when focusActive => 'Focus',
        RobotFaceState.appMode => 'App Mode',
        RobotFaceState.happy => 'Happy',
        RobotFaceState.sad => 'Sad',
        RobotFaceState.angry => 'Angry',
        RobotFaceState.love => 'In Love',
      };

  /// True for the four app-triggered emotion faces.
  bool get isExpression => switch (state) {
        RobotFaceState.happy ||
        RobotFaceState.sad ||
        RobotFaceState.angry ||
        RobotFaceState.love =>
          true,
        _ => false,
      };
}

/// Matches firmware `RobotState` enum order in BLINK_Robot.ino.
///
/// Order is load-bearing: the firmware notifies the raw enum index, so entries
/// must never be reordered or inserted mid-list — only appended.
enum RobotFaceState {
  boot, // 0
  idle, // 1
  tickled, // 2
  dizzy, // 3
  yawn, // 4
  sleep, // 5
  appMode, // 6
  happy, // 7
  sad, // 8
  angry, // 9
  love, // 10
}
