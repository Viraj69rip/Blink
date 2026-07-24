==================================================
  BLINK Robot Firmware — Quick Flash Guide
==================================================

HARDWARE NEEDED:
  - ESP32-C3 Mini (SuperMini or equivalent)
  - 0.96" OLED SSD1306 (I2C, 128x64)
  - MPU6050 accelerometer (I2C)
  - Capacitive touch sensor (GPIO 4)
  - LiPo battery + 2:1 voltage divider (GPIO 2)
  - Optional passive/piezo buzzer on a free GPIO

WIRING:
  SDA  = GPIO 8
  SCL  = GPIO 9
  Touch = GPIO 4
  Battery ADC = GPIO 2
  Buzzer + = GPIO 3, Buzzer - = GND

ARDUINO IDE SETUP:
  1. Install Arduino IDE 2.x
  2. Add ESP32 board support:
     File > Preferences > Additional Board URLs:
     https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
  3. Board Manager: install "esp32" by Espressif
  4. Select board: "ESP32C3 Dev Module"
  5. USB CDC On Boot: Enabled
  6. Install libraries (Library Manager):
     - U8g2
     - NimBLE-Arduino
     - Adafruit MPU6050
     - Adafruit Unified Sensor
     - Adafruit BusIO

FLASH:
  1. Open BLINK_Robot.ino in Arduino IDE
  2. Connect ESP32-C3 via USB
  3. Select the correct COM port
  4. Click Upload

NEW FEATURES (v2):
  - Mario Clock: animated Mario walks & jumps to change time digits
  - HW Info: shows ESP32 RAM/CPU/temp/flash stats with progress bars
  - Access: triple-tap touch sensor > scroll to "Mario Clock" or "HW Info" > triple-tap to select
  - Exit: hold touch for 2 seconds to return to normal face

NEW FEATURES (v3.1):
  - BLE firmware updates from the BLINK app (select compiled .bin in Settings)
  - Daily app reminder until a selected update is installed
  - Simplified menu: Focus, Mario Clock, BLE, HW Info, Sound Test,
    Normal Face, Go Back (Weather and standalone Time removed)
  - Stronger MPU shake detection using acceleration + gyro motion
  - Optional custom passive-buzzer melodies
  - Hold touch for 2 seconds from any menu screen to return to the main face

IMPORTANT OTA BOOTSTRAP:
  Flash this v3.1 sketch by USB once. Older firmware has no OTA receiver, so
  it cannot receive its first in-app update. Later compiled .bin updates can
  be sent through Settings > Firmware Update in the app.

EXISTING FEATURES:
  - Animated robot face with blink, tickle, dizzy, yawn, sleep
  - BLE companion app (BLINK_C3)
  - Touch menu: Focus, Mario Clock, BLE Status, HW Info, Sound Test
  - Shake detection (dizzy reaction)
  - Night mode (yawn + sleep)
  - Draw mode via BLE
