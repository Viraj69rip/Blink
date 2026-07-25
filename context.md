# BLINK Project Context

BLINK is a Flutter Android companion app and ESP32-C3 robot firmware. The app
uses BLE (NimBLE on the robot, `flutter_blue_plus` in Flutter) and the OLED is
128×64 pixels.

## GitHub repository

- **Repo:** `Viraj69rip/Blink` (public) — https://github.com/Viraj69rip/Blink
- **Current release:** v3.1.0 — https://github.com/Viraj69rip/Blink/releases/tag/v3.1.0
- **Release assets:**
  - `BLINK_Firmware_v3.zip` (25 KB) — Arduino sketch + flash guide.
  - `BLINK_App_v2_release.apk` (45.5 MB) — Android companion app.
- **CI:** `.github/workflows/release.yml` auto-builds firmware `.bin` and APK
  on every `v*` tag push. To cut a new release locally:
  ```
  git tag v3.2.0 && git push origin v3.2.0
  ```

## Current release: firmware v3.1.0

- The robot advertises as `BLINK_C3` with service UUID
  `4fafc201-1fb5-459e-8fcc-c5c9c331914b`.
- Core BLE characteristics are time, commands, drawing, and state. Firmware
  update characteristics are `...26ac` (control), `...26ad` (binary data),
  and `...26ae` (version/status).
- OTA protocol: app sends `BEGIN:<byte-count>`, ordered binary chunks, then
  `END`. Firmware verifies the expected size/image, reports success, and then
  reboots. `ABORT` cancels a transfer.
- A robot running an older build must be flashed over USB once with v3.1.0;
  it cannot receive the first BLE update because it has no OTA receiver.

## App update experience

- Settings > Firmware Update accepts a compiled ESP32 `.bin` file.
- The app copies it to its documents directory, remembers it after a restart,
  and sends a local notification once a day until the update installs.
- Firmware version, OTA support, transfer status, and progress come directly
  from the robot BLE status characteristic.
- Public GitHub releases are enabled with
  `--dart-define=BLINK_GITHUB_REPOSITORY=Viraj69rip/Blink`. The app checks the
  newest release, downloads its `.bin` asset, then queues it for BLE install.
- `.github/workflows/release.yml` builds and publishes matching `.bin` and APK
  assets whenever a `v*` tag is pushed.
- Required packages: `file_picker`, `flutter_local_notifications`,
  `path_provider`, and `shared_preferences`.

## Firmware UX

- The on-device menu contains: Focus Mode, Mario Clock, BLE Status, HW Info,
  Sound Test, Normal Face, and Go Back. Weather and the standalone Time menu
  were intentionally removed.
- Single tap moves down, double tap moves up, triple tap selects. Holding the
  touch sensor for two seconds from any menu/mode returns to the main face.
- Selected modes are full-screen; the firmware must never render a face and a
  time/weather overlay together.
- Idle expressions render at ~50 FPS, use a smooth blink-wipe transition, and
  can be paused through `ANIM:OFF` without freezing the base face.
- MPU6050 shake uses acceleration deviation plus gyro velocity and triggers
  the Dizzy state. Keep OLED and MPU sharing GPIO8/9 I2C.
- Wire a passive/piezo buzzer from GPIO3 to GND. `PIN_BUZZER` can be changed
  only if GPIO3 is used elsewhere; use `SOUND:TEST` to verify custom melodies.

## Drawing

The Flutter drawing canvas displays an actual 128×64 OLED pixel grid. It uses
the same integer Bresenham segments as the firmware, so app strokes and OLED
pixels match without rounded-dot rendering.

## Important files

- `firmware/BLINK_Robot/BLINK_Robot.ino` — robot firmware source.
- `blink_app/lib/services/ble_manager.dart` — BLE, OTA transfer, status.
- `blink_app/lib/services/firmware_update_service.dart` — file persistence and
  daily reminders.
- `blink_app/lib/widgets/drawing_canvas.dart` — pixel-accurate drawing UI.
- `blink_app/lib/screens/settings_screen.dart` — update controls.
- `.github/workflows/release.yml` — CI: builds firmware + APK on `v*` tags.
- `.gitignore` — excludes build artifacts, APKs, IDE files from git.
