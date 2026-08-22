import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/robot_animation_snapshot.dart';
import '../services/ble_manager.dart';
import '../services/firmware_update_service.dart';
import '../services/weather_mood_service.dart';
import '../theme/blink_constants.dart';

/// Connection state of the robot.
/// Named BleConnectionState to avoid conflict with dart:async's ConnectionState.
enum BleConnectionState {
  disconnected,
  scanning,
  connected,
}

/// Manages all reactive state for the BLINK robot companion.
class RobotStateProvider extends ChangeNotifier
    with WidgetsBindingObserver {
  RobotStateProvider({
    BleManager? ble,
    FirmwareUpdateService? firmware,
    WeatherMoodService? weatherMood,
  })  : _ble = ble ?? BleManager.instance,
        _firmware = firmware ?? FirmwareUpdateService.instance,
        _weatherMood = weatherMood ?? WeatherMoodService.instance {
    WidgetsBinding.instance.addObserver(this);
    _ble.addListener(_onBleChanged);
    _firmware.addListener(_onFirmwareChanged);
    _onBleChanged();

    // Everything below touches a platform plugin.  Running it inside the
    // provider constructor meant it ran during the first build, while the
    // Android activity/engine could still be attaching — a throw there took
    // startup down with it.  Defer to after the first frame and guard each
    // step independently so no single failure can block the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapServices());
    });
  }

  Future<void> _bootstrapServices() async {
    if (_bootstrapped) return;
    _bootstrapped = true;

    try {
      await _loadLocalPreferences();
    } catch (error) {
      debugPrint('[BLINK] preference load failed (non-fatal): $error');
    }

    try {
      await _firmware.initialize();
    } catch (error) {
      debugPrint('[BLINK] firmware service init failed (non-fatal): $error');
    }

    try {
      await _requestPermissionsOnStartup();
    } catch (error) {
      debugPrint('[BLINK] permission request failed (non-fatal): $error');
    }

    try {
      await _initializeWeatherMood();
    } catch (error) {
      debugPrint('[BLINK] weather mood init failed (non-fatal): $error');
    }
  }

  Future<void> _initializeWeatherMood() async {
    await _weatherMood.initialize();
    // Listen for weather mood changes.  Guarded against double-registration
    // because WeatherMoodService is a process-wide singleton that survives
    // activity recreation.
    _weatherMood.removeListener(_onWeatherMoodChanged);
    _weatherMood.addListener(_onWeatherMoodChanged);
  }

  void _onWeatherMoodChanged() {
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) return;
    // Never hammer GitHub or the BLE link on every foreground bounce, and never
    // start network work while a firmware transfer is running.
    if (_firmware.otaInProgress || _ble.firmwareUpdateInProgress) return;
    final now = DateTime.now();
    if (now.difference(_lastResumeRefreshAt) < const Duration(minutes: 5)) {
      return;
    }
    _lastResumeRefreshAt = now;
    unawaited(_firmware.checkGitHubRelease());
    unawaited(_weatherMood.forceSync());
  }

  final BleManager _ble;
  final FirmwareUpdateService _firmware;
  final WeatherMoodService _weatherMood;

  bool _bootstrapped = false;
  DateTime _lastResumeRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const _prefTouch = 'blink_touch_enabled';
  static const _prefIdleAnims = 'blink_idle_anims_enabled';
  static const _prefBuzzer = 'blink_buzzer_enabled';
  static const _prefBrightness = 'blink_display_brightness';
  static const _prefSensitivity = 'blink_touch_sensitivity';

  /// Loads the locally persisted robot preferences so the Settings switches show
  /// the user's real choices instead of hardcoded `true`s.
  Future<void> _loadLocalPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _capacitiveTouchEnabled = prefs.getBool(_prefTouch) ?? true;
    _idleAnimationsEnabled = prefs.getBool(_prefIdleAnims) ?? true;
    _buzzerEnabled = prefs.getBool(_prefBuzzer) ?? true;
    _displayBrightness =
        (prefs.getInt(_prefBrightness) ?? defaultBrightness).clamp(0, 255);
    _touchSensitivity =
        (prefs.getInt(_prefSensitivity) ?? defaultSensitivity).clamp(0, 2);
    notifyListeners();
  }

  Future<void> _persistPreference(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (error) {
      debugPrint('[BLINK] could not persist $key: $error');
    }
  }

  Future<void> _persistInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (error) {
      debugPrint('[BLINK] could not persist $key: $error');
    }
  }

  // ── Connection State ─────────────────────────────────────────
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  String get deviceName => _ble.connectedName;
  String? get bleStatusMessage => _ble.statusMessage;

  /// True while the manager is retrying a dropped link on its own, so the UI can
  /// show "reconnecting" instead of a bare "disconnected".
  bool get isReconnecting => _ble.isReconnecting;
  bool get hasKnownRobot => _ble.hasKnownDevice;

  Future<void> reconnect() => _ble.reconnect();
  void cancelFirmwareUpdate() => _ble.cancelFirmwareUpdate();

  int _batteryLevel = 0;
  int get batteryLevel => _batteryLevel;

  // ── Toggle States ────────────────────────────────────────────
  bool _capacitiveTouchEnabled = true;
  bool get capacitiveTouchEnabled => _capacitiveTouchEnabled;
  bool _idleAnimationsEnabled = true;
  bool get idleAnimationsEnabled => _idleAnimationsEnabled;
  bool _buzzerEnabled = true;
  bool get buzzerEnabled => _buzzerEnabled;

  // ── Display brightness ───────────────────────────────────────
  //
  // Stored as the raw OLED contrast the firmware wants (`BRIGHT:<0-255>`) so
  // there is no index-to-value table to keep in sync on two sides of the link.
  // The panel has no ambient-light sensor, so this is a manual setting.
  static const List<int> brightnessLevels = <int>[96, 176, 255];
  static const int defaultBrightness = 255;

  int _displayBrightness = defaultBrightness;
  int get displayBrightness => _displayBrightness;

  /// Human-readable name for a contrast value — the nearest of
  /// [brightnessLevels], so a value restored from an older build still labels.
  static String brightnessLabel(int contrast) {
    if (contrast <= (brightnessLevels[0] + brightnessLevels[1]) ~/ 2) {
      return 'dim';
    }
    if (contrast <= (brightnessLevels[1] + brightnessLevels[2]) ~/ 2) {
      return 'medium';
    }
    return 'bright';
  }

  /// Steps to the next brightness level, wrapping. One tile, no slider: the
  /// OLED only has three levels worth distinguishing by eye.
  Future<void> cycleDisplayBrightness() {
    // Start from whichever level is closest to the stored value so a contrast
    // that did not come from this list still cycles somewhere sensible.
    var nearest = 0;
    for (var i = 1; i < brightnessLevels.length; i++) {
      if ((brightnessLevels[i] - _displayBrightness).abs() <
          (brightnessLevels[nearest] - _displayBrightness).abs()) {
        nearest = i;
      }
    }
    return setDisplayBrightness(
      brightnessLevels[(nearest + 1) % brightnessLevels.length],
    );
  }

  Future<void> setDisplayBrightness(int contrast) async {
    _displayBrightness = contrast.clamp(0, 255);
    notifyListeners();
    unawaited(_persistInt(_prefBrightness, _displayBrightness));
    await _ble.sendCommand('BRIGHT:$_displayBrightness');
  }

  // ── Touch sensitivity ────────────────────────────────────────
  //
  // `PIN_TOUCH` is a digital input, so there is no analog threshold to move.
  // What the firmware actually varies is the debounce window (60 / 25 / 10 ms),
  // which is what decides whether a glancing brush registers as a tap.
  static const int defaultSensitivity = 1; // 0 = low, 1 = medium, 2 = high
  static const List<String> _sensitivityTokens = <String>['LOW', 'MED', 'HIGH'];

  int _touchSensitivity = defaultSensitivity;
  int get touchSensitivity => _touchSensitivity;

  static String sensitivityLabel(int level) => switch (level) {
        0 => 'low',
        2 => 'high',
        _ => 'medium',
      };

  Future<void> cycleTouchSensitivity() =>
      setTouchSensitivity((_touchSensitivity + 1) % 3);

  Future<void> setTouchSensitivity(int level) async {
    _touchSensitivity = level.clamp(0, 2);
    notifyListeners();
    unawaited(_persistInt(_prefSensitivity, _touchSensitivity));
    await _ble.sendCommand('SENS:${_sensitivityTokens[_touchSensitivity]}');
  }

  // ── Expression / stopwatch ───────────────────────────────────
  String _currentExpression = 'Idle Core';
  String get currentExpression => _currentExpression;

  int _selectedExpressionPack = -1;
  int get selectedExpressionPack => _selectedExpressionPack;

  RobotAnimationSnapshot? get robotAnimation => _ble.robotAnimation;

  // ── Firmware update ──────────────────────────────────────────
  bool get hasPendingFirmwareUpdate => _firmware.hasPendingUpdate;
  String? get pendingFirmwareFileName => _firmware.fileName;
  String? get firmwareUpdateError => _firmware.error;
  String? get installedFirmwareVersion => _ble.firmwareVersion;
  bool get firmwareUpdateSupported => _ble.firmwareUpdateSupported;
  bool get firmwareUpdateInProgress => _ble.firmwareUpdateInProgress;
  double get firmwareUpdateProgress => _ble.firmwareUpdateProgress;
  String? get firmwareUpdateMessage => _ble.firmwareUpdateMessage;
  bool get githubFirmwareConfigured => true;
  bool get checkingGitHubFirmware => _firmware.isCheckingGitHub;
  bool get isDownloadingFirmware => _firmware.isDownloadingFirmware;
  double get firmwareDownloadProgress => _firmware.downloadProgress;
  bool get hasGitHubFirmware => _firmware.hasGitHubFirmware;
  String? get githubFirmwareVersion => _firmware.githubVersion;
  String? get githubFirmwareAssetName => _firmware.githubAssetName;
  String? get githubFirmwareError => _firmware.githubError;
  String? get robotFirmwareVersion => _firmware.robotVersion;
  bool get isFirmwareUpdateAvailable => _firmware.isUpdateAvailable;

  // ── App self-update ──────────────────────────────────────────
  bool get isAppUpdateAvailable => _firmware.isAppUpdateAvailable;
  bool get isDownloadingApk => _firmware.isDownloadingApk;
  double get apkDownloadProgress => _firmware.apkDownloadProgress;
  bool get hasDownloadedApk => _firmware.hasDownloadedApk;
  String? get appUpdateError => _firmware.appUpdateError;
  String? get pendingApkPath => _firmware.pendingApkPath;

  Future<void> downloadAppUpdate() => _firmware.downloadAppUpdate();

  // ── Weather & Mood Sync ────────────────────────────────────────
  WeatherMoodData? get weatherMoodData => _weatherMood.currentMoodData;
  bool get isWeatherSyncing => _weatherMood.isSyncing;
  String? get weatherSyncError => _weatherMood.lastError;
  DateTime? get lastWeatherSyncTime => _weatherMood.lastSyncTime;
  bool get weatherAutoSyncEnabled => _weatherMood.autoSyncEnabled;

  Future<void> forceWeatherSync() => _weatherMood.forceSync();
  void setWeatherAutoSync(bool enabled) => _weatherMood.setAutoSync(enabled);

  bool get isRobotSynced =>
      _connectionState == BleConnectionState.connected &&
      _ble.robotAnimation != null;

  // ── Focus Timer State ────────────────────────────────────────
  bool _timerRunning = false;
  bool get timerRunning => _timerRunning;

  int _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
  int get timerSeconds => _timerSeconds;

  Timer? _timer;
  Timer? _stopwatchSync;

  /// Formatted timer string "MM:SS"
  String get timerDisplay {
    final minutes = (_timerSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_timerSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _onBleChanged() {
    final wasConnected = _connectionState == BleConnectionState.connected;
    final oldState = _connectionState;
    final oldExpression = _currentExpression;
    final oldBattery = _batteryLevel;

    if (_ble.isScanning) {
      _connectionState = BleConnectionState.scanning;
    } else if (_ble.isConnected) {
      _connectionState = BleConnectionState.connected;
    } else {
      _connectionState = BleConnectionState.disconnected;
    }

    final snapshot = _ble.robotAnimation;
    if (snapshot != null) {
      _currentExpression = snapshot.expressionLabel;
      if (snapshot.batteryPercent > 0) {
        _batteryLevel = snapshot.batteryPercent;
      }
    } else if (_connectionState == BleConnectionState.disconnected) {
      _currentExpression = 'Idle Core';
    }

    _firmware.updateRobotVersion(_ble.firmwareVersion);

    // Refresh GitHub release once per connection, not on every BLE notification.
    final justConnected =
        !wasConnected && _connectionState == BleConnectionState.connected;
    if (justConnected && !_ble.firmwareUpdateInProgress) {
      unawaited(_firmware.checkGitHubRelease());
      // The robot boots with touch/animations/buzzer all enabled, so after any
      // reboot (including the post-OTA one) it has forgotten the user's
      // choices.  Replay them.
      unawaited(_pushLocalPreferencesToRobot());
    }

    // Fire local notification when we just connected and an update exists.
    if (_connectionState == BleConnectionState.connected && _firmware.isUpdateAvailable) {
      unawaited(_firmware.notifyUpdateAvailable());
    }

    // Only rebuild the UI when something actually changed, avoiding
    // unnecessary rebuilds from the 10 Hz state notify stream.
    final changed = oldState != _connectionState ||
        oldExpression != _currentExpression ||
        oldBattery != _batteryLevel ||
        justConnected;
    if (changed) {
      notifyListeners();
    }
  }

  void _onFirmwareChanged() {
    // If GitHub check finishes after connect and shows an update, notify.
    if (_connectionState == BleConnectionState.connected &&
        _firmware.isUpdateAvailable) {
      unawaited(_firmware.notifyUpdateAvailable());
    }
    notifyListeners();
  }

  Future<void> _requestPermissionsOnStartup() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) return;
    // Requested one at a time and individually guarded: permission_handler
    // throws if no Activity is attached, and a throw on the first request used
    // to skip the remaining three.
    for (final permission in <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
      Permission.notification,
    ]) {
      try {
        await permission.request();
      } catch (error) {
        debugPrint('[BLINK] permission $permission failed: $error');
      }
    }
  }

  /// Replays the locally stored robot settings after a (re)connect.
  Future<void> _pushLocalPreferencesToRobot() async {
    if (!_ble.isConnected) return;
    await _ble.sendCommand(_capacitiveTouchEnabled ? 'TOUCH:ON' : 'TOUCH:OFF');
    await _ble.sendCommand(_idleAnimationsEnabled ? 'ANIM:ON' : 'ANIM:OFF');
    await _ble.sendCommand(_buzzerEnabled ? 'BUZZER:ON' : 'BUZZER:OFF');
    await _ble.sendCommand('SENS:${_sensitivityTokens[_touchSensitivity]}');
    await _ble.sendCommand('BRIGHT:$_displayBrightness');
    // The robot loses the weather mood across a reboot too, and waiting up to
    // 30 minutes for the next tick left it stuck on a neutral face.
    await _weatherMood.pushMoodToRobot();
  }

  // ── Connection Methods ───────────────────────────────────────

  Future<void> scanAndConnect() async {
    await _ble.startScanAndConnect();
  }

  Future<void> disconnect() async {
    await _ble.disconnect();
  }

  Future<void> syncTimeNow() async {
    await _ble.syncTime();
  }

  void setConnectionState(BleConnectionState state) {
    _connectionState = state;
    notifyListeners();
  }

  void updateBattery(int level) {
    _batteryLevel = level.clamp(0, 100);
    notifyListeners();
  }

  // ── Toggle Methods ───────────────────────────────────────────

  Future<void> toggleCapacitiveTouch() async {
    _capacitiveTouchEnabled = !_capacitiveTouchEnabled;
    notifyListeners();
    unawaited(_persistPreference(_prefTouch, _capacitiveTouchEnabled));
    await _ble.sendCommand(
      _capacitiveTouchEnabled ? 'TOUCH:ON' : 'TOUCH:OFF',
    );
  }

  Future<void> setIdleAnimations(bool enabled) async {
    _idleAnimationsEnabled = enabled;
    notifyListeners();
    unawaited(_persistPreference(_prefIdleAnims, enabled));
    await _ble.sendCommand(enabled ? 'ANIM:ON' : 'ANIM:OFF');
  }

  /// Mutes or unmutes the robot's passive buzzer.  The choice is persisted
  /// locally and replayed on every reconnect, because the robot boots unmuted.
  Future<void> setBuzzerEnabled(bool enabled) async {
    _buzzerEnabled = enabled;
    notifyListeners();
    unawaited(_persistPreference(_prefBuzzer, enabled));
    await _ble.sendCommand(enabled ? 'BUZZER:ON' : 'BUZZER:OFF');
  }

  Future<void> toggleBuzzer() => setBuzzerEnabled(!_buzzerEnabled);

  // ── Expression / sound ───────────────────────────────────────

  /// Maps a human-readable expression label to one of the four tokens the
  /// firmware's `EXP:` handler understands.
  static String? _expressionToken(String label) {
    final key = label.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');
    if (key.contains('HAPPY') ||
        key.contains('JOY') ||
        key.contains('EXCITED') ||
        key.contains('SMILE')) {
      return 'HAPPY';
    }
    if (key.contains('SAD') ||
        key.contains('GLOOM') ||
        key.contains('CRY') ||
        key.contains('TEAR')) {
      return 'SAD';
    }
    if (key.contains('ANGRY') ||
        key.contains('MAD') ||
        key.contains('RAGE') ||
        key.contains('GRUMP')) {
      return 'ANGRY';
    }
    if (key.contains('LOVE') || key.contains('HEART')) return 'LOVE';
    return null;
  }

  /// Sets the displayed expression.
  ///
  /// The command prefix is `EXP:` — it was previously `EXPR:`, which no
  /// firmware handler matched, so the whole expression UI was a silent no-op.
  Future<void> setExpression(String expression) async {
    _currentExpression = expression;
    notifyListeners();
    final token = _expressionToken(expression);
    if (token == null) {
      // Not one of the four hardware expressions — return to the idle face.
      await _ble.sendCommand('IDLE');
      return;
    }
    await _ble.sendCommand('EXP:$token');
  }

  /// Send an expression command to the robot (e.g., HAPPY, SAD, ANGRY, LOVE).
  Future<void> sendExpression(String expressionName) async {
    final token = _expressionToken(expressionName) ?? expressionName.toUpperCase();
    await _ble.sendCommand('EXP:$token');
  }

  void toggleExpressionPack(int index) {
    _selectedExpressionPack = _selectedExpressionPack == index ? -1 : index;
    notifyListeners();
  }

  Future<void> playSoundTest() => _ble.sendCommand('SOUND:TEST');

  Future<void> installFirmwareUpdate() => _firmware.installPendingUpdate(_ble);

  Future<void> checkGitHubFirmware() => _firmware.checkGitHubRelease();

  Future<void> downloadGitHubFirmware() => _firmware.downloadGitHubFirmware();

  // ── Draw mode ────────────────────────────────────────────────

  Future<void> enterDrawMode() async {
    await _ble.sendCommand('DRAW');
  }

  Future<void> exitDrawMode() async {
    await _ble.sendCommand('IDLE');
  }

  Future<void> clearDrawing() async {
    await _ble.sendCommand('CLEAR');
  }

  // ── Focus Timer Methods ──────────────────────────────────────

  Future<void> startTimer() async {
    if (_timerRunning) return;
    _timerRunning = true;
    notifyListeners();

    await _ble.sendCommand('FOCUS:$timerDisplay');
    _startStopwatchSync();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerSeconds > 0) {
        _timerSeconds--;
        notifyListeners();
      } else {
        completeTimer();
      }
    });
  }

  Future<void> completeTimer() async {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
    notifyListeners();
    await _ble.sendCommand('FOCUS:DONE');
  }

  void pauseTimer() {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    notifyListeners();
    _ble.sendCommand('SW:$timerDisplay');
  }

  Future<void> resetTimer() async {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
    notifyListeners();
    await _ble.sendCommand('IDLE');
  }

  Future<void> stopTimer() async {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
    notifyListeners();
    await _ble.sendCommand('IDLE');
  }

  void _startStopwatchSync() {
    _stopwatchSync?.cancel();
    _stopwatchSync = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_timerRunning) {
        _ble.sendCommand('FOCUS:$timerDisplay');
      }
    });
  }

  // ── Reset ────────────────────────────────────────────────────

  /// Resets the robot's runtime state only.  Local app data is untouched.
  Future<void> factoryReset() async {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
    _batteryLevel = 0;
    _capacitiveTouchEnabled = true;
    _idleAnimationsEnabled = true;
    _buzzerEnabled = true;
    _displayBrightness = defaultBrightness;
    _touchSensitivity = defaultSensitivity;
    _currentExpression = 'Idle Core';
    _selectedExpressionPack = -1;
    notifyListeners();

    unawaited(_persistPreference(_prefTouch, true));
    unawaited(_persistPreference(_prefIdleAnims, true));
    unawaited(_persistPreference(_prefBuzzer, true));
    unawaited(_persistInt(_prefBrightness, defaultBrightness));
    unawaited(_persistInt(_prefSensitivity, defaultSensitivity));

    // Single RESET command: robot clears canvas, exits focus/draw,
    // re-enables touch, and replays the BLINK boot animation.
    await _ble.sendCommand('RESET');
  }

  /// Full reset from the app: drops the BLE link, clears every locally stored
  /// preference and cached update artefact, and tells the robot to reset too if
  /// it is still reachable.
  ///
  /// Used by Settings → Reset.  Returns once local state is clean; a failure to
  /// reach the robot does not prevent the local wipe.
  Future<void> resetEverything() async {
    // 1. Tell the robot first, while the link is still up.  Best effort.
    try {
      if (_ble.isConnected) await _ble.sendCommand('RESET');
    } catch (error) {
      debugPrint('[BLINK] robot reset command failed: $error');
    }

    // 2. Stop all local activity.
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;

    // 3. Drop the connection and forget the device.
    try {
      await _ble.forgetDevice();
    } catch (error) {
      debugPrint('[BLINK] disconnect during reset failed: $error');
    }

    // 4. Wipe persisted app state.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (error) {
      debugPrint('[BLINK] preference wipe failed: $error');
    }
    try {
      await _firmware.resetAll();
    } catch (error) {
      debugPrint('[BLINK] firmware state wipe failed: $error');
    }
    try {
      await _weatherMood.reset();
    } catch (error) {
      debugPrint('[BLINK] weather state wipe failed: $error');
    }

    // 5. Back to defaults in memory.
    _batteryLevel = 0;
    _capacitiveTouchEnabled = true;
    _idleAnimationsEnabled = true;
    _buzzerEnabled = true;
    _displayBrightness = defaultBrightness;
    _touchSensitivity = defaultSensitivity;
    _currentExpression = 'Idle Core';
    _selectedExpressionPack = -1;
    _connectionState = BleConnectionState.disconnected;
    _lastResumeRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ble.removeListener(_onBleChanged);
    _firmware.removeListener(_onFirmwareChanged);
    _weatherMood.removeListener(_onWeatherMoodChanged);
    _timer?.cancel();
    _stopwatchSync?.cancel();
    super.dispose();
  }
}
