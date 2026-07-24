<div align="center">
  <h1>BLINK 🤖</h1>
  <p><b>A companion Android app + ESP32-C3 robot firmware — your little desktop robot with personality.</b></p>
  <p>
    <a href="https://viraj69rip.github.io/Blink/"><strong>🌐 Try the Live OLED Simulator & Website</strong></a>
  </p>
</div>

BLINK is a tiny robot that lives on your desk. It has an animated face with 21 idle micro-animations, responds to touch and shake, plays Mario clock, draws on its OLED, and connects to your phone over Bluetooth.

## ✨ Features

### Robot (ESP32-C3 Firmware)
- **21 idle animations** — curious looks, winking, stargazing, cat face, cool shades, pixel dance, and more
- **Mario Clock** — animated Mario bumps digits at each minute change
- **Touch menu** — single/double/triple tap and long-press gestures
- **Shake detection** — MPU6050 triggers dizzy animation
- **Drawing mode** — receive pen strokes, emoji stamps, and text from the app
- **BLE OTA updates** — receive firmware updates wirelessly from the companion app
- **Night mode** — calmer animations between 10 PM and 6 AM
- **Sound** — optional buzzer for melodies and alerts

### Companion App (Flutter/Android)
- **BLE control** — connect, sync time, send commands
- **Drawing canvas** — pen, emoji (16 stamps), and text tools mapped to the 128×64 OLED
- **Firmware updates** — pick a `.bin` file or auto-download from GitHub Releases, then send over BLE
- **Focus timer** — Pomodoro mode synced to the robot display
- **Expression vault** — browse and trigger animation packs
- **Nothing OS design** — monochrome + red accent, glassmorphism, premium feel

## 🔧 Hardware

| Component | Details |
|---|---|
| MCU | ESP32-C3 SuperMini |
| Display | 0.96" SSD1306 OLED (128×64, I2C) |
| Motion | MPU6050 accelerometer/gyro |
| Touch | Capacitive touch sensor (GPIO 4) |
| Power | LiPo battery with voltage divider (GPIO 2) |
| Audio | Passive/piezo buzzer (GPIO 3, optional) |

## 📦 Downloads

Get the latest firmware and companion app from the [**Releases**](../../releases/latest) page:

| File | Description |
|---|---|
| `BLINK_Firmware_v*.zip` | Firmware — flash to ESP32-C3 via USB (first time) or OTA |
| `BLINK_App_*_release.apk` | Android companion app |

## 🚀 Quick Start

### Flash the Robot (first time, USB)
1. Install [Arduino IDE](https://www.arduino.cc/en/software)
2. Add ESP32 board support, select **ESP32C3 Dev Module**
3. Install libraries: `U8g2`, `NimBLE-Arduino`, `Adafruit MPU6050`, `Adafruit Unified Sensor`, `Adafruit BusIO`
4. Open `firmware/BLINK_Robot/BLINK_Robot.ino` and upload
5. See `firmware/README.md` for wiring and pin details

### Install the App
1. Download the APK from [Releases](../../releases/latest)
2. Install on your Android phone
3. Open BLINK, connect to `BLINK_C3` via Bluetooth
4. Sync time, send expressions, draw on the OLED, update firmware over the air

### OTA Firmware Updates
After the first USB flash of v3.1.0+, future updates can be sent wirelessly:
- **Manual:** Settings → Firmware Update → pick a `.bin` file
- **Auto:** The app checks this GitHub repo for new releases and downloads the `.bin` automatically

## 🏗️ Building from Source

```bash
# Firmware (Arduino CLI)
arduino-cli compile --fqbn esp32:esp32:esp32c3 firmware/BLINK_Robot

# App (Flutter)
cd blink_app
flutter pub get
flutter build apk --release --dart-define=BLINK_GITHUB_REPOSITORY=Viraj69rip/BLINK
```

## 📄 License

Personal project by [@Viraj69rip](https://github.com/Viraj69rip).
