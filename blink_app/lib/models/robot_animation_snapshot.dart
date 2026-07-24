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
  static RobotAnimationSnapshot? tryParse(String raw) {
    final parts = raw.split(',');
    if (parts.length < 4) return null;
    final stateIndex = int.tryParse(parts[0].trim());
    if (stateIndex == null ||
        stateIndex < 0 ||
        stateIndex >= RobotFaceState.values.length) {
      return null;
    }
    final elapsed = int.tryParse(parts[1].trim()) ?? 0;
    final uptime = int.tryParse(parts[2].trim()) ?? 0;
    final night = parts[3].trim() == '1';
    final focus = parts.length > 4 && parts[4].trim() == '1';
    final draw = parts.length > 5 && parts[5].trim() == '1';
    final battery = parts.length > 6 ? (int.tryParse(parts[6].trim()) ?? 0) : 0;

    return RobotAnimationSnapshot(
      state: RobotFaceState.values[stateIndex],
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
      };
}

/// Matches firmware `RobotState` enum order in BLINK_Robot.ino.
enum RobotFaceState {
  boot,
  idle,
  tickled,
  dizzy,
  yawn,
  sleep,
  appMode,
}
