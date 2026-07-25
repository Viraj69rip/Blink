# BLINK Project Context

BLINK is a Flutter Android companion app and ESP32-C3 robot firmware. The app
uses BLE (NimBLE on the robot, `flutter_blue_plus` in Flutter) and the OLED is
128×64 pixels.

## GitHub repository

- **Repo:** `Viraj69rip/Blink` (public) — https://github.com/Viraj69rip/Blink
- **Current release:** v4.1.0 — https://github.com/Viraj69rip/Blink/releases/latest
- **Release assets:**
  - `BLINK_Robot-vX.Y.Z.bin` — compiled ESP32-C3 firmware binary (no source code).
  - `BLINK-Companion-vX.Y.Z-{arch}.apk` — Android companion app (arm64, armeabi, x86_64).
- **CI:** `.github/workflows/release.yml` auto-builds firmware `.bin` and APK
  on every `v*` tag push. Includes a security check to verify no source code
  (`.ino`, `.zip`, `.dart`) leaks into published release assets.
  ```
  git tag v4.1.0 && git push origin v4.1.0
  ```

## Current release: firmware v4.0.0

- The robot advertises as `BLINK_C3` with service UUID
  `4fafc201-1fb5-459e-8fcc-c5c9c331914b`.
- Core BLE characteristics are time, commands, drawing, and state. Firmware
  update characteristics are `...26ac` (control), `...26ad` (binary data),
  and `...26ae` (version/status).
- OTA protocol: app sends `BEGIN:<byte-count>`, ordered binary chunks (throttled
  every 4 chunks with 15ms yield), then `END`. Firmware verifies the expected
  size/image, reports success, and then reboots. `ABORT` cancels a transfer.
- A robot running an older build must be flashed over USB once with v4.0.0;
  it cannot receive the first BLE update because it has no OTA receiver.

## App update experience

- Settings > Firmware Update accepts a compiled ESP32 `.bin` file.
- The app copies it to its documents directory, remembers it after a restart,
  and sends a local notification once a day until the update installs.
- Firmware version, OTA support, transfer status, and progress come directly
  from the robot BLE status characteristic.
- Public GitHub releases are enabled. The app checks the newest release,
  downloads its `.bin` asset, then queues it for BLE install.
- **App self-update:** Settings > Update App checks the same GitHub release for
  `.apk` assets. The app downloads the APK to its documents directory and
  prompts the user to install it via the Android package installer.
- `.github/workflows/release.yml` builds and publishes matching `.bin` and APK
  assets whenever a `v*` tag is pushed. Source code is never included.
- Required packages: `flutter_blue_plus`, `provider`, `permission_handler`,
  `flutter_local_notifications`, `path_provider`, `shared_preferences`.

## Firmware UX

- The on-device menu contains: Focus Mode, Clock, BLE Status, HW Info,
  Sound Test, and Go Back.
- Single tap moves down, double tap moves up, triple tap selects. Holding the
  touch sensor for two seconds from any menu/mode returns to the main face.
- Selected modes are full-screen; the firmware must never render a face and a
  time/weather overlay together.
- Idle expressions render at ~50 FPS, use a smooth blink-wipe transition, and
  can be paused through `ANIM:OFF` without freezing the base face.
- 21 Mochi-style idle animations with weighted random cycling and night-safe
  subset for calm-only expressions during 10PM–6AM.
- **BLE Status screen:** Displays "BLINK" title in bold, connection status text,
  5 animated sine-wave signal bars (outlined when disconnected), and an orbiting
  glowing dot — matching the website OLED simulator "App Mode" animation.
- MPU6050 shake uses simplified acceleration magnitude (g > 1.12) plus gyro
  velocity (> 150 DPS) and triggers the Dizzy state. No baseline tracking —
  reliable on first shake. Keep OLED and MPU sharing GPIO8/9 I2C.
- Wire a passive/piezo buzzer from GPIO3 to GND. `PIN_BUZZER` can be changed
  only if GPIO3 is used elsewhere; use `SOUND:TEST` to verify custom melodies.
- Custom buzzer melody: C5→E5→A5→C6 jingle plays on Sound Test menu selection.

## Drawing

The Flutter drawing canvas displays an actual 128×64 OLED pixel grid. It uses
the same integer Bresenham segments as the firmware, so app strokes and OLED
pixels match without rounded-dot rendering. BLE writes are throttled to ≤30ms
intervals (buffered locally for instant visual feedback) to prevent flooding
the BLE stack.

## Bug fixes in v4.1.0

- **Drawing delay:** Added 30ms BLE write throttle with local stroke buffering
  for instant visual feedback while preventing BLE stack overflow.
- **Firmware flashing crash:** Added 15ms yield every 4 BLE chunks plus a
  connection-lost guard during OTA transfer.
- **UI reloading:** RobotStateProvider now deduplicates `notifyListeners()` —
  only fires when connection state, expression, or battery actually change,
  eliminating the 10Hz unnecessary UI rebuilds.
- **MPU6050 shake:** Removed fragile baseline learning logic; shake now triggers
  on raw g-force > 1.12 OR gyro > 150 DPS for reliable dizzy animation.
- **Firmware update sheet:** Added animated circular progress indicator with
  percentage display and pulsing activity dot during transfers.

## Important files

- `firmware/BLINK_Robot/BLINK_Robot.ino` — robot firmware source.
- `blink_app/lib/services/ble_manager.dart` — BLE, OTA transfer, status.
- `blink_app/lib/services/firmware_update_service.dart` — file persistence,
  daily reminders, GitHub release checks, and app self-update.
- `blink_app/lib/widgets/drawing_canvas.dart` — pixel-accurate drawing UI
  with BLE write throttling.
- `blink_app/lib/widgets/firmware_update_sheet.dart` — update controls with
  animated circular progress and download percentage.
- `blink_app/lib/screens/settings_screen.dart` — device config, app update,
  and firmware update controls.
- `blink_app/lib/providers/robot_state_provider.dart` — reactive state with
  deduplicated UI notifications.
- `.github/workflows/release.yml` — CI: builds firmware + APK on `v*` tags,
  verifies no source code leaks before publishing.
- `.gitignore` — excludes build artifacts, APKs, IDE files from git.
