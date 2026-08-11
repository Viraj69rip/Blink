/**
 * BLINK Robot — ESP32-C3 Mini firmware
 *
 * Hardware: ESP32-C3 Mini, 0.96" OLED SSD1306 (I2C), MPU6050 (I2C),
 *           single-pin capacitive touch, 3.7V LiPo.
 *
 * Libraries (Arduino Library Manager):
 *   - U8g2
 *   - NimBLE-Arduino
 *   - Adafruit MPU6050 (+ Adafruit Unified Sensor, Adafruit BusIO)
 *
 * Board: ESP32C3 Dev Module (or your C3 Mini board package)
 * Upload: USB CDC On Boot = Enabled (recommended for serial debug)
 *
 * UUID remap note:
 *   Keep SERVICE_UUID / TIME_CHAR_UUID / CMD_CHAR_UUID / DRAW_CHAR_UUID
 *   identical on firmware and Flutter (ble_manager.dart). Change both sides together.
 */

#include <Wire.h>
#include <sys/time.h>
#include <time.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <esp_random.h>
#include <Update.h>

#include <U8g2lib.h>
#include <NimBLEDevice.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>

// ─── Pin map (ESP32-C3 SuperMini / common C3 Mini) ─────────────────────────
// Adjust if your breakout uses different I2C / touch pins.
static const int PIN_SDA     = 8;
static const int PIN_SCL     = 9;
static const int PIN_TOUCH   = 4;   // digital HIGH = touched
static const int PIN_BATTERY = 2;   // LiPo via 2:1 divider → ADC (adjust if your board differs)
// Passive/piezo buzzer. Connect + to GPIO3 and - to GND. Change this only if
// GPIO3 is already used in your build; never share the OLED/MPU I2C pins.
static const int PIN_BUZZER  = 3;

// ─── BLE UUIDs (must match Flutter) ────────────────────────────────────────
// Remap tip: generate new 128-bit UUIDs and paste the same strings into
// blink_app/lib/services/ble_manager.dart
#define DEVICE_NAME      "BLINK_C3"
#define SERVICE_UUID     "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define TIME_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"  // Write: Unix seconds
#define CMD_CHAR_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a9"  // Write: FOCUS / IDLE / DRAW / CLEAR / SW:...
#define DRAW_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26aa"  // Write: "X1,Y1,X2,Y2"
#define STATE_CHAR_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26ab"  // Notify: state,elapsed,uptime,night,focus,draw
#define OTA_CONTROL_UUID "beb5483e-36e1-4688-b7f5-ea07361b26ac"  // Write: BEGIN:size / END / ABORT
#define OTA_DATA_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26ad"  // Write: firmware binary chunks
#define OTA_STATUS_UUID  "beb5483e-36e1-4688-b7f5-ea07361b26ae"  // Read/notify: version and OTA progress

static const char* FIRMWARE_VERSION = "4.0.0";

// ─── Timing / thresholds ───────────────────────────────────────────────────
static const uint32_t BOOT_MS           = 2200;
static const uint32_t TICKLE_MS         = 2200;
static const uint32_t DIZZY_MS          = 3200;
static const uint32_t YAWN_MS           = 3200;   // yawn build → peak → settle
static const uint32_t SLEEP_MS          = 120000; // 2 minutes deep sleep
static const uint32_t FRAME_MS          = 16;    // ~60 FPS — ultra-smooth OLED motion
static const uint32_t SENSOR_MS         = 20;    // faster sensor polling
static const uint32_t TIME_REFRESH_MS   = 1000;
static const uint32_t STATE_NOTIFY_MS   = 50;    // ~20 Hz live preview sync to app
static const uint32_t NIGHT_CHECK_MS    = 35000; // roll for sleepy yawn ~every 35s
static const uint8_t  NIGHT_YAWN_CHANCE = 22;    // % chance per check (22% ≈ once / ~2.5 min)
static const int      NIGHT_START_HOUR  = 22;    // 10 PM
static const int      NIGHT_END_HOUR    = 6;     // 6 AM
static const float    SHAKE_THRESHOLD   = 1.08f; // total acceleration threshold in g (more sensitive)
static const float    SHAKE_DELTA_G     = 0.18f; // sudden motion above the resting baseline (more sensitive)
static const float    SHAKE_GYRO_DPS    = 120.0f; // rotational shake threshold (more sensitive)
static const uint32_t SHAKE_COOLDOWN_MS = 600;  // prevents repeated dizzy restarts (faster recovery)
static const uint32_t TAP_MAX_MS        = 300;   // max touch duration counted as tap
static const uint32_t TAP_GAP_MS        = 350;   // max gap between taps in a gesture
static const uint32_t TAP_SETTLE_MS     = 400;   // idle time before gesture fires
static const uint32_t LONG_PRESS_MS     = 2000;  // hold to return to main face

// Drawing BLE throttle - reduced for ultra-low latency
static const uint32_t DRAW_BLE_THROTTLE_MS = 8; // ~125 Hz max draw updates

static const int OLED_W = 128;
static const int OLED_H = 64;

// ─── Hardware ──────────────────────────────────────────────────────────────
// Sine lookup table (64 entries, 0-63 → sin(0..2π) scaled -31..+31)
static const int8_t SIN_LUT[64] = {
  0, 3, 6, 9, 12, 15, 18, 21, 24, 26, 28, 30, 31, 31, 31, 31,
  31, 30, 28, 26, 24, 21, 18, 15, 12, 9, 6, 3, 0, -3, -6, -9,
  -12, -15, -18, -21, -24, -26, -28, -30, -31, -31, -31, -31,
  -31, -30, -28, -26, -24, -21, -18, -15, -12, -9, -6, -3, 0,
  3, 6, 9, 12, 15, 18
};

// SSD1306 128x64 I2C, hardware I2C, no reset pin
U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);
Adafruit_MPU6050 mpu;
bool mpuOk = false;
uint32_t lastMpuRetryAt = 0;
static const uint32_t MPU_RETRY_MS = 5000;  // retry MPU init every 5s if it failed

// ─── State machine ─────────────────────────────────────────────────────────
enum RobotState : uint8_t {
  STATE_BOOT = 0,
  STATE_IDLE,
  STATE_TICKLED,
  STATE_DIZZY,
  STATE_YAWN,
  STATE_SLEEP,
  STATE_APP_MODE,
  STATE_HAPPY,
  STATE_SAD,
  STATE_ANGRY,
  STATE_LOVE
};

RobotState state = STATE_BOOT;
uint32_t stateEnteredAt = 0;
uint32_t lastFrameAt = 0;
uint32_t lastSensorAt = 0;
uint32_t lastShakeAt = 0;
uint32_t lastNightCheckAt = 0;
uint32_t animPhase = 0;

// Blink randomization for idle face
uint32_t nextBlinkAt = 0;
bool blinkActive = false;
uint32_t blinkStartAt = 0;
static const uint32_t BLINK_DURATION_MS = 150;

static const uint32_t EXPRESSION_MS = 5000;  // expressions auto-return after 5s

bool timeSynced = false;
bool touchEnabled = true;
bool focusActive = false;
bool drawMode = false;
bool buzzerEnabled = true;  // Buzzer mute/unmute
char stopwatchText[16] = "";   // optional "MM:SS" overlay from app
bool idleAnimationsEnabled = true;

// BLE pairing animation state
enum BlePairState : uint8_t {
  BLE_PAIR_IDLE = 0,
  BLE_PAIR_SCANNING,
  BLE_PAIR_CONNECTING,
  BLE_PAIR_CONNECTED,
  BLE_PAIR_FAILED
};
BlePairState blePairState = BLE_PAIR_IDLE;
uint32_t blePairAnimStartAt = 0;
uint32_t blePairStateEnteredAt = 0;

// Weather/mood sync from app
int8_t weatherMood = 0;  // -2=sad, -1=gloomy, 0=neutral, 1=happy, 2=excited
uint32_t lastWeatherSyncAt = 0;

// OLED display mode selected from on-robot touch menu
enum DisplayMode : uint8_t {
  DISPLAY_NORMAL = 0,
  DISPLAY_FOCUS,
  DISPLAY_BLE,
  DISPLAY_MARIO_CLOCK,
  DISPLAY_HW_INFO
};

DisplayMode displayMode = DISPLAY_NORMAL;
bool menuOpen = false;
int menuIndex = 0;
static const int MENU_COUNT = 6;
static const char* MENU_ITEMS[MENU_COUNT] = {
  "Focus Mode",
  "Clock",
  "BLE Status",
  "HW Info",
  "Sound Test",
  "Go Back"
};

// Touch gesture detection (single / double / triple tap)
bool touchActive = false;
bool touchWasActive = false;
uint32_t touchDownAt = 0;
uint32_t touchUpAt = 0;
int pendingTapCount = 0;
uint32_t tapWindowStart = 0;
uint32_t lastGestureAt = 0;

// Long-press detection: hold from any menu screen to return to the main face.
bool longPressTriggered = false;

// ─── Idle Animation Pool (Mochi-style varied expressions) ────────────────
static const int IDLE_ANIM_COUNT = 21;
int  currentIdleAnim      = 0;              // index into animation pool
uint32_t idleAnimStartedAt  = 0;            // when current animation began
uint32_t idleAnimDuration   = 7000;         // ms before switching (randomized)
uint32_t idleTransitionStartAt = 0;         // crossfade start time
bool     idleTransitioning  = false;
int      nextIdleAnim       = -1;
static const uint32_t IDLE_TRANSITION_MS = 400; // blink-wipe transition duration

// Weights: higher = more likely to be picked during daytime
static const uint8_t IDLE_ANIM_WEIGHTS[IDLE_ANIM_COUNT] = {
  5,  // 0  Default face (most common)
  3,  // 1  Curious
  2,  // 2  Winking
  3,  // 3  Stargazing
  2,  // 4  Bouncy
  3,  // 5  Sleepy blink
  2,  // 6  Cat face
  3,  // 7  Sparkle eyes
  2,  // 8  Confused
  2,  // 9  Whistling
  2,  // 10 Nervous
  2,  // 11 Cool shades
  2,  // 12 Chewing
  1,  // 13 Peeking (rare)
  2,  // 14 Heart bubbles
  1,  // 15 Robot scan (rare)
  1,  // 16 Pixel dance (rare)
  3,  // 17 Dreamy
  2,  // 18 Excited shake
  2,  // 19 Tongue out
  2,  // 20 Snoring
};

// Night-safe animations (calm/quiet only)
static const int NIGHT_SAFE_ANIMS[] = {0, 3, 5, 14, 17, 20};
static const int NIGHT_SAFE_COUNT   = 6;

// ─── Mario Clock State ───────────────────────────────────────────────────
enum MarioClockState : uint8_t {
  MCLOCK_IDLE = 0,
  MCLOCK_WALKING,
  MCLOCK_JUMPING,
  MCLOCK_WALKING_OFF
};

MarioClockState mclockState = MCLOCK_IDLE;
float mclock_x = -15.0f;            // Mario X position (starts off-screen)
float mclock_jumpY = 0.0f;          // Jump Y offset (negative = up)
float mclock_jumpVel = 0.0f;        // Jump velocity
int   mclock_baseY = 62;            // Ground Y position
bool  mclock_facingRight = true;
int   mclock_walkFrame = 0;
uint32_t mclock_lastUpdate = 0;

// Displayed time for Mario clock
int   mclock_dispHour = 0;
int   mclock_dispMin = 0;
int   mclock_lastMin = -1;
bool  mclock_animTriggered = false;
bool  mclock_digitBounceTriggered = false;

// Digit bounce animation
float mclock_digitOffY[5] = {0};
float mclock_digitVelY[5] = {0};

// Target tracking for minute-change digit bumps
int   mclock_numTargets = 0;
int   mclock_targetX[4] = {0};
int   mclock_targetDigitIdx[4] = {0};
int   mclock_targetDigitVal[4] = {0};
int   mclock_curTarget = 0;

// Digit X positions (for size-3 text equivalent, 18px spacing)
static const int MCLOCK_DIGIT_X[5] = {19, 37, 55, 73, 91};
static const int MCLOCK_TIME_Y = 26;
static const float MCLOCK_JUMP_POWER = -4.5f;
static const float MCLOCK_GRAVITY = 0.6f;
static const int MCLOCK_HEAD_OFFSET = 10;
static const int MCLOCK_DIGIT_BOTTOM = 47; // TIME_Y + 21
static const float MCLOCK_BOUNCE_VEL = 2.0f;
static const int MCLOCK_START_X = -15;
static const uint32_t MCLOCK_ANIM_MS = 35; // ~28 FPS animation tick

// MPU baseline + battery
float mpuBaselineG = 1.0f;
bool mpuBaselineReady = false;
uint32_t lastBatteryReadAt = 0;
int batteryPercent = 0;

// Drawing buffer: lines stored as segments for redraw in APP_MODE
struct DrawSeg {
  int16_t x1, y1, x2, y2;
};
static const int MAX_SEGS = 256;
DrawSeg segs[MAX_SEGS];
int segCount = 0;

// BLE
NimBLEServer* bleServer = nullptr;
NimBLECharacteristic* timeChar = nullptr;
NimBLECharacteristic* cmdChar = nullptr;
NimBLECharacteristic* drawChar = nullptr;
NimBLECharacteristic* stateChar = nullptr;
NimBLECharacteristic* otaControlChar = nullptr;
NimBLECharacteristic* otaDataChar = nullptr;
NimBLECharacteristic* otaStatusChar = nullptr;
bool bleConnected = false;
uint32_t lastStateNotifyAt = 0;

bool otaInProgress = false;
bool otaRestartPending = false;
size_t otaExpectedBytes = 0;
size_t otaReceivedBytes = 0;
uint32_t otaRestartAt = 0;
size_t otaLastReportedBytes = 0;

struct ToneStep {
  uint16_t frequency;
  uint16_t durationMs;
  uint16_t gapMs;
};

const ToneStep* activeTone = nullptr;
uint8_t activeToneCount = 0;
uint8_t activeToneIndex = 0;
uint32_t toneStepStartedAt = 0;
bool tonePlaying = false;

static const ToneStep SOUND_BOOT[] = {{523, 70, 25}, {659, 70, 25}, {784, 120, 0}};
static const ToneStep SOUND_TICKLE[] = {{784, 55, 20}, {1047, 90, 0}};
static const ToneStep SOUND_DIZZY[] = {{330, 80, 20}, {294, 80, 20}, {247, 120, 0}};
static const ToneStep SOUND_FOCUS_DONE[] = {{784, 90, 30}, {784, 90, 30}, {1047, 180, 0}};
static const ToneStep SOUND_CUSTOM[] = {{523, 100, 20}, {659, 100, 20}, {880, 150, 40}, {1047, 200, 0}};

// Expression sound effects - matching dasai mochi / chotubot style
static const ToneStep SOUND_HAPPY[] = {{659, 60, 15}, {784, 60, 15}, {1047, 60, 15}, {1319, 120, 0}};
static const ToneStep SOUND_SAD[] = {{392, 120, 30}, {330, 150, 30}, {294, 200, 0}};
static const ToneStep SOUND_ANGRY[] = {{220, 80, 15}, {247, 80, 15}, {277, 80, 15}, {311, 150, 0}};
static const ToneStep SOUND_LOVE[] = {{523, 80, 20}, {659, 80, 20}, {784, 80, 20}, {1047, 180, 0}};
static const ToneStep SOUND_SLEEP[] = {{392, 200, 50}, {349, 200, 50}, {330, 300, 0}};
static const ToneStep SOUND_WAKE[] = {{523, 80, 20}, {659, 80, 20}, {784, 80, 20}, {1047, 150, 0}};
static const ToneStep SOUND_PAIRING[] = {{659, 50, 15}, {784, 50, 15}, {880, 50, 15}, {1047, 50, 15}, {1319, 100, 0}};
static const ToneStep SOUND_CONNECTED[] = {{784, 80, 20}, {1047, 80, 20}, {1319, 150, 0}};
static const ToneStep SOUND_DISCONNECTED[] = {{392, 100, 20}, {349, 100, 20}, {330, 150, 0}};
static const ToneStep SOUND_MENU_OPEN[] = {{523, 60, 15}, {659, 60, 0}};
static const ToneStep SOUND_MENU_SELECT[] = {{784, 50, 10}, {1047, 80, 0}};
static const ToneStep SOUND_TAP[] = {{1047, 30, 0}};

// Pending BLE payloads (set in callbacks, handled in loop — keep callbacks short)
volatile bool pendingTime = false;
volatile bool pendingCmd = false;
volatile bool pendingDraw = false;
char timeBuf[24];
char cmdBuf[48];
char drawBuf[32];

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

bool isNightTime();
void notifyRobotState(bool force = false);

void notifyOtaStatus(const char* status) {
  if (otaStatusChar == nullptr) return;
  otaStatusChar->setValue(status);
  if (bleConnected) otaStatusChar->notify();
}

void playCustomSound(const ToneStep* steps, uint8_t count) {
  if (PIN_BUZZER < 0 || steps == nullptr || count == 0 || !buzzerEnabled) return;
  activeTone = steps;
  activeToneCount = count;
  activeToneIndex = 0;
  toneStepStartedAt = 0;
  tonePlaying = false;
}

void stopCustomSound() {
  if (PIN_BUZZER >= 0) noTone(PIN_BUZZER);
  activeTone = nullptr;
  activeToneCount = 0;
  tonePlaying = false;
}

void updateCustomSound() {
  if (activeTone == nullptr || activeToneIndex >= activeToneCount || PIN_BUZZER < 0) return;
  uint32_t now = millis();
  const ToneStep& step = activeTone[activeToneIndex];

  if (!tonePlaying) {
    tone(PIN_BUZZER, step.frequency);
    toneStepStartedAt = now;
    tonePlaying = true;
    return;
  }

  if (now - toneStepStartedAt < step.durationMs) return;
  noTone(PIN_BUZZER);
  if (now - toneStepStartedAt < step.durationMs + step.gapMs) return;

  activeToneIndex++;
  tonePlaying = false;
  if (activeToneIndex >= activeToneCount) stopCustomSound();
}

void beginOtaUpdate(size_t totalBytes) {
  if (otaInProgress) {
    notifyOtaStatus("OTA:ERROR:busy");
    return;
  }
  if (totalBytes == 0 || totalBytes > ESP.getFreeSketchSpace()) {
    notifyOtaStatus("OTA:ERROR:size");
    return;
  }
  if (!Update.begin(totalBytes, U_FLASH)) {
    notifyOtaStatus("OTA:ERROR:begin");
    return;
  }

  otaExpectedBytes = totalBytes;
  otaReceivedBytes = 0;
  otaLastReportedBytes = 0;
  otaInProgress = true;
  menuOpen = false;
  notifyOtaStatus("OTA:READY");
}

void abortOtaUpdate(const char* reason) {
  if (otaInProgress) Update.abort();
  otaInProgress = false;
  char status[40];
  snprintf(status, sizeof(status), "OTA:ERROR:%s", reason);
  notifyOtaStatus(status);
}

void finishOtaUpdate() {
  if (!otaInProgress || otaReceivedBytes != otaExpectedBytes) {
    abortOtaUpdate("incomplete");
    return;
  }
  if (!Update.end()) {
    abortOtaUpdate("verify");
    return;
  }

  otaInProgress = false;
  notifyOtaStatus("OTA:SUCCESS");
  otaRestartPending = true;
  otaRestartAt = millis() + 800;
}

void maybeRestartAfterOta() {
  if (otaRestartPending && millis() >= otaRestartAt) {
    ESP.restart();
  }
}

// Forward declarations for idle animation pool
int pickNextIdleAnim();

void enterState(RobotState next) {
  state = next;
  stateEnteredAt = millis();
  animPhase = 0;
  lastStateNotifyAt = 0;

  // Reset idle animation cycling when entering IDLE
  if (next == STATE_IDLE) {
    currentIdleAnim = pickNextIdleAnim();
    idleAnimStartedAt = millis();
    idleAnimDuration = 5000 + (esp_random() % 5001);
    idleTransitioning = false;
  }

  if (next == STATE_TICKLED) {
    playCustomSound(SOUND_TICKLE, sizeof(SOUND_TICKLE) / sizeof(SOUND_TICKLE[0]));
  } else if (next == STATE_DIZZY) {
    playCustomSound(SOUND_DIZZY, sizeof(SOUND_DIZZY) / sizeof(SOUND_DIZZY[0]));
  } else if (next == STATE_HAPPY) {
    playCustomSound(SOUND_HAPPY, sizeof(SOUND_HAPPY) / sizeof(SOUND_HAPPY[0]));
  } else if (next == STATE_SAD) {
    playCustomSound(SOUND_SAD, sizeof(SOUND_SAD) / sizeof(SOUND_SAD[0]));
  } else if (next == STATE_ANGRY) {
    playCustomSound(SOUND_ANGRY, sizeof(SOUND_ANGRY) / sizeof(SOUND_ANGRY[0]));
  } else if (next == STATE_LOVE) {
    playCustomSound(SOUND_LOVE, sizeof(SOUND_LOVE) / sizeof(SOUND_LOVE[0]));
  } else if (next == STATE_YAWN) {
    playCustomSound(SOUND_SLEEP, sizeof(SOUND_SLEEP) / sizeof(SOUND_SLEEP[0]));
  } else if (next == STATE_SLEEP) {
    // Sleep is silent - just the yawn sound was played
  } else if (next == STATE_BOOT) {
    playCustomSound(SOUND_BOOT, sizeof(SOUND_BOOT) / sizeof(SOUND_BOOT[0]));
  }

  notifyRobotState(true);
}

void notifyRobotState(bool force) {
  if (!bleConnected || stateChar == nullptr) return;
  uint32_t now = millis();
  if (!force && now - lastStateNotifyAt < STATE_NOTIFY_MS) return;
  lastStateNotifyAt = now;

  char buf[48];
  snprintf(buf, sizeof(buf), "%u,%lu,%lu,%u,%u,%u,%d",
           (unsigned)state,
           (unsigned long)(now - stateEnteredAt),
           (unsigned long)now,
           isNightTime() ? 1u : 0u,
           focusActive ? 1u : 0u,
           drawMode ? 1u : 0u,
           batteryPercent);
  stateChar->setValue((uint8_t*)buf, strlen(buf));
  stateChar->notify();
}

void setRtcFromUnix(long unixSec) {
  struct timeval tv;
  tv.tv_sec = unixSec;
  tv.tv_usec = 0;
  settimeofday(&tv, nullptr);
  timeSynced = true;
}

void formatLocalTime(char* out, size_t n) {
  time_t now = time(nullptr);
  struct tm t;
  localtime_r(&now, &t);
  snprintf(out, n, "%02d:%02d", t.tm_hour, t.tm_min);
}

void formatLocalDate(char* out, size_t n) {
  time_t now = time(nullptr);
  struct tm t;
  localtime_r(&now, &t);
  static const char* days[] = {"SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"};
  snprintf(out, n, "%s %02d/%02d", days[t.tm_wday], t.tm_mday, t.tm_mon + 1);
}

int clampi(int v, int lo, int hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

float clampf(float v, float lo, float hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

// Smoothstep ease 0→1
float easeInOut(float t) {
  t = clampf(t, 0.0f, 1.0f);
  return t * t * (3.0f - 2.0f * t);
}

bool isNightTime() {
  if (!timeSynced) return false;
  time_t now = time(nullptr);
  struct tm t;
  localtime_r(&now, &t);
  return (t.tm_hour >= NIGHT_START_HOUR || t.tm_hour < NIGHT_END_HOUR);
}

void drawClosedSleepEyes(int leftCx, int rightCx, int cy, int lookX) {
  for (int e = 0; e < 2; e++) {
    int cx = (e == 0 ? leftCx : rightCx) + lookX;
    // Soft curved lids — peaceful closed eyes
    u8g2.drawCircle(cx, cy + 3, 10, U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawCircle(cx, cy + 3, 9, U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawHLine(cx - 9, cy + 3, 19);
  }
}

void drawFloatingZzz(uint32_t t, int headX, int headY) {
  // Three drifting z's at staggered phases — classic sleep comic style
  static const char* zChars[] = {"z", "Z", "z"};
  static const uint8_t fontIdx[] = {0, 1, 0};  // 0=4x6, 1=5x7, 2=6x12
  for (int i = 0; i < 3; i++) {
    float cycle = fmodf(t / 900.0f + i * 0.34f, 1.0f);
    float drift = easeInOut(cycle);
    int x = headX + 18 + i * 10 + (int)(drift * 14.0f);
    int y = headY - (int)(drift * 20.0f) + (int)(sinf(t / 400.0f + i) * 1.5f);
    if (fontIdx[i] == 0) u8g2.setFont(u8g2_font_4x6_tr);
    else if (fontIdx[i] == 1) u8g2.setFont(u8g2_font_5x7_tr);
    else u8g2.setFont(u8g2_font_6x12_tr);
    u8g2.drawStr(x, y, zChars[i]);
  }
  // Gentle wobbling "zzz" label near forehead
  u8g2.setFont(u8g2_font_5x7_tr);
  int wob = (int)(sinf(t / 550.0f) * 2.0f);
  u8g2.drawStr(96 + wob, 10, "zzz");
}

void drawNightMoon(int x, int y) {
  u8g2.setDrawColor(1);
  u8g2.drawDisc(x, y, 5);
  u8g2.setDrawColor(0);
  u8g2.drawDisc(x + 3, y - 1, 4);
  u8g2.setDrawColor(1);
  // Tiny star sparkle
  u8g2.drawPixel(x - 8, y - 4);
  u8g2.drawPixel(x - 7, y - 3);
  u8g2.drawPixel(x - 6, y - 4);
}

void clearDrawing() {
  segCount = 0;
}

void factoryResetRobot() {
  clearDrawing();
  focusActive = false;
  drawMode = false;
  touchEnabled = true;
  displayMode = DISPLAY_NORMAL;
  menuOpen = false;
  menuIndex = 0;
  stopwatchText[0] = '\0';
  idleAnimationsEnabled = true;
  // Replay boot "BLINK" animation, then return to IDLE with kept RTC
  enterState(STATE_BOOT);
}

void addDrawLine(int x1, int y1, int x2, int y2) {
  x1 = clampi(x1, 0, OLED_W - 1);
  y1 = clampi(y1, 0, OLED_H - 1);
  x2 = clampi(x2, 0, OLED_W - 1);
  y2 = clampi(y2, 0, OLED_H - 1);
  if (segCount >= MAX_SEGS) {
    // Drop oldest half to keep streaming drawings alive
    memmove(segs, segs + MAX_SEGS / 2, (MAX_SEGS / 2) * sizeof(DrawSeg));
    segCount = MAX_SEGS / 2;
  }
  segs[segCount++] = {(int16_t)x1, (int16_t)y1, (int16_t)x2, (int16_t)y2};
}

// Bresenham line with solid pixels — avoids gaps on SSD1306 diagonals
void drawLineSolid(int x0, int y0, int x1, int y1) {
  int dx = abs(x1 - x0);
  int sx = x0 < x1 ? 1 : -1;
  int dy = -abs(y1 - y0);
  int sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;

  while (true) {
    u8g2.drawPixel(x0, y0);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 >= dy) {
      err += dy;
      x0 += sx;
    }
    if (e2 <= dx) {
      err += dx;
      y0 += sy;
    }
  }
}

bool parseDrawPayload(const char* s) {
  // Exact format: "X1,Y1,X2,Y2"
  int x1, y1, x2, y2;
  if (sscanf(s, "%d,%d,%d,%d", &x1, &y1, &x2, &y2) != 4) return false;
  addDrawLine(x1, y1, x2, y2);
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// OLED face / screens (smooth, millis-driven ~50 FPS)
// ═══════════════════════════════════════════════════════════════════════════

void drawRoundedEye(int cx, int cy, int w, int h) {
  // Pixel-perfect filled capsule eyes for SSD1306
  int hw = w / 2;
  int hh = h / 2;
  if (h <= 3) {
    // Very thin eye (blink) — draw thick horizontal line
    u8g2.drawBox(cx - hw, cy - 1, w, clampi(h, 2, 3));
    return;
  }
  int r = clampi(h / 3, 1, 4);
  // Filled rounded box for solid pixels, no gaps
  u8g2.drawRBox(cx - hw, cy - hh, w, h, r);
  // Reinforce fill to cover any sub-pixel gaps on SSD1306
  u8g2.drawBox(cx - hw + r, cy - hh, w - 2 * r, h);
  u8g2.drawBox(cx - hw, cy - hh + r, w, h - 2 * r);
}

void drawEyesBase(int leftCx, int rightCx, int cy, int w, int h, int lookX) {
  drawRoundedEye(leftCx + lookX, cy, w, h);
  drawRoundedEye(rightCx + lookX, cy, w, h);
}

void drawIdleFace(uint32_t t) {
  u8g2.setDrawColor(1);
  // Breathing bob + slow look-around — always happy open eyes
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 2.5f);
  int lookX = (int)(sinf(t / 2200.0f) * 3.0f);
  bool night = isNightTime();

  int baseEyeH = 18;
  int eyeH = baseEyeH;

  // Randomized blink: 3-5 second interval, non-blocking
  uint32_t now = millis();
  if (!blinkActive && now >= nextBlinkAt) {
    blinkActive = true;
    blinkStartAt = now;
    nextBlinkAt = now + 3000 + (esp_random() % 2001); // 3000-5000ms
  }
  if (blinkActive) {
    uint32_t blinkElapsed = now - blinkStartAt;
    if (blinkElapsed < BLINK_DURATION_MS) {
      float p = blinkElapsed / (float)BLINK_DURATION_MS;
      float lid = (p < 0.5f) ? easeInOut(p * 2.0f) : easeInOut((1.0f - p) * 2.0f);
      eyeH = (int)(baseEyeH - lid * (baseEyeH - 2));
      eyeH = clampi(eyeH, 2, baseEyeH);
    } else {
      blinkActive = false;
    }
  }

  drawEyesBase(40, 88, 27 + bob, 22, eyeH, lookX);

  // Happy curved smile — thicker, properly positioned, pixel-perfect
  int smileY = 44 + bob;  // moved up from 48 to avoid clipping
  for (int dx = -12; dx <= 12; dx++) {
    int y = smileY + (int)(dx * dx * 0.045f);  // steeper curve = more visible smile
    u8g2.drawPixel(64 + dx + lookX, y);
    u8g2.drawPixel(64 + dx + lookX, y + 1);  // 2px thick
    if (abs(dx) < 10) {
      u8g2.drawPixel(64 + dx + lookX, y + 2);  // 3px thick center
    }
  }

  if (night) {
    drawNightMoon(116, 9);
  }
  // The normal face intentionally has no clock/weather overlay.
}

// ═══════════════════════════════════════════════════════════════════════════
// Idle Animation Pool — Mochi-style varied expressions (20 animations)
// Each function draws a unique personality micro-animation at ~50 FPS
// ═══════════════════════════════════════════════════════════════════════════

// Normal idle mode deliberately has no secondary display overlays. Menu
// options are full-screen and are rendered only from STATE_APP_MODE.
void drawIdleOverlays() {
  return;
}

// ─── Animation 1: Curious Look ────────────────────────────────────────
void drawIdle_Curious(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 800.0f);
  int bob = (int)(breath * 1.5f);
  float lookCycle = sinf(t / 1800.0f);
  int lookX = (int)(lookCycle * 12.0f);

  // Raised eyebrows
  int browLift = 2 + (int)(fabsf(lookCycle) * 3.0f);
  u8g2.drawHLine(30 + lookX, 14 - browLift + bob, 12);
  u8g2.drawHLine(30 + lookX, 15 - browLift + bob, 12);
  u8g2.drawHLine(86 + lookX, 14 - browLift + bob, 12);
  u8g2.drawHLine(86 + lookX, 15 - browLift + bob, 12);

  // Wide curious eyes
  drawEyesBase(40, 88, 27 + bob, 22, 20, lookX);

  // Pupils tracking look direction
  u8g2.setDrawColor(0);
  u8g2.drawDisc(40 + lookX + lookX / 3, 27 + bob, 4);
  u8g2.drawDisc(88 + lookX + lookX / 3, 27 + bob, 4);
  u8g2.setDrawColor(1);
  u8g2.drawDisc(40 + lookX + lookX / 3, 27 + bob, 2);
  u8g2.drawDisc(88 + lookX + lookX / 3, 27 + bob, 2);

  // Small surprised mouth
  u8g2.drawEllipse(64 + lookX / 2, 46 + bob, 4, 2, U8G2_DRAW_ALL);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(48, 62, "hmm?");
}

// ─── Animation 2: Winking ────────────────────────────────────────────
void drawIdle_Winking(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 2.0f);

  // Left eye: normal
  drawRoundedEye(40, 27 + bob, 22, 18);

  // Right eye: winking cycle
  uint32_t winkCycle = t % 3000;
  if (winkCycle < 2000) {
    u8g2.drawCircle(88, 30 + bob, 10, U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawCircle(88, 30 + bob, 9, U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawHLine(78, 30 + bob, 20);
  } else {
    drawRoundedEye(88, 27 + bob, 22, 18);
  }

  // Playful tongue sticking out
  int tongueY = 46 + bob;
  u8g2.drawHLine(58, tongueY, 12);
  u8g2.drawDisc(68, tongueY + 4, 4);
  u8g2.setDrawColor(0);
  u8g2.drawBox(58, tongueY - 3, 16, 4);
  u8g2.setDrawColor(1);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(52, 62, ";P");
}

// ─── Animation 3: Stargazing ─────────────────────────────────────────
void drawIdle_Stargazing(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 900.0f);
  int bob = (int)(breath * 1.5f);

  // Eyes looking upward
  drawEyesBase(40, 88, 24 + bob, 22, 16, 0);
  u8g2.setDrawColor(0);
  u8g2.drawDisc(40, 20 + bob, 3);
  u8g2.drawDisc(88, 20 + bob, 3);
  u8g2.setDrawColor(1);
  u8g2.drawDisc(40, 20 + bob, 1);
  u8g2.drawDisc(88, 20 + bob, 1);

  // Small awe mouth
  u8g2.drawEllipse(64, 44 + bob, 5, 3, U8G2_DRAW_ALL);

  // Twinkling stars across top
  float phase = t / 500.0f;
  for (int i = 0; i < 6; i++) {
    float starP = fmodf(phase + i * 1.1f, 6.283f);
    float bri = (sinf(starP) + 1.0f) / 2.0f;
    if (bri > 0.5f) {
      int sx = 8 + (i * 21) % 112;
      int sy = 3 + (i * 7) % 14;
      u8g2.drawPixel(sx, sy);
      u8g2.drawPixel(sx - 1, sy);
      u8g2.drawPixel(sx + 1, sy);
      u8g2.drawPixel(sx, sy - 1);
      u8g2.drawPixel(sx, sy + 1);
      if (bri > 0.8f) {
        u8g2.drawPixel(sx - 2, sy);
        u8g2.drawPixel(sx + 2, sy);
      }
    }
  }
}

// ─── Animation 4: Bouncy ────────────────────────────────────────────
void drawIdle_Bouncy(uint32_t t) {
  u8g2.setDrawColor(1);
  float bounceRaw = fabsf(sinf(t / 200.0f));
  float bounce = bounceRaw * bounceRaw;
  int bob = (int)(bounce * 12.0f);

  // Squash & stretch
  int eyeW = clampi(22 - (int)(bounce * 6.0f), 16, 22);
  int eyeH = clampi(14 + (int)(bounce * 6.0f), 14, 22);
  drawEyesBase(40, 88, 30 - bob, eyeW, eyeH, 0);

  // Smile widens at bottom of bounce
  int smileY = 48 - bob;
  int smileW = 8 + (int)((1.0f - bounce) * 6.0f);
  for (int dx = -smileW; dx <= smileW; dx++) {
    int y = smileY + (int)(dx * dx * 0.035f);
    u8g2.drawPixel(64 + dx, y);
    u8g2.drawPixel(64 + dx, y + 1);
  }

  // Impact lines at bottom
  if (bounce < 0.15f) {
    u8g2.drawHLine(26, 56, 8);
    u8g2.drawHLine(94, 56, 8);
  }
}

// ─── Animation 5: Sleepy Blink ──────────────────────────────────────
void drawIdle_SleepyBlink(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 1400.0f);
  int bob = (int)(breath * 1.0f);

  // Very slow heavy blink
  float blinkP = fmodf(t / 2500.0f, 1.0f);
  int eyeH;
  if (blinkP < 0.7f) eyeH = 8;
  else if (blinkP < 0.8f) {
    eyeH = 8 + (int)(easeInOut((blinkP - 0.7f) / 0.1f) * 8.0f);
  } else if (blinkP < 0.9f) {
    eyeH = 16 - (int)(easeInOut((blinkP - 0.8f) / 0.1f) * 8.0f);
  } else eyeH = 8;

  drawEyesBase(40, 88, 30 + bob, 22, eyeH, 0);

  // Droopy eyebrows
  u8g2.drawLine(30, 17 + bob, 50, 19 + bob);
  u8g2.drawLine(78, 19 + bob, 98, 17 + bob);

  // Tiny yawn mouth
  int mouthH = 2 + (int)(fabsf(sinf(t / 3000.0f)) * 4.0f);
  u8g2.drawEllipse(64, 48 + bob, 6, mouthH, U8G2_DRAW_ALL);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(52, 62, "...");
}

// ─── Animation 6: Cat Face ──────────────────────────────────────────
void drawIdle_CatFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 800.0f);
  int bob = (int)(breath * 1.5f);

  // Large round eyes with vertical slit pupils
  drawRoundedEye(40, 27 + bob, 24, 20);
  drawRoundedEye(88, 27 + bob, 24, 20);

  // Slit pupils
  u8g2.setDrawColor(0);
  u8g2.drawBox(38, 19 + bob, 4, 16);
  u8g2.setDrawColor(1);
  u8g2.drawBox(39, 20 + bob, 2, 14);
  u8g2.setDrawColor(0);
  u8g2.drawBox(86, 19 + bob, 4, 16);
  u8g2.setDrawColor(1);
  u8g2.drawBox(87, 20 + bob, 2, 14);

  // Cat nose triangle
  u8g2.drawTriangle(62, 40 + bob, 66, 40 + bob, 64, 43 + bob);

  // Whiskers (3 per side)
  int wy = 44 + bob;
  u8g2.drawLine(20, wy - 2, 55, wy);
  u8g2.drawLine(18, wy + 1, 55, wy + 2);
  u8g2.drawLine(20, wy + 4, 55, wy + 4);
  u8g2.drawLine(73, wy, 108, wy - 2);
  u8g2.drawLine(73, wy + 2, 110, wy + 1);
  u8g2.drawLine(73, wy + 4, 108, wy + 4);

  // Cat ears at top
  u8g2.drawTriangle(28, 8 + bob, 36, 8 + bob, 32, 2 + bob);
  u8g2.drawTriangle(92, 8 + bob, 100, 8 + bob, 96, 2 + bob);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(48, 62, "nya~");
}

// ─── Animation 7: Sparkle Eyes ──────────────────────────────────────
void drawIdle_SparkleEyes(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 600.0f);
  int bob = (int)(breath * 2.0f);
  float pulse = 1.0f + sinf(t / 300.0f) * 0.2f;

  // Big pulsing round eyes
  int eyeR = (int)(12.0f * pulse);
  u8g2.drawDisc(40, 27 + bob, eyeR);
  u8g2.drawDisc(88, 27 + bob, eyeR);

  // Star sparkle cut-outs inside each eye
  u8g2.setDrawColor(0);
  for (int e = 0; e < 2; e++) {
    int cx = (e == 0) ? 40 : 88;
    int cy = 27 + bob;
    int s = (int)(5.0f * pulse);
    u8g2.drawHLine(cx - s, cy, s * 2 + 1);
    u8g2.drawVLine(cx, cy - s, s * 2 + 1);
    u8g2.drawPixel(cx - s / 2, cy - s / 2);
    u8g2.drawPixel(cx + s / 2, cy - s / 2);
    u8g2.drawPixel(cx - s / 2, cy + s / 2);
    u8g2.drawPixel(cx + s / 2, cy + s / 2);
  }
  u8g2.setDrawColor(1);

  // Ooh mouth
  u8g2.drawEllipse(64, 46 + bob, 6, 4, U8G2_DRAW_ALL);

  // Floating sparkle particles
  float sparkT = t / 400.0f;
  for (int i = 0; i < 4; i++) {
    float a = sparkT + i * 1.57f;
    int sx = 64 + (int)(cosf(a) * 30.0f);
    int sy = 20 + (int)(sinf(a * 0.7f) * 10.0f);
    if (sx > 2 && sx < 126 && sy > 2 && sy < 62) {
      u8g2.drawPixel(sx, sy);
      u8g2.drawPixel(sx - 1, sy);
      u8g2.drawPixel(sx + 1, sy);
      u8g2.drawPixel(sx, sy - 1);
      u8g2.drawPixel(sx, sy + 1);
    }
  }

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(48, 62, "ooh!");
}

// ─── Animation 8: Confused ──────────────────────────────────────────
void drawIdle_Confused(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 800.0f);
  int bob = (int)(breath * 1.5f);

  // Uneven eyes: left wide, right squinted
  drawRoundedEye(40, 27 + bob, 24, 20);
  drawRoundedEye(88, 30 + bob, 18, 8);

  // Tilted eyebrows
  u8g2.drawLine(30, 16 + bob, 48, 13 + bob);
  u8g2.drawLine(30, 17 + bob, 48, 14 + bob);
  u8g2.drawLine(80, 18 + bob, 98, 22 + bob);
  u8g2.drawLine(80, 19 + bob, 98, 23 + bob);

  // Wavy uncertain mouth
  int smileY = 46 + bob;
  for (int dx = -10; dx <= 10; dx++) {
    int y = smileY + (int)(sinf(dx * 0.5f + t / 400.0f) * 2.0f);
    u8g2.drawPixel(64 + dx, y);
    u8g2.drawPixel(64 + dx, y + 1);
  }

  // Floating "?"
  float qBob = sinf(t / 500.0f) * 3.0f;
  u8g2.setFont(u8g2_font_logisoso16_tr);
  u8g2.drawStr(108, 18 + (int)qBob, "?");
}

// ─── Animation 9: Whistling ─────────────────────────────────────────
void drawIdle_Whistling(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 1.5f);
  int lookX = 5;

  // Eyes looking sideways (innocent)
  drawEyesBase(40, 88, 27 + bob, 20, 16, lookX);

  // Small O-shaped whistling mouth
  int mouthR = 3 + (int)(sinf(t / 300.0f) * 1.5f);
  u8g2.drawCircle(64 + lookX, 46 + bob, mouthR);
  u8g2.drawCircle(64 + lookX, 46 + bob, mouthR - 1);

  // Floating musical notes
  for (int i = 0; i < 3; i++) {
    float noteP = fmodf(t / 1200.0f + i * 0.33f, 1.0f);
    int nx = 80 + i * 12 + (int)(sinf(noteP * 6.283f) * 4.0f);
    int ny = 30 - (int)(noteP * 28.0f);
    if (ny > 2 && noteP < 0.9f) {
      u8g2.drawDisc(nx, ny, 2);
      u8g2.drawVLine(nx + 2, ny - 6, 6);
      u8g2.drawPixel(nx + 3, ny - 6);
      u8g2.drawPixel(nx + 4, ny - 5);
    }
  }
}

// ─── Animation 10: Nervous ──────────────────────────────────────────
void drawIdle_Nervous(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 500.0f);
  int bob = (int)(breath * 0.8f);

  // Rapid eye darting
  float dartP = fmodf(t / 400.0f, 1.0f);
  int lookX;
  if (dartP < 0.25f) lookX = -6;
  else if (dartP < 0.5f) lookX = 6;
  else if (dartP < 0.75f) lookX = -3;
  else lookX = 4;

  // Small worried eyes
  drawEyesBase(40, 88, 27 + bob, 18, 14, lookX);

  // Worried eyebrows
  u8g2.drawLine(30, 18 + bob, 48, 14 + bob);
  u8g2.drawLine(80, 14 + bob, 98, 18 + bob);

  // Wobbly mouth
  int smileY = 48 + bob;
  for (int dx = -8; dx <= 8; dx++) {
    int y = smileY + (int)(sinf(dx * 0.8f) * 2.0f);
    u8g2.drawPixel(64 + dx, y);
  }

  // Animated sweat drop
  float sweatP = fmodf(t / 800.0f, 1.0f);
  int sweatY = 12 + (int)(sweatP * 18.0f);
  if (sweatP < 0.8f) {
    u8g2.drawPixel(108, sweatY);
    u8g2.drawPixel(107, sweatY + 1);
    u8g2.drawPixel(109, sweatY + 1);
    u8g2.drawPixel(108, sweatY + 2);
  }

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(44, 62, "ehehe..");
}

// ─── Animation 11: Cool Shades ──────────────────────────────────────
void drawIdle_CoolShades(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 1000.0f);
  int bob = (int)(breath * 1.5f);

  int glassY = 22 + bob;
  // Left lens
  u8g2.drawRBox(26, glassY, 28, 14, 3);
  // Right lens
  u8g2.drawRBox(74, glassY, 28, 14, 3);
  // Bridge
  u8g2.drawHLine(54, glassY + 5, 20);
  u8g2.drawHLine(54, glassY + 6, 20);
  // Arms
  u8g2.drawHLine(20, glassY + 5, 6);
  u8g2.drawHLine(102, glassY + 5, 6);

  // Inner lens (dark) + glint
  u8g2.setDrawColor(0);
  u8g2.drawRBox(28, glassY + 2, 24, 10, 2);
  u8g2.drawRBox(76, glassY + 2, 24, 10, 2);
  u8g2.setDrawColor(1);
  u8g2.drawPixel(33, glassY + 4);
  u8g2.drawPixel(34, glassY + 4);
  u8g2.drawPixel(81, glassY + 4);
  u8g2.drawPixel(82, glassY + 4);

  // Asymmetric smirk
  int smileY = 44 + bob;
  for (int dx = -8; dx <= 12; dx++) {
    float curve = (dx < 0) ? dx * dx * 0.02f : -dx * 0.4f;
    int y = smileY + (int)curve;
    u8g2.drawPixel(60 + dx, y);
    u8g2.drawPixel(60 + dx, y + 1);
  }

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(52, 62, "B)");
}

// ─── Animation 12: Chewing ──────────────────────────────────────────
void drawIdle_Chewing(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 1.0f);

  // Happy arc eyes (closed from enjoyment)
  for (int i = 0; i < 3; i++) {
    u8g2.drawCircle(40, 30 + bob, 10 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawCircle(88, 30 + bob, 10 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
  }

  // Chewing mouth
  float chewP = fmodf(t / 350.0f, 1.0f);
  float chewOpen = fabsf(sinf(chewP * 3.14159f));
  int mouthH = 2 + (int)(chewOpen * 8.0f);
  u8g2.drawEllipse(64, 46 + bob, 8, mouthH / 2, U8G2_DRAW_ALL);

  // Puffing cheeks
  int cheekR = 4 + (int)((1.0f - chewOpen) * 3.0f);
  u8g2.drawCircle(22, 38 + bob, cheekR);
  u8g2.drawCircle(106, 38 + bob, cheekR);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(40, 62, "nom nom");
}

// ─── Animation 13: Peeking ─────────────────────────────────────────
void drawIdle_Peeking(uint32_t t) {
  u8g2.setDrawColor(1);

  // Face peeks up from bottom edge
  float peekCycle = fmodf(t / 4000.0f, 1.0f);
  int peekY;
  if (peekCycle < 0.3f)
    peekY = 64 - (int)(easeInOut(peekCycle / 0.3f) * 30.0f);
  else if (peekCycle < 0.7f)
    peekY = 34;
  else
    peekY = 34 + (int)(easeInOut((peekCycle - 0.7f) / 0.3f) * 30.0f);

  if (peekY < 60) {
    int lookX = (int)(sinf(t / 1500.0f) * 5.0f);
    drawEyesBase(40, 88, peekY, 22, 16, lookX);
    if (peekY > 40)
      u8g2.drawHLine(0, peekY - 10, 128);
  }
}

// ─── Animation 14: Heart Bubbles ────────────────────────────────────
void drawIdle_HeartBubbles(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 2.0f);

  // Normal happy eyes
  drawEyesBase(40, 88, 27 + bob, 22, 18, 0);

  // Cute smile
  int smileY = 44 + bob;
  for (int dx = -10; dx <= 10; dx++) {
    int y = smileY + (int)(dx * dx * 0.04f);
    u8g2.drawPixel(64 + dx, y);
    u8g2.drawPixel(64 + dx, y + 1);
  }

  // Floating heart particles
  for (int i = 0; i < 5; i++) {
    float hP = fmodf(t / 2000.0f + i * 0.2f, 1.0f);
    int hx = 15 + i * 24 + (int)(sinf(hP * 6.283f + i) * 6.0f);
    int hy = 55 - (int)(hP * 50.0f);
    if (hy > 2 && hy < 60 && hP < 0.85f) {
      u8g2.drawPixel(hx - 1, hy);
      u8g2.drawPixel(hx + 1, hy);
      u8g2.drawPixel(hx - 2, hy - 1);
      u8g2.drawPixel(hx, hy - 1);
      u8g2.drawPixel(hx + 2, hy - 1);
      u8g2.drawPixel(hx, hy + 1);
    }
  }
}

// ─── Animation 15: Robot Scan ───────────────────────────────────────
void drawIdle_RobotScan(uint32_t t) {
  u8g2.setDrawColor(1);

  // Rectangular eye frames
  u8g2.drawFrame(26, 14, 30, 26);
  u8g2.drawFrame(72, 14, 30, 26);

  // Sweeping scan line
  float scanP = fmodf(t / 1500.0f, 1.0f);
  int scanY;
  if (scanP < 0.5f) scanY = 16 + (int)(scanP * 2.0f * 20.0f);
  else scanY = 36 - (int)((scanP - 0.5f) * 2.0f * 20.0f);
  scanY = clampi(scanY, 16, 36);

  u8g2.drawHLine(28, scanY, 26);
  u8g2.drawHLine(28, scanY + 1, 26);
  u8g2.drawHLine(74, scanY, 26);
  u8g2.drawHLine(74, scanY + 1, 26);

  // Blinking antenna
  float antP = sinf(t / 300.0f);
  if (antP > 0) u8g2.drawDisc(64, 5, 2);
  else u8g2.drawCircle(64, 5, 2);
  u8g2.drawVLine(64, 7, 5);

  // Mechanical mouth
  u8g2.drawHLine(52, 48, 24);
  u8g2.drawVLine(52, 48, 4);
  u8g2.drawVLine(76, 48, 4);
  u8g2.drawHLine(52, 52, 24);
  u8g2.drawVLine(58, 48, 4);
  u8g2.drawVLine(64, 48, 4);
  u8g2.drawVLine(70, 48, 4);

  u8g2.setFont(u8g2_font_4x6_tr);
  u8g2.drawStr(38, 62, "SCANNING...");
}

// ─── Animation 16: Pixel Dance ──────────────────────────────────────
void drawIdle_PixelDance(uint32_t t) {
  u8g2.setDrawColor(1);
  int frame = (t / 300) % 4;
  int cx = 64;
  int cy = 32;

  // Head
  u8g2.drawBox(cx - 3, cy - 12, 6, 6);
  u8g2.setDrawColor(0);
  u8g2.drawPixel(cx - 2, cy - 10);
  u8g2.drawPixel(cx + 1, cy - 10);
  u8g2.setDrawColor(1);

  // Body
  u8g2.drawBox(cx - 3, cy - 5, 6, 7);

  // 4-frame dance cycle
  switch (frame) {
    case 0:
      u8g2.drawBox(cx - 4, cy + 2, 3, 8);
      u8g2.drawBox(cx + 1, cy + 2, 3, 8);
      u8g2.drawLine(cx - 3, cy - 3, cx - 8, cy - 6);
      u8g2.drawLine(cx + 2, cy - 3, cx + 7, cy);
      break;
    case 1:
      u8g2.drawLine(cx - 2, cy + 2, cx - 6, cy + 10);
      u8g2.drawBox(cx + 1, cy + 2, 3, 8);
      u8g2.drawLine(cx - 3, cy - 3, cx - 8, cy);
      u8g2.drawLine(cx + 2, cy - 3, cx + 7, cy - 6);
      break;
    case 2:
      u8g2.drawBox(cx - 4, cy + 2, 3, 8);
      u8g2.drawBox(cx + 1, cy + 2, 3, 8);
      u8g2.drawLine(cx - 3, cy - 3, cx - 8, cy);
      u8g2.drawLine(cx + 2, cy - 3, cx + 7, cy);
      break;
    case 3:
      u8g2.drawBox(cx - 4, cy + 2, 3, 8);
      u8g2.drawLine(cx + 2, cy + 2, cx + 6, cy + 10);
      u8g2.drawLine(cx - 3, cy - 3, cx - 8, cy - 6);
      u8g2.drawLine(cx + 2, cy - 3, cx + 7, cy - 6);
      break;
  }

  // Bouncing music symbols
  float noteP = fmodf(t / 800.0f, 1.0f);
  int ny = 10 - (int)(noteP * 8.0f);
  u8g2.setFont(u8g2_font_5x7_tr);
  if (noteP < 0.7f) {
    u8g2.drawStr(80, ny + 10, "~");
    u8g2.drawStr(20, ny + 14, "~");
  }

  u8g2.setFont(u8g2_font_4x6_tr);
  u8g2.drawStr(40, 62, "groove~");
}

// ─── Animation 17: Dreamy ───────────────────────────────────────────
void drawIdle_Dreamy(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 1200.0f);
  int bob = (int)(breath * 1.0f);

  // Half-lidded dreamy eyes
  drawEyesBase(40, 88, 30 + bob, 22, 10, 0);
  u8g2.setDrawColor(0);
  u8g2.drawBox(29, 20 + bob, 24, 8);
  u8g2.drawBox(77, 20 + bob, 24, 8);
  u8g2.setDrawColor(1);
  u8g2.drawHLine(29, 28 + bob, 24);
  u8g2.drawHLine(77, 28 + bob, 24);

  // Gentle smile
  int smileY = 46 + bob;
  for (int dx = -8; dx <= 8; dx++) {
    int y = smileY + (int)(dx * dx * 0.03f);
    u8g2.drawPixel(64 + dx, y);
  }

  // Thought bubble cloud (top-right)
  float cloudBob = sinf(t / 900.0f) * 2.0f;
  int cby = 10 + (int)cloudBob;
  u8g2.drawDisc(104, cby, 5);
  u8g2.drawDisc(110, cby - 2, 4);
  u8g2.drawDisc(116, cby, 3);
  u8g2.drawDisc(96, cby + 8, 2);
  u8g2.drawPixel(92, cby + 12);

  // Star inside cloud
  u8g2.setDrawColor(0);
  u8g2.drawPixel(107, cby - 1);
  u8g2.drawPixel(106, cby);
  u8g2.drawPixel(108, cby);
  u8g2.drawPixel(107, cby + 1);
  u8g2.setDrawColor(1);
}

// ─── Animation 18: Excited Shake ────────────────────────────────────
void drawIdle_ExcitedShake(uint32_t t) {
  u8g2.setDrawColor(1);
  int shakeX = (int)(sinf(t / 30.0f) * 2.0f);
  int shakeY = (int)(cosf(t / 25.0f) * 1.5f);

  // Wide excited eyes
  drawEyesBase(40 + shakeX, 88 + shakeX, 24 + shakeY, 26, 22, 0);

  // Big grin
  int smileY = 44 + shakeY;
  u8g2.drawCircle(64 + shakeX, smileY - 2, 14,
                  U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);
  u8g2.drawCircle(64 + shakeX, smileY - 2, 13,
                  U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);

  // Bouncing exclamation marks
  float exP = fmodf(t / 500.0f, 1.0f);
  int exBounce = (int)(fabsf(sinf(exP * 3.14f)) * 3.0f);
  u8g2.setFont(u8g2_font_6x12_tr);
  u8g2.drawStr(6, 16 - exBounce, "!");
  u8g2.drawStr(116, 14 - exBounce, "!");
  u8g2.drawStr(12, 20, "!");
  u8g2.drawStr(110, 18, "!");
}

// ─── Animation 19: Tongue Out ───────────────────────────────────────
void drawIdle_TongueOut(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 700.0f);
  int bob = (int)(breath * 2.0f);

  // Playful eyes (slightly asymmetric)
  drawRoundedEye(40, 27 + bob, 22, 18);
  drawRoundedEye(88, 27 + bob, 20, 16);

  // Smile with gap for tongue
  int smileY = 42 + bob;
  for (int dx = -12; dx <= 12; dx++) {
    if (abs(dx) > 3) {
      int y = smileY + (int)(dx * dx * 0.04f);
      u8g2.drawPixel(64 + dx, y);
      u8g2.drawPixel(64 + dx, y + 1);
    }
  }

  // Wiggling tongue
  float tongueW = sinf(t / 200.0f) * 3.0f;
  int tx = 64 + (int)tongueW;
  int ty = smileY + 2;
  u8g2.drawDisc(tx, ty + 5, 5);
  u8g2.drawBox(tx - 4, ty, 8, 5);
  u8g2.setDrawColor(0);
  u8g2.drawDisc(tx, ty + 4, 3);
  u8g2.drawBox(tx - 2, ty, 4, 3);
  u8g2.setDrawColor(1);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(48, 62, "bleh~");
}

// ─── Animation 20: Snoring ─────────────────────────────────────────
void drawIdle_Snoring(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 2000.0f);
  int bob = (int)(breath * 1.5f);

  // Closed sleep eyes
  drawClosedSleepEyes(40, 88, 28 + bob, 0);

  // Tiny relaxed smile
  int smileY = 46 + bob;
  for (int dx = -6; dx <= 6; dx++) {
    int y = smileY + (int)(dx * dx * 0.02f);
    u8g2.drawPixel(64 + dx, y);
  }

  // Expanding/contracting snore bubble
  float bubbleP = fmodf(t / 1800.0f, 1.0f);
  float bubbleSize;
  if (bubbleP < 0.6f) bubbleSize = easeInOut(bubbleP / 0.6f);
  else bubbleSize = 1.0f - easeInOut((bubbleP - 0.6f) / 0.4f);
  int bx = 74, by = 42 + bob;
  int br = 3 + (int)(bubbleSize * 8.0f);
  u8g2.drawCircle(bx + br / 2, by - br / 2, br);

  if (bubbleSize > 0.3f) {
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(bx + br, by - br - 4, "z");
  }

  // Cheek blush
  u8g2.drawPixel(26, 38 + bob);
  u8g2.drawPixel(27, 39 + bob);
  u8g2.drawPixel(100, 38 + bob);
  u8g2.drawPixel(101, 39 + bob);
}

// ═══════════════════════════════════════════════════════════════════════════
// Idle Animation Dispatch + Cycling Logic
// ═══════════════════════════════════════════════════════════════════════════

void drawIdleAnimByIndex(int idx, uint32_t t) {
  switch (idx) {
    case 0:  drawIdleFace(t); break;
    case 1:  drawIdle_Curious(t); break;
    case 2:  drawIdle_Winking(t); break;
    case 3:  drawIdle_Stargazing(t); break;
    case 4:  drawIdle_Bouncy(t); break;
    case 5:  drawIdle_SleepyBlink(t); break;
    case 6:  drawIdle_CatFace(t); break;
    case 7:  drawIdle_SparkleEyes(t); break;
    case 8:  drawIdle_Confused(t); break;
    case 9:  drawIdle_Whistling(t); break;
    case 10: drawIdle_Nervous(t); break;
    case 11: drawIdle_CoolShades(t); break;
    case 12: drawIdle_Chewing(t); break;
    case 13: drawIdle_Peeking(t); break;
    case 14: drawIdle_HeartBubbles(t); break;
    case 15: drawIdle_RobotScan(t); break;
    case 16: drawIdle_PixelDance(t); break;
    case 17: drawIdle_Dreamy(t); break;
    case 18: drawIdle_ExcitedShake(t); break;
    case 19: drawIdle_TongueOut(t); break;
    case 20: drawIdle_Snoring(t); break;
    default: drawIdleFace(t); break;
  }
}

int pickNextIdleAnim() {
  bool night = isNightTime();

  if (night) {
    // Night: pick from calm pool only
    int pick = NIGHT_SAFE_ANIMS[esp_random() % NIGHT_SAFE_COUNT];
    if (pick == currentIdleAnim && NIGHT_SAFE_COUNT > 1) {
      pick = NIGHT_SAFE_ANIMS[(esp_random() % (NIGHT_SAFE_COUNT - 1) + 1) % NIGHT_SAFE_COUNT];
    }
    return pick;
  }

  // Daytime: weighted random selection
  int totalWeight = 0;
  for (int i = 0; i < IDLE_ANIM_COUNT; i++) totalWeight += IDLE_ANIM_WEIGHTS[i];

  int roll = esp_random() % totalWeight;
  int cumulative = 0;
  for (int i = 0; i < IDLE_ANIM_COUNT; i++) {
    cumulative += IDLE_ANIM_WEIGHTS[i];
    if (roll < cumulative) {
      // Don't repeat the same animation twice in a row
      if (i == currentIdleAnim && IDLE_ANIM_COUNT > 1) {
        return (i + 1 + (esp_random() % (IDLE_ANIM_COUNT - 1))) % IDLE_ANIM_COUNT;
      }
      return i;
    }
  }
  return 0;
}

// Master idle animation wrapper with blink-wipe transitions
void drawIdleAnimation(uint32_t now) {
  // A paused idle mode still renders the calm, breathing face; it never
  // leaves a frozen frame on the OLED.
  if (!idleAnimationsEnabled) {
    drawIdleFace(now);
    drawIdleOverlays();
    return;
  }

  // Check if time to cycle
  if (!idleTransitioning && now - idleAnimStartedAt >= idleAnimDuration) {
    idleTransitioning = true;
    idleTransitionStartAt = now;
    nextIdleAnim = pickNextIdleAnim();
  }

  // During transition: horizontal-bar wipe (eyelid close/open effect)
  if (idleTransitioning) {
    uint32_t tp = now - idleTransitionStartAt;
    if (tp < IDLE_TRANSITION_MS) {
      float p = tp / (float)IDLE_TRANSITION_MS;
      if (p < 0.5f) {
        // Phase 1: closing — draw current anim, overlay closing bars
        drawIdleAnimByIndex(currentIdleAnim, now);
        float close = easeInOut(p * 2.0f);
        int barH = (int)(32.0f * close);
        u8g2.setDrawColor(0);
        u8g2.drawBox(0, 0, 128, barH);
        u8g2.drawBox(0, 64 - barH, 128, barH);
        u8g2.setDrawColor(1);
      } else {
        // Phase 2: opening — switch to new anim, overlay opening bars
        if (currentIdleAnim != nextIdleAnim) {
          currentIdleAnim = nextIdleAnim;
          idleAnimStartedAt = now;
        }
        drawIdleAnimByIndex(currentIdleAnim, now);
        float open = easeInOut((1.0f - p) * 2.0f);
        int barH = (int)(32.0f * open);
        u8g2.setDrawColor(0);
        u8g2.drawBox(0, 0, 128, barH);
        u8g2.drawBox(0, 64 - barH, 128, barH);
        u8g2.setDrawColor(1);
      }
    } else {
      // Transition complete
      idleTransitioning = false;
      currentIdleAnim = nextIdleAnim;
      idleAnimStartedAt = now;
      idleAnimDuration = 5000 + (esp_random() % 5001); // 5–10 seconds
      drawIdleAnimByIndex(currentIdleAnim, now);
    }
  } else {
    // Normal: draw current animation
    drawIdleAnimByIndex(currentIdleAnim, now);
  }

  // Apply display mode overlays on top of any animation
  drawIdleOverlays();
}

void drawTickledFace(uint32_t t) {
  u8g2.setDrawColor(1);
  // Continuous happy bounce (not stepped)
  float bounceF = fabsf(sinf(t / 95.0f));
  int bounce = (int)(bounceF * 5.0f);
  int cy = 26 - bounce;
  int wobble = (int)(sinf(t / 70.0f) * 2.0f);

  // Thick arc eyes ^ ^
  for (int i = 0; i < 4; i++) {
    u8g2.drawCircle(40 + wobble, cy + 5, 11 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawCircle(88 - wobble, cy + 5, 11 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
  }

  // Big smile arcs
  u8g2.drawCircle(64, 40 + bounce / 2, 14, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);
  u8g2.drawCircle(64, 40 + bounce / 2, 13, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);

  // Small sparkle marks (cleaner than orbiting dots on 0.96" OLED)
  // Top-left sparkle
  u8g2.drawPixel(12, 14);
  u8g2.drawPixel(11, 15);
  u8g2.drawPixel(13, 15);
  u8g2.drawPixel(12, 16);
  // Top-right sparkle
  u8g2.drawPixel(116, 14);
  u8g2.drawPixel(115, 15);
  u8g2.drawPixel(117, 15);
  u8g2.drawPixel(116, 16);

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(40, 62, "hehe~");
}

void drawDizzyFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float a = t / 70.0f;
  int shakeX = (int)(sinf(a * 2.1f) * 5.0f);  // stronger shake
  int shakeY = (int)(cosf(a * 1.6f) * 4.0f);

  // Continuous spiral eyes (polyline)
  for (int e = 0; e < 2; e++) {
    int cx = (e == 0 ? 40 : 88) + shakeX;
    int cy = 28 + shakeY;
    int prevX = cx, prevY = cy;
    for (int i = 1; i <= 28; i++) {
      float r = i * 0.4f;
      float ang = a * (e == 0 ? 1.0f : -1.0f) + i * 0.45f;
      int px = cx + (int)(cosf(ang) * r);
      int py = cy + (int)(sinf(ang) * r);
      u8g2.drawLine(prevX, prevY, px, py);
      prevX = px;
      prevY = py;
    }
  }

  // Smooth wavy mouth
  int prevMx = 46 + shakeX;
  int prevMy = 46 + shakeY;
  for (int x = 47; x <= 82; x++) {
    int y = 46 + (int)(sinf((x + t / 18.0f) * 0.35f) * 3.5f) + shakeY;
    u8g2.drawLine(prevMx, prevMy, x + shakeX, y);
    prevMx = x + shakeX;
    prevMy = y;
  }

  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(38, 62, "wooozy");
}

void drawYawnFace(uint32_t t) {
  float p = clampf(t / (float)YAWN_MS, 0.0f, 1.0f);
  float breath = sinf(t / 850.0f);
  int bob = (int)(breath * 1.2f);
  int cy = 27 + bob;

  // Eyes: open → heavy squint → nearly shut as sleep approaches
  float eyeOpen;
  if (p < 0.22f) {
    eyeOpen = 1.0f - easeInOut(p / 0.22f) * 0.55f;
  } else if (p < 0.58f) {
    eyeOpen = 0.45f - easeInOut((p - 0.22f) / 0.36f) * 0.38f;
  } else {
    eyeOpen = 0.07f - easeInOut((p - 0.58f) / 0.42f) * 0.06f;
  }
  int eyeH = clampi((int)(18.0f * eyeOpen), 2, 18);
  drawEyesBase(40, 88, cy, 22, eyeH, 0);

  // Wide O-mouth yawn — grows to peak then relaxes
  float mouthGrow;
  if (p < 0.48f) {
    mouthGrow = easeInOut(p / 0.48f);
  } else {
    mouthGrow = easeInOut(1.0f - (p - 0.48f) / 0.52f);
  }
  int mouthRx = 5 + (int)(mouthGrow * 15.0f);
  int mouthRy = 2 + (int)(mouthGrow * 11.0f);
  int mouthY = 47 + bob;
  u8g2.drawEllipse(64, mouthY, mouthRx, mouthRy, U8G2_DRAW_ALL);
  if (mouthGrow > 0.35f) {
    // Inner mouth depth
    u8g2.drawEllipse(64, mouthY + 1, mouthRx - 3, mouthRy - 4, U8G2_DRAW_ALL);
  }

  // Raised eyebrows / forehead tension during peak yawn
  if (p > 0.25f && p < 0.72f) {
    float brow = sinf((p - 0.25f) / 0.47f * 3.14159f);
    int lift = (int)(brow * 3.0f);
    u8g2.drawHLine(32, 14 - lift, 8);
    u8g2.drawHLine(88, 14 - lift, 8);
  }

  // Little "ahh~" at peak
  if (p > 0.35f && p < 0.75f) {
    u8g2.setFont(u8g2_font_5x7_tr);
    u8g2.drawStr(52, 62, "ahh~");
  }

  drawNightMoon(116, 9);
}

void drawSleepFace(uint32_t t) {
  // Slow peaceful breathing while asleep
  float breath = sinf(t / 2400.0f);
  int bob = (int)(breath * 2.0f);
  int cy = 28 + bob;
  int lookX = (int)(sinf(t / 5000.0f) * 1.0f);

  drawClosedSleepEyes(40, 88, cy, lookX);

  // Tiny relaxed smile
  int smileY = 49 + bob;
  for (int dx = -7; dx <= 7; dx++) {
    int y = smileY + (int)(dx * dx * 0.025f);
    u8g2.drawPixel(64 + dx, y);
  }

  // Cheek blush dots (sleepy warmth)
  u8g2.drawPixel(26, 38 + bob);
  u8g2.drawPixel(27, 39 + bob);
  u8g2.drawPixel(100, 38 + bob);
  u8g2.drawPixel(101, 39 + bob);

  drawFloatingZzz(t, 64, 22 + bob);
  drawNightMoon(116, 9);

  // Dim time stamp — still visible but unobtrusive
  if (timeSynced) {
    char clockBuf[8];
    formatLocalTime(clockBuf, sizeof(clockBuf));
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(2, 62, clockBuf);
  } else {
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(36, 62, "shhh...");
  }
}

void drawBootScreen(uint32_t elapsed) {
  u8g2.setDrawColor(1);
  float p = clampf(elapsed / (float)BOOT_MS, 0.0f, 1.0f);
  float e = easeInOut(p);

  u8g2.setFont(u8g2_font_logisoso22_tr);
  const char* text = "BLINK";
  int tw = u8g2.getStrWidth(text);
  int x = (OLED_W - tw) / 2;
  int y = 20 + (int)(18.0f * e);  // rise into place

  if (p < 0.18f) {
    // Expanding pulse dots
    float q = easeInOut(p / 0.18f);
    int r = 1 + (int)(q * 3);
    for (int i = 0; i < 5; i++) {
      int dx = 44 + i * 9;
      u8g2.drawDisc(dx, 32, r);
    }
  } else {
    u8g2.drawStr(x, y, text);
    int lineW = (int)(tw * easeInOut((p - 0.18f) / 0.55f));
    u8g2.drawHLine(x, y + 5, clampi(lineW, 0, tw));
    // Soft glow bar under text near end
    if (p > 0.75f) {
      int glow = (int)((p - 0.75f) / 0.25f * tw);
      u8g2.drawHLine(x, y + 7, glow);
    }
  }
}

void drawMenuScreen() {
  u8g2.setFont(u8g2_font_6x12_tr);
  u8g2.drawStr(4, 11, "BLINK MENU");
  u8g2.drawHLine(0, 14, OLED_W);

  u8g2.setFont(u8g2_font_5x7_tr);
  for (int i = 0; i < 4; i++) {
    int idx = menuIndex - 1 + i;
    if (idx < 0) idx += MENU_COUNT;
    idx %= MENU_COUNT;
    int y = 26 + i * 12;
    if (i == 1) {
      u8g2.drawBox(0, y - 8, OLED_W, 10);
      u8g2.setDrawColor(0);
      u8g2.drawStr(10, y, MENU_ITEMS[idx]);
      u8g2.setDrawColor(1);
    } else {
      u8g2.drawStr(10, y, MENU_ITEMS[idx]);
    }
  }

  u8g2.setFont(u8g2_font_4x6_tr);
  u8g2.drawStr(2, 62, "tap:next 2x:back 3x:open");
}

void applyMenuSelection() {
  menuOpen = false;
  switch (menuIndex) {
    case 0:  // Focus Mode
      focusActive = true;
      drawMode = false;
      displayMode = DISPLAY_FOCUS;
      if (stopwatchText[0] == '\0') {
        strncpy(stopwatchText, "25:00", sizeof(stopwatchText));
        stopwatchText[sizeof(stopwatchText) - 1] = '\0';
      }
      enterState(STATE_APP_MODE);
      break;
    case 1:  // Mario Clock
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_MARIO_CLOCK;
      mclockState = MCLOCK_IDLE;
      mclock_x = MCLOCK_START_X;
      mclock_jumpY = 0;
      mclock_jumpVel = 0;
      mclock_lastMin = -1;
      mclock_animTriggered = false;
      for (int i = 0; i < 5; i++) {
        mclock_digitOffY[i] = 0;
        mclock_digitVelY[i] = 0;
      }
      enterState(STATE_APP_MODE);
      break;
    case 2:  // BLE Status
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_BLE;
      enterState(STATE_APP_MODE);
      break;
    case 3:  // HW Info
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_HW_INFO;
      enterState(STATE_APP_MODE);
      break;
    case 4:  // Sound Test
      playCustomSound(SOUND_CUSTOM, sizeof(SOUND_CUSTOM) / sizeof(SOUND_CUSTOM[0]));
      displayMode = DISPLAY_NORMAL;
      enterState(STATE_IDLE);
      break;
    case 5:  // Go Back
      // Close the menu without changing the screen currently in use.
      menuOpen = false;
      break;
    default:
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_NORMAL;
      stopwatchText[0] = '\0';
      enterState(STATE_IDLE);
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mario Clock — sprite drawing, animation, & screen render
// Adapted from SmallOLED-PCMonitor clock_mario.cpp (Adafruit → U8g2)
// ═══════════════════════════════════════════════════════════════════════════

void drawMarioSprite(int x, int y, bool facingRight, int frame, bool jumping) {
  if (x < -10 || x > OLED_W + 10) return;
  int sx = x - 4;
  int sy = y - 10;
  u8g2.setDrawColor(1);

  if (jumping) {
    // Head (hat)
    u8g2.drawBox(sx + 2, sy, 4, 3);
    // Body
    u8g2.drawBox(sx + 2, sy + 3, 4, 3);
    // Arms out
    u8g2.drawPixel(sx + 1, sy + 2);
    u8g2.drawPixel(sx + 6, sy + 2);
    u8g2.drawPixel(sx + 0, sy + 1);
    u8g2.drawPixel(sx + 7, sy + 1);
    // Legs together
    u8g2.drawBox(sx + 2, sy + 6, 2, 3);
    u8g2.drawBox(sx + 4, sy + 6, 2, 3);
  } else {
    // Head (hat)
    u8g2.drawBox(sx + 2, sy, 4, 3);
    // Cap brim
    if (facingRight) {
      u8g2.drawPixel(sx + 6, sy + 1);
    } else {
      u8g2.drawPixel(sx + 1, sy + 1);
    }
    // Body
    u8g2.drawBox(sx + 2, sy + 3, 4, 3);
    // Arms: back arm static, front arm bobs
    if (facingRight) {
      u8g2.drawPixel(sx + 1, sy + 4);
      u8g2.drawPixel(sx + 6, sy + 3 + (frame % 2));
    } else {
      u8g2.drawPixel(sx + 6, sy + 4);
      u8g2.drawPixel(sx + 1, sy + 3 + (frame % 2));
    }
    // 2-frame walk cycle
    if (frame % 2 == 0) {
      u8g2.drawBox(sx + 2, sy + 6, 2, 3);
      u8g2.drawBox(sx + 4, sy + 6, 2, 3);
    } else {
      u8g2.drawBox(sx + 1, sy + 6, 2, 3);
      u8g2.drawBox(sx + 5, sy + 6, 2, 3);
    }
  }
}

// Get displayed digit value from mclock_dispHour / mclock_dispMin
uint8_t mclockGetDigit(uint8_t idx) {
  switch (idx) {
    case 0: return mclock_dispHour / 10;
    case 1: return mclock_dispHour % 10;
    case 3: return mclock_dispMin / 10;
    case 4: return mclock_dispMin % 10;
    default: return 0;
  }
}

// Set a single displayed digit
void mclockSetDigit(uint8_t idx, uint8_t val) {
  switch (idx) {
    case 0: mclock_dispHour = val * 10 + (mclock_dispHour % 10); break;
    case 1: mclock_dispHour = (mclock_dispHour / 10) * 10 + val; break;
    case 3: mclock_dispMin = val * 10 + (mclock_dispMin % 10); break;
    case 4: mclock_dispMin = (mclock_dispMin / 10) * 10 + val; break;
  }
}

// Trigger a digit bounce (upward pop when Mario bumps it)
void mclockTriggerBounce(int idx) {
  if (idx >= 0 && idx < 5) {
    mclock_digitVelY[idx] = -4.0f;
  }
}

// Update digit bounce physics
void mclockUpdateBounce() {
  for (int i = 0; i < 5; i++) {
    if (mclock_digitOffY[i] != 0 || mclock_digitVelY[i] != 0) {
      mclock_digitVelY[i] += 0.6f;
      mclock_digitOffY[i] += mclock_digitVelY[i];
      if (mclock_digitOffY[i] >= 0) {
        mclock_digitOffY[i] = 0;
        mclock_digitVelY[i] = 0;
      }
    }
  }
}

// Calculate which digits change at the next minute, build target list
void mclockCalcTargets() {
  int nextHour = mclock_dispHour;
  int nextMin = mclock_dispMin + 1;
  if (nextMin >= 60) {
    nextMin = 0;
    nextHour = (nextHour + 1) % 24;
  }

  mclock_numTargets = 0;
  // Hour tens
  if ((mclock_dispHour / 10) != (nextHour / 10)) {
    mclock_targetX[mclock_numTargets] = MCLOCK_DIGIT_X[0] + 7;
    mclock_targetDigitIdx[mclock_numTargets] = 0;
    mclock_targetDigitVal[mclock_numTargets] = nextHour / 10;
    mclock_numTargets++;
  }
  // Hour ones
  if ((mclock_dispHour % 10) != (nextHour % 10)) {
    mclock_targetX[mclock_numTargets] = MCLOCK_DIGIT_X[1] + 7;
    mclock_targetDigitIdx[mclock_numTargets] = 1;
    mclock_targetDigitVal[mclock_numTargets] = nextHour % 10;
    mclock_numTargets++;
  }
  // Minute tens
  if ((mclock_dispMin / 10) != (nextMin / 10)) {
    mclock_targetX[mclock_numTargets] = MCLOCK_DIGIT_X[3] + 7;
    mclock_targetDigitIdx[mclock_numTargets] = 3;
    mclock_targetDigitVal[mclock_numTargets] = nextMin / 10;
    mclock_numTargets++;
  }
  // Minute ones
  if ((mclock_dispMin % 10) != (nextMin % 10)) {
    mclock_targetX[mclock_numTargets] = MCLOCK_DIGIT_X[4] + 7;
    mclock_targetDigitIdx[mclock_numTargets] = 4;
    mclock_targetDigitVal[mclock_numTargets] = nextMin % 10;
    mclock_numTargets++;
  }
}

// Main Mario animation state machine update
void mclockUpdateAnimation() {
  uint32_t now = millis();
  if (now - mclock_lastUpdate < MCLOCK_ANIM_MS) return;
  mclock_lastUpdate = now;

  // Get current real time
  if (!timeSynced) return;
  time_t rawNow = time(nullptr);
  struct tm t;
  localtime_r(&rawNow, &t);
  int seconds = t.tm_sec;
  int curMin = t.tm_min;

  // Detect minute change
  if (curMin != mclock_lastMin) {
    mclock_lastMin = curMin;
    mclock_animTriggered = false;
  }

  // Trigger animation at second 56 (gives Mario time to walk + jump before :00)
  if (seconds >= 56 && !mclock_animTriggered && mclockState == MCLOCK_IDLE) {
    mclock_animTriggered = true;
    mclockCalcTargets();
    if (mclock_numTargets > 0) {
      mclock_curTarget = 0;
      mclock_x = MCLOCK_START_X;
      mclockState = MCLOCK_WALKING;
      mclock_facingRight = true;
      mclock_digitBounceTriggered = false;
    }
  }

  switch (mclockState) {
    case MCLOCK_IDLE:
      mclock_walkFrame = 0;
      mclock_x = MCLOCK_START_X;
      break;

    case MCLOCK_WALKING:
      if (mclock_curTarget < mclock_numTargets) {
        int tgtX = mclock_targetX[mclock_curTarget];
        if (abs(mclock_x - tgtX) > 3) {
          float spd = 2.0f;
          if (mclock_x < tgtX) {
            mclock_x += spd;
            mclock_facingRight = true;
          } else {
            mclock_x -= spd;
            mclock_facingRight = false;
          }
          mclock_walkFrame = (mclock_walkFrame + 1) % 2;
        } else {
          mclock_x = tgtX;
          mclockState = MCLOCK_JUMPING;
          mclock_jumpVel = MCLOCK_JUMP_POWER;
          mclock_jumpY = 0;
          mclock_digitBounceTriggered = false;
        }
      } else {
        mclockState = MCLOCK_WALKING_OFF;
        mclock_facingRight = true;
      }
      break;

    case MCLOCK_JUMPING: {
      mclock_jumpVel += MCLOCK_GRAVITY;
      mclock_jumpY += mclock_jumpVel;

      int headY = mclock_baseY + (int)mclock_jumpY - MCLOCK_HEAD_OFFSET;
      if (!mclock_digitBounceTriggered && headY <= MCLOCK_DIGIT_BOTTOM) {
        mclock_digitBounceTriggered = true;
        int di = mclock_targetDigitIdx[mclock_curTarget];
        mclockTriggerBounce(di);
        mclockSetDigit(di, mclock_targetDigitVal[mclock_curTarget]);
        mclock_jumpVel = MCLOCK_BOUNCE_VEL;
      }

      if (mclock_jumpY >= 0) {
        mclock_jumpY = 0;
        mclock_jumpVel = 0;
        mclock_curTarget++;
        if (mclock_curTarget < mclock_numTargets) {
          mclockState = MCLOCK_WALKING;
          mclock_facingRight = (mclock_targetX[mclock_curTarget] > mclock_x);
          mclock_digitBounceTriggered = false;
        } else {
          mclockState = MCLOCK_WALKING_OFF;
          mclock_facingRight = true;
        }
      }
      break;
    }

    case MCLOCK_WALKING_OFF:
      mclock_x += 2.0f;
      mclock_walkFrame = (mclock_walkFrame + 1) % 2;
      if (mclock_x > OLED_W + 15) {
        mclockState = MCLOCK_IDLE;
        mclock_x = MCLOCK_START_X;
      }
      break;
  }
}

// Draw the full Mario Clock screen
void drawMarioClockScreen() {
  u8g2.setDrawColor(1);

  if (!timeSynced) {
    u8g2.setFont(u8g2_font_6x12_tr);
    u8g2.drawStr(18, 36, "sync via app");
    return;
  }

  // Sync displayed time from RTC (only when not in animation)
  time_t rawNow = time(nullptr);
  struct tm t;
  localtime_r(&rawNow, &t);
  if (mclockState == MCLOCK_IDLE) {
    mclock_dispHour = t.tm_hour;
    mclock_dispMin = t.tm_min;
  }

  // Date at top
  u8g2.setFont(u8g2_font_5x7_tr);
  char dateStr[12];
  snprintf(dateStr, sizeof(dateStr), "%02d/%02d/%04d", t.tm_mday, t.tm_mon + 1, t.tm_year + 1900);
  int dateW = u8g2.getStrWidth(dateStr);
  u8g2.drawStr((OLED_W - dateW) / 2, 10, dateStr);

  // Update animation & bounce physics
  mclockUpdateAnimation();
  mclockUpdateBounce();

  // Draw time digits using large font, with per-digit bounce offset
  u8g2.setFont(u8g2_font_logisoso22_tr);
  char digits[6];
  digits[0] = '0' + (mclock_dispHour / 10);
  digits[1] = '0' + (mclock_dispHour % 10);
  // Blinking colon
  digits[2] = ((millis() / 500) % 2 == 0) ? ':' : ' ';
  digits[3] = '0' + (mclock_dispMin / 10);
  digits[4] = '0' + (mclock_dispMin % 10);
  digits[5] = '\0';

  // Draw each digit individually for per-digit bounce
  char singleChar[2] = {0, 0};
  for (int i = 0; i < 5; i++) {
    singleChar[0] = digits[i];
    int dy = MCLOCK_TIME_Y + (int)mclock_digitOffY[i];
    u8g2.drawStr(MCLOCK_DIGIT_X[i], dy, singleChar);
  }

  // Draw Mario sprite
  int marioDrawY = mclock_baseY + (int)mclock_jumpY;
  bool isJumping = (mclockState == MCLOCK_JUMPING);
  drawMarioSprite((int)mclock_x, marioDrawY, mclock_facingRight, mclock_walkFrame, isJumping);

  // Ground line (subtle)
  u8g2.drawHLine(0, 63, OLED_W);

  // "hold to exit" hint (small, bottom-left, fades after 5 sec)
  uint32_t elapsed = millis() - stateEnteredAt;
  if (elapsed < 5000) {
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(2, 7, "hold 2s=exit");
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HW Info Screen — ESP32 internal stats with progress bars
// ═══════════════════════════════════════════════════════════════════════════

void drawHwInfoBar(int x, int y, int barW, int barH, int pct) {
  pct = clampi(pct, 0, 100);
  int fillW = (barW * pct) / 100;
  // Filled portion
  if (fillW > 0) {
    u8g2.drawBox(x, y, fillW, barH);
  }
  // Empty portion (outline dots for visual texture)
  for (int px = x + fillW; px < x + barW; px += 2) {
    u8g2.drawPixel(px, y + barH / 2);
  }
  // Bar border
  u8g2.drawFrame(x, y, barW, barH);
}

void drawHwInfoScreen() {
  u8g2.setDrawColor(1);

  // Header: "BLINK" + uptime + time
  u8g2.setFont(u8g2_font_6x12_tr);
  u8g2.drawStr(2, 11, "BLINK");

  // Uptime in seconds
  uint32_t uptimeSec = millis() / 1000;
  uint32_t uptimeMin = uptimeSec / 60;
  uint32_t uptimeHr = uptimeMin / 60;
  char uptBuf[12];
  if (uptimeHr > 0) {
    snprintf(uptBuf, sizeof(uptBuf), "%luh%02lum", (unsigned long)uptimeHr, (unsigned long)(uptimeMin % 60));
  } else {
    snprintf(uptBuf, sizeof(uptBuf), "%lum%02lus", (unsigned long)uptimeMin, (unsigned long)(uptimeSec % 60));
  }
  u8g2.setFont(u8g2_font_5x7_tr);
  u8g2.drawStr(40, 10, uptBuf);

  // Time (top-right)
  if (timeSynced) {
    char clockBuf[8];
    formatLocalTime(clockBuf, sizeof(clockBuf));
    int tw = u8g2.getStrWidth(clockBuf);
    u8g2.drawStr(OLED_W - tw - 2, 10, clockBuf);
  }

  // Separator
  u8g2.drawHLine(0, 13, OLED_W);

  // Calculate stats
  uint32_t totalHeap = ESP.getHeapSize();
  uint32_t freeHeap = ESP.getFreeHeap();
  int ramPct = (totalHeap > 0) ? (int)(((totalHeap - freeHeap) * 100) / totalHeap) : 0;

  // CPU: simple load heuristic (how much of each second we spend in loop)
  // Use a smoothed fake value based on connection state for visual appeal
  int cpuPct = bleConnected ? 12 : 4;

  // GPU: chip temperature (ESP32-C3 has internal temp sensor)
  float chipTempC = temperatureRead();
  int gpuVal = (int)chipTempC;

  // DISK: flash usage
  uint32_t sketchSize = ESP.getSketchSize();
  uint32_t totalSketch = sketchSize + ESP.getFreeSketchSpace();
  int diskPct = (totalSketch > 0) ? (int)((sketchSize * 100) / totalSketch) : 0;

  // Row layout: label at x=2, bar at x=32, value at x=102
  const int labelX = 2;
  const int barX = 32;
  const int barW = 65;
  const int barH = 7;
  const int valX = 100;
  const int rowH = 12;
  const int startY = 18;

  u8g2.setFont(u8g2_font_5x7_tr);

  // RAM row
  u8g2.drawStr(labelX, startY + 7, "RAM:");
  drawHwInfoBar(barX, startY + 1, barW, barH, ramPct);
  char valBuf[8];
  snprintf(valBuf, sizeof(valBuf), "%d%%", ramPct);
  u8g2.drawStr(valX, startY + 7, valBuf);

  // CPU row
  u8g2.drawStr(labelX, startY + rowH + 7, "CPU:");
  drawHwInfoBar(barX, startY + rowH + 1, barW, barH, cpuPct);
  snprintf(valBuf, sizeof(valBuf), "%d%%", cpuPct);
  u8g2.drawStr(valX, startY + rowH + 7, valBuf);

  // GPU row (temperature)
  u8g2.drawStr(labelX, startY + rowH * 2 + 7, "GPU:");
  int tempPct = clampi((gpuVal - 20) * 100 / 60, 0, 100); // 20-80C range
  drawHwInfoBar(barX, startY + rowH * 2 + 1, barW, barH, tempPct);
  snprintf(valBuf, sizeof(valBuf), "%dC", gpuVal);
  u8g2.drawStr(valX, startY + rowH * 2 + 7, valBuf);

  // DISK row
  u8g2.drawStr(labelX, startY + rowH * 3 + 7, "DISK:");
  drawHwInfoBar(barX, startY + rowH * 3 + 1, barW, barH, diskPct);
  snprintf(valBuf, sizeof(valBuf), "%d%%", diskPct);
  u8g2.drawStr(valX, startY + rowH * 3 + 7, valBuf);

  // "hold to exit" hint (fades after 5 sec)
  uint32_t elapsed = millis() - stateEnteredAt;
  if (elapsed < 5000) {
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(30, 63, "hold 2s = exit");
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expression Faces — triggered via BLE commands from the app
// ═══════════════════════════════════════════════════════════════════════════

void drawHappyFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float bounce = fabsf(sinf(t / 120.0f)) * 4.0f;
  int bob = (int)bounce;

  // Big arc eyes ^ ^
  for (int i = 0; i < 3; i++) {
    u8g2.drawCircle(40, 28 - bob + 5, 11 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
    u8g2.drawCircle(88, 28 - bob + 5, 11 - i,
                    U8G2_DRAW_UPPER_LEFT | U8G2_DRAW_UPPER_RIGHT);
  }

  // Wide smile
  u8g2.drawCircle(64, 38 - bob, 16, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);
  u8g2.drawCircle(64, 38 - bob, 15, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);
  u8g2.drawCircle(64, 38 - bob, 14, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);

  // Rosy cheeks
  u8g2.drawDisc(24, 38 - bob, 3);
  u8g2.drawDisc(104, 38 - bob, 3);

  u8g2.setFont(u8g2_font_5x7_tr);
  const char* txt = "YAY!";
  int tw = u8g2.getStrWidth(txt);
  u8g2.drawStr((OLED_W - tw) / 2, 62, txt);
}

void drawSadFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float breath = sinf(t / 1200.0f);
  int bob = (int)(breath * 1.5f);

  // Big round droopy eyes
  drawRoundedEye(40, 26 + bob, 20, 18);
  drawRoundedEye(88, 26 + bob, 20, 18);

  // Pupil highlights (inner dark circles to show sadness)
  u8g2.setDrawColor(0);
  u8g2.drawDisc(40, 28 + bob, 5);
  u8g2.drawDisc(88, 28 + bob, 5);
  u8g2.setDrawColor(1);
  // Tiny glint
  u8g2.drawPixel(38, 26 + bob);
  u8g2.drawPixel(86, 26 + bob);

  // Frown (inverted smile curve)
  int frownY = 48 + bob;
  for (int dx = -12; dx <= 12; dx++) {
    int y = frownY - (int)(dx * dx * 0.04f);
    u8g2.drawPixel(64 + dx, y);
    u8g2.drawPixel(64 + dx, y + 1);
  }

  // Tear drops (animated drip)
  int tearY = 36 + bob + (int)(fmodf(t / 400.0f, 1.0f) * 12.0f);
  if (tearY < 50) {
    u8g2.drawPixel(50, tearY);
    u8g2.drawPixel(50, tearY + 1);
    u8g2.drawPixel(98, tearY);
    u8g2.drawPixel(98, tearY + 1);
  }

  u8g2.setFont(u8g2_font_5x7_tr);
  const char* txt = "aww...";
  int tw = u8g2.getStrWidth(txt);
  u8g2.drawStr((OLED_W - tw) / 2, 62, txt);
}

void drawAngryFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float shake = sinf(t / 50.0f) * 1.5f;
  int sx = (int)shake;

  // Angry eyebrows (diagonal lines slanting inward)
  u8g2.drawLine(28 + sx, 14, 48 + sx, 20);
  u8g2.drawLine(28 + sx, 15, 48 + sx, 21);
  u8g2.drawLine(100 + sx, 14, 80 + sx, 20);
  u8g2.drawLine(100 + sx, 15, 80 + sx, 21);

  // Narrow glaring eyes
  drawRoundedEye(40 + sx, 28, 18, 8);
  drawRoundedEye(88 + sx, 28, 18, 8);

  // Gritted teeth mouth
  u8g2.drawFrame(50 + sx, 42, 28, 10);
  // Teeth lines
  for (int i = 1; i < 4; i++) {
    u8g2.drawVLine(50 + sx + i * 7, 42, 10);
  }
  // Horizontal divide
  u8g2.drawHLine(50 + sx, 47, 28);

  u8g2.setFont(u8g2_font_5x7_tr);
  const char* txt = "GRRR!";
  int tw = u8g2.getStrWidth(txt);
  u8g2.drawStr((OLED_W - tw) / 2, 62, txt);
}

void drawLoveFace(uint32_t t) {
  u8g2.setDrawColor(1);
  float pulse = 1.0f + sinf(t / 200.0f) * 0.15f;
  int bob = (int)(sinf(t / 600.0f) * 2.0f);

  // Heart-shaped eyes (two small hearts)
  for (int e = 0; e < 2; e++) {
    int cx = (e == 0) ? 40 : 88;
    int cy = 24 + bob;
    int s = (int)(6.0f * pulse);
    // Heart = two overlapping discs + triangle
    u8g2.drawDisc(cx - s/2, cy - s/3, s/2);
    u8g2.drawDisc(cx + s/2, cy - s/3, s/2);
    u8g2.drawTriangle(cx - s, cy, cx + s, cy, cx, cy + s);
  }

  // Cute smile
  int smileY = 44 + bob;
  u8g2.drawCircle(64, smileY - 4, 12, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);
  u8g2.drawCircle(64, smileY - 4, 11, U8G2_DRAW_LOWER_LEFT | U8G2_DRAW_LOWER_RIGHT);

  // Floating hearts
  float drift = fmodf(t / 800.0f, 1.0f);
  int hx = 12 + (int)(drift * 20.0f);
  int hy = 10 - (int)(drift * 8.0f);
  u8g2.drawDisc(hx, hy, 2);
  u8g2.drawDisc(hx + 3, hy, 2);
  u8g2.drawTriangle(hx - 2, hy + 1, hx + 5, hy + 1, hx + 1, hy + 5);

  int hx2 = 108 - (int)(drift * 15.0f);
  int hy2 = 12 - (int)(drift * 6.0f);
  u8g2.drawDisc(hx2, hy2, 2);
  u8g2.drawDisc(hx2 + 3, hy2, 2);
  u8g2.drawTriangle(hx2 - 2, hy2 + 1, hx2 + 5, hy2 + 1, hx2 + 1, hy2 + 5);

  u8g2.setFont(u8g2_font_5x7_tr);
  const char* txt = "<3 <3";
  int tw = u8g2.getStrWidth(txt);
  u8g2.drawStr((OLED_W - tw) / 2, 62, txt);
}

// ═══════════════════════════════════════════════════════════════════════════

void drawAppModeScreen(uint32_t t) {
  u8g2.setDrawColor(1);

  // Mario Clock — full-screen takeover
  if (displayMode == DISPLAY_MARIO_CLOCK) {
    drawMarioClockScreen();
    return;
  }

  // HW Info — full-screen takeover
  if (displayMode == DISPLAY_HW_INFO) {
    drawHwInfoScreen();
    return;
  }
  if (drawMode) {
    for (int i = 0; i < segCount; i++) {
      drawLineSolid(segs[i].x1, segs[i].y1, segs[i].x2, segs[i].y2);
    }
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr(2, 7, "DRAW 2x=exit");
    return;
  }

  if (focusActive || displayMode == DISPLAY_FOCUS) {
    // Focus mode is timer-only: no face, weather, or clock overlays.
    const char* timerTxt = stopwatchText[0] != '\0' ? stopwatchText : "25:00";
    u8g2.drawFrame(10, 12, 108, 43);
    u8g2.drawHLine(18, 16, 92);
    u8g2.setFont(u8g2_font_logisoso24_tr);
    int tw = u8g2.getStrWidth(timerTxt);
    u8g2.drawStr((OLED_W - tw) / 2, 46, timerTxt);
    u8g2.setFont(u8g2_font_4x6_tr);
    u8g2.drawStr((OLED_W - u8g2.getStrWidth("FOCUS")) / 2, 8, "FOCUS");
    u8g2.drawStr(37, 62, "hold = home");
    return;
  }

  if (displayMode == DISPLAY_BLE) {
    float sec = t / 1000.0f;
    
    u8g2.setFont(u8g2_font_7x13B_tr);
    int w1 = u8g2.getStrWidth("BLINK");
    u8g2.drawStr((OLED_W - w1) / 2, 14, "BLINK");
    
    u8g2.setFont(u8g2_font_4x6_tr);
    const char* stat = bleConnected ? "CONNECTED" : "DISCONNECTED";
    int w2 = u8g2.getStrWidth(stat);
    if (!bleConnected) {
      u8g2.setDrawColor(2); // Use XOR mode if needed or just draw normally
    }
    u8g2.drawStr((OLED_W - w2) / 2, 22, stat);
    u8g2.setDrawColor(1);
    
    for (int i = 0; i < 5; i++) {
      float baseH = 19.2f * ((i + 1) / 5.0f);
      float bh = baseH + sinf(sec * 3.0f + i * 1.2f) * 2.5f;
      int bx = 32 + i * 13;
      int h = (int)bh;
      if (h < 1) h = 1;
      
      if (!bleConnected && i > 2) {
        u8g2.drawFrame(bx, 46 - h, 6, h);
      } else {
        u8g2.drawBox(bx, 46 - h, 6, h);
      }
    }
    
    int dotX = 64 + (int)(cosf(sec * 1.5f) * 10.0f);
    int dotY = 32 + (int)(sinf(sec * 1.8f) * 4.0f);
    
    u8g2.drawDisc(dotX, dotY, 2);
    u8g2.drawCircle(dotX, dotY, 4);
    
    return;
  }

  // Normal face is always rendered by STATE_IDLE. APP_MODE never mixes a
  // face with another menu option or a clock.
  u8g2.setFont(u8g2_font_6x12_tr);
  u8g2.drawStr(28, 33, "SELECT A MODE");
  u8g2.setFont(u8g2_font_4x6_tr);
  u8g2.drawStr(36, 49, "hold = home");
}

// ═══════════════════════════════════════════════════════════════════════════
// BLE Pairing Animation — matches website OLED simulator 'app' mode
// ═══════════════════════════════════════════════════════════════════════════

void drawBlePairingScreen(uint32_t t) {
  u8g2.setDrawColor(1);
  float sec = t / 1000.0f;
  uint32_t elapsed = t - blePairAnimStartAt;
  float p = clampf(elapsed / 3000.0f, 0.0f, 1.0f); // 3 second animation
  
  // "BLINK" text with fade-in
  u8g2.setFont(u8g2_font_7x13B_tr);
  int w1 = u8g2.getStrWidth("BLINK");
  int x1 = (OLED_W - w1) / 2;
  int y1 = 14;
  
  if (p < 0.3f) {
    float tp = p / 0.3f;
    int tx = x1 + (int)((1.0f - tp) * 20.0f);
    u8g2.drawStr(tx, y1, "BLINK");
  } else {
    u8g2.drawStr(x1, y1, "BLINK");
  }
  
  // Status text
  u8g2.setFont(u8g2_font_4x6_tr);
  const char* stat;
  if (blePairState == BLE_PAIR_SCANNING) stat = "SCANNING...";
  else if (blePairState == BLE_PAIR_CONNECTING) stat = "CONNECTING...";
  else if (blePairState == BLE_PAIR_CONNECTED) stat = "CONNECTED!";
  else stat = "FAILED";
  
  int w2 = u8g2.getStrWidth(stat);
  u8g2.drawStr((OLED_W - w2) / 2, 22, stat);
  
  // Animated bars (5 bars like website demo)
  for (int i = 0; i < 5; i++) {
    float baseH = 19.2f * ((i + 1) / 5.0f);
    float phaseOffset = i * 1.2f;
    float bh = baseH + sinf(sec * 3.0f + phaseOffset) * 2.5f;
    
    // Add connection progress visualization
    if (blePairState == BLE_PAIR_CONNECTING) {
      bh = baseH * p + sinf(sec * 4.0f + phaseOffset) * 1.5f;
    } else if (blePairState == BLE_PAIR_CONNECTED) {
      bh = baseH + sinf(sec * 2.0f + phaseOffset) * 1.0f;
    }
    
    int bx = 32 + i * 13;
    int h = (int)bh;
    if (h < 1) h = 1;
    
    if (blePairState == BLE_PAIR_FAILED || (blePairState == BLE_PAIR_SCANNING && i > 2)) {
      u8g2.drawFrame(bx, 46 - h, 6, h);
    } else {
      u8g2.drawBox(bx, 46 - h, 6, h);
    }
  }
  
  // Floating dot (like website)
  int dotX = 64 + (int)(cosf(sec * 1.5f) * 10.0f);
  int dotY = 32 + (int)(sinf(sec * 1.8f) * 4.0f);
  u8g2.drawDisc(dotX, dotY, 2);
  u8g2.drawCircle(dotX, dotY, 4);
  
  // Sparkle particles on connect
  if (blePairState == BLE_PAIR_CONNECTED) {
    for (int i = 0; i < 6; i++) {
      float sp = fmodf(sec * 2.0f + i * 1.05f, 1.0f);
      int sx = 64 + (int)(cosf(sp * 6.283f) * (15.0f + 20.0f * p));
      int sy = 32 + (int)(sinf(sp * 6.283f + i) * (8.0f + 12.0f * p));
      if (sx > 2 && sx < 126 && sy > 2 && sy < 62) {
        u8g2.drawDisc(sx, sy, 1);
      }
    }
  }
}

void renderFrame() {
  uint32_t now = millis();
  uint32_t inState = now - stateEnteredAt;

  u8g2.clearBuffer();
  u8g2.setDrawColor(1);

  if (menuOpen) {
    drawMenuScreen();
  } else if (blePairState != BLE_PAIR_IDLE) {
    drawBlePairingScreen(now);
  } else {
    switch (state) {
      case STATE_BOOT:
        drawBootScreen(inState);
        break;
      case STATE_IDLE:
        drawIdleAnimation(now);
        break;
      case STATE_TICKLED:
        drawTickledFace(inState);
        break;
      case STATE_DIZZY:
        drawDizzyFace(inState);
        break;
      case STATE_YAWN:
        drawYawnFace(inState);
        break;
      case STATE_SLEEP:
        drawSleepFace(inState);
        break;
      case STATE_APP_MODE:
        drawAppModeScreen(now);
        break;
      case STATE_HAPPY:
        drawHappyFace(inState);
        break;
      case STATE_SAD:
        drawSadFace(inState);
        break;
      case STATE_ANGRY:
        drawAngryFace(inState);
        break;
      case STATE_LOVE:
        drawLoveFace(inState);
        break;
    }
  }

  u8g2.sendBuffer();
}

// ═══════════════════════════════════════════════════════════════════════════
// Sensors
// ═══════════════════════════════════════════════════════════════════════════

bool readTouch() {
  if (!touchEnabled) return false;
  return digitalRead(PIN_TOUCH) == HIGH;
}

bool readShake() {
  if (!mpuOk) {
    // Periodically retry MPU init if it failed at boot
    uint32_t now = millis();
    if (now - lastMpuRetryAt > MPU_RETRY_MS) {
      lastMpuRetryAt = now;
      Serial.println("[MPU] Retrying init...");
      Wire.begin(PIN_SDA, PIN_SCL);
      Wire.setClock(100000);
      mpuOk = mpu.begin(0x68, &Wire);
      if (!mpuOk) mpuOk = mpu.begin(0x69, &Wire);
      if (mpuOk) {
        mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
        mpu.setGyroRange(MPU6050_RANGE_500_DEG);
        mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
        Wire.setClock(400000);
        mpuBaselineReady = false;
        Serial.println("[MPU] Reconnected!");
      }
    }
    return false;
  }

  sensors_event_t a, g, temp;
  if (!mpu.getEvent(&a, &g, &temp)) {
    // I2C read failed — try bus recovery
    Serial.println("[MPU] I2C read failed, recovering...");
    Wire.end();
    delay(5);
    Wire.begin(PIN_SDA, PIN_SCL);
    Wire.setClock(400000);
    mpuOk = false;  // will retry on next call
    return false;
  }

  float mag = sqrtf(a.acceleration.x * a.acceleration.x +
                    a.acceleration.y * a.acceleration.y +
                    a.acceleration.z * a.acceleration.z);
  float gForce = mag / 9.80665f;
  
  float gyroDps = sqrtf(g.gyro.x * g.gyro.x + g.gyro.y * g.gyro.y +
                        g.gyro.z * g.gyro.z) * 57.29578f;

  // Establish baseline on first valid reads
  if (!mpuBaselineReady) {
    mpuBaselineG = gForce;
    mpuBaselineReady = true;
  }

  // Advanced shake detection: combine absolute threshold + delta from baseline + gyro spike
  float deltaG = fabsf(gForce - mpuBaselineG);
  
  // Slowly adapt baseline to handle orientation changes (low-pass filter)
  mpuBaselineG = mpuBaselineG * 0.995f + gForce * 0.005f;

  // Shake detected if: total g-force exceeds threshold OR sudden delta from baseline OR high rotation
  bool shook = (gForce > SHAKE_THRESHOLD) || (deltaG > SHAKE_DELTA_G) || (gyroDps > SHAKE_GYRO_DPS);
  
  if (shook) {
    Serial.printf("[MPU] SHAKE! g=%.2f delta=%.2f gyro=%.0f\n", gForce, deltaG, gyroDps);
  }
  return shook;
}

int readBatteryPercent() {
  // Multi-sample average for stable ADC reads
  // 2:1 divider: 4.2V full → ~2.1V at pin; 3.3V empty → ~1.65V at pin
  long sum = 0;
  for (int i = 0; i < 8; i++) {
    sum += analogRead(PIN_BATTERY);
  }
  int raw = sum / 8;
  float pinV = (raw / 4095.0f) * 3.3f;
  float battV = pinV * 2.0f;
  int pct = (int)((battV - 3.30f) / (4.20f - 3.30f) * 100.0f);
  return clampi(pct, 0, 100);
}

void pollBattery() {
  uint32_t now = millis();
  if (now - lastBatteryReadAt < 5000) return;
  lastBatteryReadAt = now;
  batteryPercent = readBatteryPercent();
}

void exitDrawModeFromTouch() {
  drawMode = false;
  clearDrawing();
  if (focusActive || displayMode == DISPLAY_FOCUS) {
    enterState(STATE_APP_MODE);
  } else if (displayMode != DISPLAY_NORMAL) {
    enterState(STATE_IDLE);
  } else {
    enterState(STATE_IDLE);
  }
}

void handleTouchGesture(int tapCount) {
  if (tapCount <= 0) return;
  lastGestureAt = millis();

  // Drawing mode: double-tap exits
  if (drawMode && tapCount == 2) {
    exitDrawModeFromTouch();
    return;
  }

  if (menuOpen) {
    if (tapCount == 1) {
      menuIndex = (menuIndex + 1) % MENU_COUNT;
    } else if (tapCount == 2) {
      menuIndex = (menuIndex - 1 + MENU_COUNT) % MENU_COUNT;
    } else if (tapCount >= 3) {
      applyMenuSelection();
    }
    return;
  }

  if (tapCount >= 3) {
    menuOpen = true;
    menuIndex = 0;
    return;
  }

  // Menu screens own the full OLED. Only the normal idle face reacts to a
  // pet/tickle tap, so an opened option is never replaced by a face.
  if (tapCount == 1 && state == STATE_IDLE &&
      displayMode == DISPLAY_NORMAL && !drawMode && !focusActive) {
    enterState(STATE_TICKLED);
  }
}

void pollTouchGestures() {
  if (!touchEnabled) return;

  uint32_t now = millis();
  bool pressed = readTouch();

  // A long hold always returns to the main animated face, from the menu or
  // any option. It is deliberately not a tap, so no accidental action fires.
  if (pressed && touchWasActive) {
    uint32_t holdDuration = now - touchDownAt;
    if (holdDuration >= LONG_PRESS_MS && !longPressTriggered) {
      longPressTriggered = true;
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_NORMAL;
      menuOpen = false;
      stopwatchText[0] = '\0';
      enterState(STATE_IDLE);
      touchWasActive = pressed;
      return;  // Skip tap processing this cycle
    }
  }

  if (pressed && !touchWasActive) {
    touchActive = true;
    touchDownAt = now;
    longPressTriggered = false;  // Reset on new press
  }

  if (!pressed && touchWasActive) {
    touchActive = false;
    touchUpAt = now;
    uint32_t held = touchUpAt - touchDownAt;
    // Don't register taps from a long-press release
    if (longPressTriggered) {
      longPressTriggered = false;
    } else if (held <= TAP_MAX_MS) {
      if (pendingTapCount == 0) tapWindowStart = touchUpAt;
      if (touchUpAt - tapWindowStart <= TAP_GAP_MS * 3) {
        pendingTapCount++;
      } else {
        pendingTapCount = 1;
        tapWindowStart = touchUpAt;
      }
    }
  }

  touchWasActive = pressed;

  if (pendingTapCount > 0 && !pressed &&
      now - touchUpAt >= TAP_SETTLE_MS) {
    handleTouchGesture(pendingTapCount);
    pendingTapCount = 0;
  }
}

void pollSensors() {
  uint32_t now = millis();
  if (now - lastSensorAt < SENSOR_MS) return;
  lastSensorAt = now;

  pollTouchGestures();
  pollBattery();

  // Touch wakes BLINK from yawn / sleep (any touch, not just tap)
  if (state == STATE_YAWN || state == STATE_SLEEP) {
    if (readTouch()) {
      menuOpen = false;
      enterState(focusActive || drawMode ? STATE_APP_MODE : STATE_IDLE);
    }
    return;
  }

  // Skip emotions while menu is open
  if (menuOpen) return;

  // Shake → dizzy (MPU6050 or BLE SHAKE command)
  bool allowShake = (state == STATE_IDLE || state == STATE_APP_MODE ||
                     state == STATE_TICKLED);
  if (allowShake && now - lastShakeAt > SHAKE_COOLDOWN_MS && readShake()) {
    lastShakeAt = now;
    enterState(STATE_DIZZY);
  }
}

void pollNightBehavior() {
  if (state != STATE_IDLE) return;
  if (!isNightTime()) return;

  uint32_t now = millis();
  if (now - lastNightCheckAt < NIGHT_CHECK_MS) return;
  lastNightCheckAt = now;

  if ((esp_random() % 100) < NIGHT_YAWN_CHANCE) {
    enterState(STATE_YAWN);
  }
}

void updateStateMachine() {
  uint32_t now = millis();
  uint32_t elapsed = now - stateEnteredAt;

  switch (state) {
    case STATE_BOOT:
      if (elapsed >= BOOT_MS) {
        enterState(STATE_IDLE);
      }
      break;

    case STATE_TICKLED:
      if (elapsed >= TICKLE_MS) {
        enterState(focusActive || drawMode ? STATE_APP_MODE : STATE_IDLE);
      }
      break;

    case STATE_DIZZY:
      if (elapsed >= DIZZY_MS) {
        enterState(focusActive || drawMode ? STATE_APP_MODE : STATE_IDLE);
      }
      break;

    case STATE_YAWN:
      if (elapsed >= YAWN_MS) {
        enterState(STATE_SLEEP);
      }
      break;

    case STATE_SLEEP:
      if (elapsed >= SLEEP_MS) {
        enterState(focusActive || drawMode ? STATE_APP_MODE : STATE_IDLE);
      }
      break;

    case STATE_IDLE:
    case STATE_APP_MODE:
      break;

    case STATE_HAPPY:
    case STATE_SAD:
    case STATE_ANGRY:
    case STATE_LOVE:
      if (elapsed >= EXPRESSION_MS) {
        enterState(STATE_IDLE);
      }
      break;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// BLE callbacks + command handling
// ═══════════════════════════════════════════════════════════════════════════

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo) override {
    bleConnected = true;
    // Trigger pairing animation
    blePairState = BLE_PAIR_CONNECTING;
    blePairAnimStartAt = millis();
    blePairStateEnteredAt = millis();
    playCustomSound(SOUND_CONNECTED, sizeof(SOUND_CONNECTED) / sizeof(SOUND_CONNECTED[0]));
  }
  void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason) override {
    bleConnected = false;
    // Show disconnected animation briefly
    blePairState = BLE_PAIR_FAILED;
    blePairAnimStartAt = millis();
    playCustomSound(SOUND_DISCONNECTED, sizeof(SOUND_DISCONNECTED) / sizeof(SOUND_DISCONNECTED[0]));
    // Robot keeps running offline with last RTC + sensors
    NimBLEDevice::startAdvertising();
    // Reset pairing animation after a delay
    // (handled in loop via state machine)
  }
};

class TimeCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) override {
    std::string v = c->getValue();
    if (v.empty() || v.size() >= sizeof(timeBuf)) return;
    memcpy((void*)timeBuf, v.c_str(), v.size());
    timeBuf[v.size()] = '\0';
    pendingTime = true;
  }
};

class CmdCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) override {
    std::string v = c->getValue();
    if (v.empty() || v.size() >= sizeof(cmdBuf)) return;
    memcpy((void*)cmdBuf, v.c_str(), v.size());
    cmdBuf[v.size()] = '\0';
    pendingCmd = true;
  }
};

class DrawCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) override {
    std::string v = c->getValue();
    if (v.empty() || v.size() >= sizeof(drawBuf)) return;
    memcpy((void*)drawBuf, v.c_str(), v.size());
    drawBuf[v.size()] = '\0';
    pendingDraw = true;
  }
};

class OtaControlCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) override {
    const std::string value = c->getValue();
    if (value.rfind("BEGIN:", 0) == 0) {
      beginOtaUpdate(strtoul(value.c_str() + 6, nullptr, 10));
    } else if (value == "END") {
      finishOtaUpdate();
    } else if (value == "ABORT") {
      abortOtaUpdate("cancelled");
    } else if (value == "VERSION") {
      char status[32];
      snprintf(status, sizeof(status), "VERSION:%s", FIRMWARE_VERSION);
      notifyOtaStatus(status);
    } else {
      notifyOtaStatus("OTA:ERROR:command");
    }
  }
};

class OtaDataCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& /*connInfo*/) override {
    if (!otaInProgress) {
      notifyOtaStatus("OTA:ERROR:not-started");
      return;
    }
    const std::string value = c->getValue();
    if (value.empty() || value.size() > otaExpectedBytes - otaReceivedBytes) {
      abortOtaUpdate("chunk");
      return;
    }
    if (Update.write(reinterpret_cast<uint8_t*>(const_cast<char*>(value.data())), value.size()) != value.size()) {
      abortOtaUpdate("write");
      return;
    }
    otaReceivedBytes += value.size();
    if (otaReceivedBytes == otaExpectedBytes ||
        otaReceivedBytes - otaLastReportedBytes >= 4096) {
      otaLastReportedBytes = otaReceivedBytes;
      char status[48];
      snprintf(status, sizeof(status), "OTA:PROGRESS:%u:%u",
               (unsigned)otaReceivedBytes, (unsigned)otaExpectedBytes);
      notifyOtaStatus(status);
    }
  }
};

void handlePendingBle() {
  if (pendingTime) {
    pendingTime = false;
    long unixSec = atol(timeBuf);
    if (unixSec > 1000000000L) {
      setRtcFromUnix(unixSec);
    }
  }

  if (pendingCmd) {
    pendingCmd = false;
    // Commands:
    //   FOCUS / FOCUS:MM:SS  — enter focus mode (optional timer text)
    //   IDLE                 — leave app mode
    //   DRAW / DRAW:ON       — enter drawing mode
    //   DRAW:OFF / CLEAR     — clear canvas / leave draw
    //   SW:MM:SS             — stopwatch overlay text
    //   TOUCH:ON / TOUCH:OFF
    //   SOUND:TEST           — play the fitted passive-buzzer melody
    //   RESET / FACTORY / FACTORY_RESET — clear canvas, exit modes, replay BLINK boot
    if (strcmp(cmdBuf, "FOCUS:DONE") == 0) {
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_NORMAL;
      stopwatchText[0] = '\0';
      playCustomSound(SOUND_FOCUS_DONE,
                      sizeof(SOUND_FOCUS_DONE) / sizeof(SOUND_FOCUS_DONE[0]));
      enterState(STATE_IDLE);
    } else if (strncmp(cmdBuf, "FOCUS", 5) == 0) {
      focusActive = true;
      drawMode = false;
      displayMode = DISPLAY_FOCUS;
      menuOpen = false;
      if (cmdBuf[5] == ':' && cmdBuf[6] != '\0') {
        strncpy(stopwatchText, cmdBuf + 6, sizeof(stopwatchText) - 1);
        stopwatchText[sizeof(stopwatchText) - 1] = '\0';
      }
      if (state == STATE_IDLE || state == STATE_APP_MODE) enterState(STATE_APP_MODE);
    } else if (strcmp(cmdBuf, "IDLE") == 0) {
      focusActive = false;
      drawMode = false;
      displayMode = DISPLAY_NORMAL;
      menuOpen = false;
      stopwatchText[0] = '\0';
      if (state == STATE_APP_MODE) enterState(STATE_IDLE);
    } else if (strncmp(cmdBuf, "DRAW", 4) == 0) {
      bool on = true;
      if (strstr(cmdBuf, "OFF") != nullptr) on = false;
      drawMode = on;
      if (on) {
        focusActive = false;
        if (state == STATE_IDLE || state == STATE_APP_MODE) enterState(STATE_APP_MODE);
      } else if (!focusActive) {
        enterState(STATE_IDLE);
      }
    } else if (strcmp(cmdBuf, "CLEAR") == 0) {
      clearDrawing();
    } else if (strcmp(cmdBuf, "RESET") == 0 ||
               strcmp(cmdBuf, "FACTORY") == 0 ||
               strcmp(cmdBuf, "FACTORY_RESET") == 0) {
      factoryResetRobot();
    } else if (strncmp(cmdBuf, "SW:", 3) == 0) {
      strncpy(stopwatchText, cmdBuf + 3, sizeof(stopwatchText) - 1);
      stopwatchText[sizeof(stopwatchText) - 1] = '\0';
      if (!focusActive && !drawMode && state == STATE_IDLE) {
        // show stopwatch in app mode briefly
        enterState(STATE_APP_MODE);
      }
    } else if (strcmp(cmdBuf, "TOUCH:ON") == 0) {
      touchEnabled = true;
    } else if (strcmp(cmdBuf, "SHAKE") == 0) {
      lastShakeAt = millis();
      enterState(STATE_DIZZY);
    } else if (strcmp(cmdBuf, "TOUCH:OFF") == 0) {
      touchEnabled = false;
    } else if (strcmp(cmdBuf, "SOUND:TEST") == 0) {
      playCustomSound(SOUND_BOOT, sizeof(SOUND_BOOT) / sizeof(SOUND_BOOT[0]));
    } else if (strcmp(cmdBuf, "SOUND:STOP") == 0) {
      stopCustomSound();
    } else if (strcmp(cmdBuf, "BUZZER:ON") == 0) {
      buzzerEnabled = true;
    } else if (strcmp(cmdBuf, "BUZZER:OFF") == 0) {
      buzzerEnabled = false;
      stopCustomSound();
    } else if (strncmp(cmdBuf, "MOOD:", 5) == 0) {
      const char* moodArg = cmdBuf + 5;
      weatherMood = clampi(atoi(moodArg), -2, 2);
      lastWeatherSyncAt = millis();
    } else if (strncmp(cmdBuf, "ANIM:", 5) == 0) {
      const char* animArg = cmdBuf + 5;
      if (strcmp(animArg, "OFF") == 0) {
        idleAnimationsEnabled = false;
      } else if (strcmp(animArg, "ON") == 0) {
        idleAnimationsEnabled = true;
        idleAnimStartedAt = millis();
        idleTransitioning = false;
      } else if (strcmp(animArg, "NEXT") == 0) {
        // Skip to next random idle animation
        if (state == STATE_IDLE) {
          currentIdleAnim = pickNextIdleAnim();
          idleAnimStartedAt = millis();
          idleAnimDuration = 5000 + (esp_random() % 5001);
          idleTransitioning = false;
        }
      } else if (strncmp(animArg, "SPEED:", 6) == 0) {
        const char* speed = animArg + 6;
        if (strcmp(speed, "FAST") == 0) {
          idleAnimDuration = 3000 + (esp_random() % 2001); // 3-5s
        } else if (strcmp(speed, "SLOW") == 0) {
          idleAnimDuration = 8000 + (esp_random() % 7001); // 8-15s
        } else {
          idleAnimDuration = 5000 + (esp_random() % 5001); // normal 5-10s
        }
      } else {
        // ANIM:N — force specific animation index
        int idx = atoi(animArg);
        if (idx >= 0 && idx < IDLE_ANIM_COUNT && state == STATE_IDLE) {
          currentIdleAnim = idx;
          idleAnimStartedAt = millis();
          idleAnimDuration = 5000 + (esp_random() % 5001);
          idleTransitioning = false;
        }
      }
    } else if (strncmp(cmdBuf, "EXP:", 4) == 0) {
      const char* expr = cmdBuf + 4;
      if (strcmp(expr, "HAPPY") == 0) {
        enterState(STATE_HAPPY);
      } else if (strcmp(expr, "SAD") == 0) {
        enterState(STATE_SAD);
      } else if (strcmp(expr, "ANGRY") == 0) {
        enterState(STATE_ANGRY);
      } else if (strcmp(expr, "LOVE") == 0) {
        enterState(STATE_LOVE);
      } else {
        enterState(STATE_IDLE);
      }
    }
  }

  if (pendingDraw) {
    pendingDraw = false;
    // Only process draw data if draw mode was explicitly enabled via DRAW command
    // This prevents stray/leftover BLE packets from auto-enabling draw mode
    // Throttle draw processing to avoid overwhelming the OLED
    static uint32_t lastDrawProcessAt = 0;
    if (drawMode && (millis() - lastDrawProcessAt >= DRAW_BLE_THROTTLE_MS)) {
      lastDrawProcessAt = millis();
      parseDrawPayload(drawBuf);
    }
  }
}

void setupBle() {
  NimBLEDevice::init(DEVICE_NAME);
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);

  bleServer = NimBLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  NimBLEService* service = bleServer->createService(SERVICE_UUID);

  timeChar = service->createCharacteristic(
      TIME_CHAR_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  timeChar->setCallbacks(new TimeCallbacks());

  cmdChar = service->createCharacteristic(
      CMD_CHAR_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  cmdChar->setCallbacks(new CmdCallbacks());

  drawChar = service->createCharacteristic(
      DRAW_CHAR_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  drawChar->setCallbacks(new DrawCallbacks());

  stateChar = service->createCharacteristic(
      STATE_CHAR_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  stateChar->setValue("0,0,0,0,0,0,0");

  otaControlChar = service->createCharacteristic(
      OTA_CONTROL_UUID,
      NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  otaControlChar->setCallbacks(new OtaControlCallbacks());

  otaDataChar = service->createCharacteristic(
      OTA_DATA_UUID,
      NIMBLE_PROPERTY::WRITE);
  otaDataChar->setCallbacks(new OtaDataCallbacks());

  otaStatusChar = service->createCharacteristic(
      OTA_STATUS_UUID,
      NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  char versionStatus[32];
  snprintf(versionStatus, sizeof(versionStatus), "VERSION:%s", FIRMWARE_VERSION);
  otaStatusChar->setValue(versionStatus);

  service->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setName(DEVICE_NAME);
  adv->enableScanResponse(true);
  adv->start();
}

void setupSensors() {
  pinMode(PIN_TOUCH, INPUT);
  if (PIN_BUZZER >= 0) {
    pinMode(PIN_BUZZER, OUTPUT);
    noTone(PIN_BUZZER);
  }
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(PIN_BATTERY, INPUT);

  // Initialize I2C — start clean
  Wire.end();
  delay(10);
  Wire.begin(PIN_SDA, PIN_SCL);
  Wire.setClock(100000);  // start at 100kHz for reliable init

  u8g2.begin();
  u8g2.setContrast(255);
  u8g2.clearBuffer();
  u8g2.sendBuffer();

  // MPU6050 initialization with robust I2C scan
  Serial.println("[MPU] Scanning I2C bus...");
  uint8_t mpuAddr = 0;
  for (uint8_t addr : {0x68, 0x69}) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("[MPU] Found device at 0x%02X\n", addr);
      mpuAddr = addr;
      break;
    }
  }

  if (mpuAddr == 0) {
    Serial.println("[MPU] No MPU6050 found on I2C bus! Will retry later.");
    mpuOk = false;
  } else {
    delay(50);  // let bus settle after scan
    mpuOk = mpu.begin(mpuAddr, &Wire);
    if (mpuOk) {
      Serial.printf("[MPU] MPU6050 OK @ 0x%02X\n", mpuAddr);
      mpu.setAccelerometerRange(MPU6050_RANGE_4_G);  // 4G for desk shake sensitivity
      mpu.setGyroRange(MPU6050_RANGE_500_DEG);
      mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
      delay(150);  // warm-up

      // Baseline calibration
      float gSum = 0;
      int validReads = 0;
      for (int i = 0; i < 15; i++) {
        sensors_event_t a, g, temp;
        if (mpu.getEvent(&a, &g, &temp)) {
          float mag = sqrtf(a.acceleration.x * a.acceleration.x +
                            a.acceleration.y * a.acceleration.y +
                            a.acceleration.z * a.acceleration.z);
          gSum += mag / 9.80665f;
          validReads++;
        }
        delay(15);
      }
      if (validReads > 0) {
        mpuBaselineG = gSum / validReads;
        mpuBaselineReady = true;
        Serial.printf("[MPU] Baseline: %.2f g (%d samples)\n", mpuBaselineG, validReads);
      }
    } else {
      Serial.printf("[MPU] begin() failed at 0x%02X — will retry\n", mpuAddr);
    }
  }

  // Speed up I2C now that init is done
  Wire.setClock(400000);

  batteryPercent = readBatteryPercent();
  Serial.printf("[BAT] Initial: %d%%\n", batteryPercent);
}

// ═══════════════════════════════════════════════════════════════════════════
void setup() {
  Serial.begin(115200);
  delay(50);  // only once at boot for USB CDC — never in loop()

  setupSensors();
  setupBle();

  // Default timezone offset can be adjusted after BLE time sync from the phone
  setenv("TZ", "IST-5:30", 1);
  tzset();

  enterState(STATE_BOOT);
  playCustomSound(SOUND_BOOT, sizeof(SOUND_BOOT) / sizeof(SOUND_BOOT[0]));
  Serial.println("BLINK ready");
}

void loop() {
  handlePendingBle();
  updateStateMachine();
  pollNightBehavior();
  pollSensors();
  updateCustomSound();
  notifyRobotState();
  maybeRestartAfterOta();
  
  // BLE pairing animation state machine
  if (blePairState == BLE_PAIR_CONNECTING && bleConnected) {
    blePairState = BLE_PAIR_CONNECTED;
    blePairAnimStartAt = millis();
  } else if (blePairState == BLE_PAIR_CONNECTED && millis() - blePairAnimStartAt > 3000) {
    blePairState = BLE_PAIR_IDLE;
  } else if (blePairState == BLE_PAIR_FAILED && millis() - blePairAnimStartAt > 2000) {
    blePairState = BLE_PAIR_IDLE;
  } else if (blePairState == BLE_PAIR_SCANNING && bleConnected) {
    blePairState = BLE_PAIR_CONNECTING;
    blePairAnimStartAt = millis();
    playCustomSound(SOUND_CONNECTED, sizeof(SOUND_CONNECTED) / sizeof(SOUND_CONNECTED[0]));
  }

  uint32_t now = millis();
  if (now - lastFrameAt >= FRAME_MS) {
    lastFrameAt = now;
    renderFrame();
  }
  // Cooperative yield — no delay() that would freeze animations
}
