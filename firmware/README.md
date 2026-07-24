# BLINK Robot — ESP32-C3 Firmware

Arduino sketch: `BLINK_Robot/BLINK_Robot.ino`

## Libraries (Library Manager)

| Library | Purpose |
|---|---|
| **U8g2** | OLED graphics (non-blocking buffer) |
| **NimBLE-Arduino** (v1.4+ / v2.x) | Lightweight BLE GATT server |
| **Adafruit MPU6050** | Accelerometer shake detection |
| Adafruit Unified Sensor / BusIO | MPU dependency |

## Board settings

- Board: **ESP32C3 Dev Module** (or your C3 Mini package)
- USB CDC On Boot: **Enabled**
- Upload speed: 921600 (or 115200 if unstable)

## Default pins (change at top of `.ino`)

| Signal | GPIO |
|---|---|
| I2C SDA (OLED + MPU6050) | 8 |
| I2C SCL | 9 |
| Touch sensor digital OUT | 4 |
| LiPo battery via 2:1 divider | 2 |
| Passive/piezo buzzer (optional) | 3 |

OLED SSD1306 @ `0x3C`, MPU6050 @ `0x68` on the same I2C bus.

## BLE UUIDs (must match Flutter)

Remap in **both** places if you change them:

- Firmware: `#define SERVICE_UUID` / `TIME_CHAR_UUID` / `CMD_CHAR_UUID` / `DRAW_CHAR_UUID`
- App: `lib/services/ble_manager.dart`

Device advertises as **`BLINK_C3`**.

### Characteristics

| Char | Direction | Payload |
|---|---|---|
| Time Sync | Write | Unix timestamp seconds as ASCII (`1740000000`) |
| Command | Write | `FOCUS`, `FOCUS:12:34`, `FOCUS:DONE`, `IDLE`, `DRAW`, `CLEAR`, `SW:01:23`, `TOUCH:ON`, `SOUND:TEST`, `ANIM:ON/OFF` |
| Draw | Write | `X1,Y1,X2,Y2` OLED pixel line |
| OTA Control | Write | `BEGIN:<byte-count>`, `END`, `ABORT`, `VERSION` |
| OTA Data | Write | Ordered chunks from a compiled ESP32 `.bin` file |
| OTA Status | Read/Notify | Firmware version, update progress, success, or error |

### In-app firmware updates

Firmware v3.1.0 adds a BLE OTA transport. Flash this version by USB once to
bootstrap a robot running older firmware. After that, use **Settings >
Firmware Update** in the companion app: select a compiled `.bin`, connect to
BLINK, and tap Install. The app retains the selected binary and sends one daily
notification until installation succeeds.

### On-robot menu

The touch menu is now: Focus Mode, Mario Clock, BLE Status, HW Info, Sound
Test, Normal Face, and **Go Back**. Weather and the standalone time screen are
removed. Single tap moves forward, double tap moves back, triple tap selects,
and a two-second hold always returns to the main animated face.

## States

`BOOT` (2s “BLINK”) → `IDLE` (eyes + RTC clock) → `TICKLED` / `DIZZY` / `YAWN` → `SLEEP` (2 min) / `APP_MODE`

At night (10 PM–6 AM, after RTC sync), IDLE randomly yawns (~22% every 35s), then sleeps for 2 minutes with floating `zzz` and closed eyes. Touch wakes from yawn/sleep.

Robot keeps time with internal RTC after one BLE sync; sensors work without a phone connected.
