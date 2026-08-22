# BLINK Project Context

BLINK is a desk robot: an ESP32-C3 with a 128×64 SSD1306 OLED face, a Flutter
Android companion app, and a marketing/download site. The app talks to the robot
over BLE (NimBLE on the robot, `flutter_blue_plus` in Flutter).

This file describes **what the code currently does**. When behaviour and this
file disagree, the code is right and this file is the bug — it has drifted
before. `HANDOFF.md` tracks open work; this file tracks current state.

## Layout

| Path | What it is |
| --- | --- |
| `firmware/BLINK_Robot/BLINK_Robot.ino` | Entire robot firmware, single sketch |
| `blink_app/` | Flutter companion app (Android) |
| `website/` | Vite + React site source |
| `docs/` | Built site — this is what GitHub Pages serves |
| `.github/workflows/` | `ci.yml` (build gate), `pages.yml` (site), `release.yml` (tags) |

## Versions

- Firmware: `FIRMWARE_VERSION = "4.1.0"` (`BLINK_Robot.ino:57`)
- App: `version: 5.1.0+3001` (`blink_app/pubspec.yaml:8`)
- Toolchain floor: Dart `^3.6.0` / Flutter `>=3.27.0`. This is not cosmetic —
  `Color.withValues()` is used ~107 times across `lib/` and landed in Flutter
  3.27. On an older SDK `pub get` succeeds and then nearly every widget file
  fails to compile.
- ESP32 core: Arduino-ESP32 **3.3.11**, pinned identically in `ci.yml` and
  `release.yml`. The firmware needs NimBLE 2.x.

## GitHub

- **Repo:** `Viraj69rip/Blink` — https://github.com/Viraj69rip/Blink
  (Note the casing: the product is *BLINK*, the repo path is *Blink*. URLs are
  case-sensitive; `website/src/config.js` holds the one canonical copy.)
- **Release assets** (`release.yml`, on any `v*` tag):
  - `BLINK_Robot-vX.Y.Z.bin` — compiled ESP32-C3 image
  - `BLINK-Companion-vX.Y.Z-{arm64,armeabi,x86_64}.apk`
  - A guard step fails the release if `.ino` / `.dart` / `.zip` source reaches
    the published assets.
  ```bash
  git tag v4.1.0 && git push origin v4.1.0
  ```
- **`ci.yml`** compiles the firmware, then runs `flutter analyze`,
  `flutter test`, and a debug APK build, then builds the website. Unsigned and
  publishes nothing, so it runs on forks and PRs. This is the build gate — a
  change that does not compile should go red here, not at release time.
- **`pages.yml`** rebuilds `docs/` from `website/` on pushes that touch
  `website/**` and commits the result. Its `paths:` filter is what stops its own
  docs-only commit from retriggering it.

## BLE contract

The robot advertises as `BLINK_C3`, service
`4fafc201-1fb5-459e-8fcc-c5c9c331914b`. Characteristics: time, command,
drawing, state, plus OTA `...26ac` (control), `...26ad` (data),
`...26ae` (version/status). The UUID strings appear verbatim in both
`BLINK_Robot.ino` and `blink_app/lib/services/ble_manager.dart` — change one and
you must change the other.

Commands written to the command characteristic (parsed in `handlePendingBle()`,
`BLINK_Robot.ino:3356`):

| Command | Effect |
| --- | --- |
| `FOCUS`, `FOCUS:MM:SS`, `FOCUS:DONE` | Focus mode, optional timer text |
| `IDLE` | Leave app mode |
| `DRAW` / `DRAW:ON` / `DRAW:OFF` | Enter / leave drawing mode |
| `CLEAR` | Clear the canvas |
| `SW:MM:SS` | Stopwatch overlay text |
| `TOUCH:ON` / `TOUCH:OFF` | Enable / disable the touch sensor |
| `SENS:LOW\|MED\|HIGH` | Touch debounce window — 60 / 25 / 10 ms |
| `BRIGHT:<0-255>` | `u8g2.setContrast()`; the only brightness knob the panel has |
| `MOOD:<-2..2>` | Weather mood bias |
| `ANIM:ON\|OFF\|NEXT\|SPEED:FAST\|SLOW\|<n>` | Idle animation control |
| `EXP:<name>` | Force an expression |
| `SOUND:TEST` / `SOUND:STOP` | Buzzer melody |
| `BUZZER:ON` / `BUZZER:OFF` | Mute the buzzer |
| `SHAKE` | Trigger dizzy without shaking the hardware |
| `RESET` / `FACTORY` / `FACTORY_RESET` | Clear canvas, exit modes, restore defaults, replay the boot animation |

`SENS:` deserves a note: `PIN_TOUCH` (GPIO4) is a plain **digital** input, so
there is no analog threshold to raise. "Sensitivity" is only the debounce
window, which is why the three levels are three millisecond values.

## OTA and app updates

- `Settings → Firmware Update` accepts a compiled `.bin`, copies it into the
  app's documents directory, survives a restart, and posts a daily local
  notification until it installs.
- Protocol: app sends `BEGIN:<byte-count>`, then ordered binary chunks (a 15 ms
  yield every 4 chunks so the BLE stack keeps up), then `END`. The firmware
  checks the size against what was announced, reports the result, and reboots.
  `ABORT` cancels.
- Version, OTA support, transfer state, and progress all come from the robot's
  status characteristic — the app never guesses.
- A robot on a pre-OTA build must be flashed once over USB. It cannot receive
  its first BLE update because it has no receiver yet.
- `Settings → Update App` reads the same GitHub release for `.apk` assets,
  downloads one, and hands it to the Android package installer. The repo slug is
  a compile-time constant (`firmware_update_service.dart:29`) — there is no
  `--dart-define` for it.
- Two distinct reset actions, deliberately separate: **Factory Reset** sends
  `RESET` to the robot; **Reset App Data** clears local app state. Both require
  typing `RESET` to confirm.

## Firmware behaviour

**Touch gestures** (`handleTouchGesture()`, `BLINK_Robot.ino:3006`). A gesture
fires only after the pin has been quiet for `TAP_SETTLE_MS` (260 ms), so a slow
multi-tap still counts:

- **1 tap** → select / confirm
- **2 taps** → open the menu (or advance, if already open)
- **3 taps** → back / exit (a 4th tap is clamped to this)
- **hold ≥600 ms** in the menu → scroll, repeating
- **hold ≥2000 ms** anywhere → return to the main face, never counted as a tap

Raw reads are debounced (`touchStable`) because an undebounced TTP223 tap emits
a burst of edges and runs the counter past 3, which made gestures feel random.
The idle level is sampled at boot, so active-high and active-low breakouts both
work unmodified.

**Menu** (6 items, `BLINK_Robot.ino:210`): Focus Mode, Clock, BLE Status,
HW Info, Sound Test, Go Back. Selected modes are full-screen — the firmware must
never render a face and a time/weather overlay at once.

**Idle animations**: 21 Mochi-style animations, weighted random cycling, with a
night-safe calm-only subset between 10 PM and 6 AM. ~50 FPS, blink-wipe
transitions, pausable with `ANIM:OFF` without freezing the base face. Weather
mood biases the pick via `weatherMood * IDLE_ANIM_ENERGY[idx]`
(`BLINK_Robot.ino:1666`), so a gloomy forecast leans calm and a bright one leans
energetic.

**BLE Status screen**: bold "BLINK" title, connection text, five animated
sine-wave signal bars (outlined when disconnected), and an orbiting glowing dot
— deliberately identical to the website's OLED simulator in "App Mode".

**Shake → dizzy** (`pollMotion()`, `BLINK_Robot.ino:2900`). Not a flat g-force
threshold. A slow EMA (`alpha = 0.06`, ~0.3 s at 50 Hz) of the acceleration
*vector* tracks gravity, and the detector works on the **residual** after
subtracting it, so tilting the robot is not movement but shaking it is. A jolt
is `residual > 3.4 m/s²` **or** `gyro > 210 °/s`; three jolts at least 55 ms
apart within a 750 ms window make a shake, then a 1400 ms cooldown. The MPU is
sampled every tick regardless of state — when it was only read while a shake was
already permitted, the filter had no history and never fired.

**Wiring**: OLED and MPU6050 share I²C on GPIO8 (SDA) / GPIO9 (SCL). Touch on
GPIO4. Battery on GPIO2 through a 2:1 divider. Passive/piezo buzzer on GPIO3 to
GND; `PIN_BUZZER` only needs changing if GPIO3 is taken. `SOUND:TEST` verifies
custom melodies, which use `tone()`/`noTone()` (both present in
arduino-esp32 3.x).

## Drawing

The canvas is a real 128×64 pixel grid, rasterised with the same integer
Bresenham as the firmware, so what the app shows and what the OLED shows are the
same pixels — no rounded-dot fudging.

Both sides are built around *never dropping a segment*:

- **App** (`drawing_canvas.dart`): the local preview updates on every pointer
  sample; BLE sends are coalesced to one in-flight write with the newest point
  always winning, at a ≥20 ms cadence. Coalescing, not discarding — the newest
  queued point is still sent, just later.
- **Firmware** (`BLINK_Robot.ino:438`): incoming segments are parsed straight
  into a 64-entry lock-free SPSC ring (BLE callback writes the head, `loop()`
  drains the whole tail every iteration). The previous design was a single
  `drawBuf` plus an 8 ms throttle that *discarded* anything inside the window —
  between the two, most of a fast stroke never reached the rasteriser, which is
  exactly why drawings came out as disconnected dots.

`CLEAR` waits for the in-flight write before sending, so a late segment cannot
reappear after a clear.

## Website

Vite + React in `website/`, built to `docs/` with `base: '/Blink/'` and
`emptyOutDir: true` (which is why `.nojekyll` has to be recreated after each
build). GitHub Pages serves `main` → `/docs`.

- `website/src/config.js` is the single source of truth for the repo slug, the
  UPI ID, and the order delivery channel. Everything in it is compiled into the
  public bundle, so it must never hold a secret.
- Checkout has no backend. An order can only reach the owner if the buyer's own
  device hands it over — a `wa.me` deep link or `mailto:`. Until
  `ORDER_DELIVERY` is filled in, `PaymentModal` says so plainly and shows the
  order text to copy rather than promising a reply that cannot come.
- The OLED simulator in `Demo.jsx` mirrors the firmware's app-mode animation.

## Important files

- `firmware/BLINK_Robot/BLINK_Robot.ino` — the whole robot.
- `blink_app/lib/services/ble_manager.dart` — BLE, OTA transfer, status.
- `blink_app/lib/services/firmware_update_service.dart` — persistence, daily
  reminders, GitHub release checks, app self-update.
- `blink_app/lib/providers/robot_state_provider.dart` — reactive state; notifies
  only on real changes, not on every 10 Hz poll.
- `blink_app/lib/widgets/drawing_canvas.dart` — pixel-accurate canvas.
- `blink_app/lib/screens/settings_screen.dart` — device config, brightness,
  sensitivity, both resets, update controls.
- `website/src/config.js` — all owner-configurable public values.
- `.github/workflows/ci.yml` — the build gate.
