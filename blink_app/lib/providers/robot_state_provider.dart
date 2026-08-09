import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';

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
    unawaited(_firmware.initialize());
    _onBleChanged();
    unawaited(_requestPermissionsOnStartup());
    unawaited(_initializeWeatherMood());
  }

  Future<void> _initializeWeatherMood() async {
    await _weatherMood.initialize();
    // Listen for weather mood changes
    _weatherMood.addListener(_onWeatherMoodChanged);
  }

  void _onWeatherMoodChanged() {
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_firmware.checkGitHubRelease());
      unawaited(_weatherMood.forceSync());
    }
  }

  final BleManager _ble;
  final FirmwareUpdateService _firmware;
  final WeatherMoodService _weatherMood;

  bool _connectedSinceLastGithubCheck = false;

  // ── Connection State ─────────────────────────────────────────
  BleConnectionState _connectionState = BleConnectionState.disconnected;
  BleConnectionState get connectionState => _connectionState;

  String get deviceName => _ble.connectedName;
  String? get bleStatusMessage => _ble.statusMessage;

  int _batteryLevel = 0;
  int get batteryLevel => _batteryLevel;

  // ── Toggle States ────────────────────────────────────────────
  bool _capacitiveTouchEnabled = true;
  bool get capacitiveTouchEnabled => _capacitiveTouchEnabled;
  bool _idleAnimationsEnabled = true;
  bool get idleAnimationsEnabled => _idleAnimationsEnabled;

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
      _connectedSinceLastGithubCheck = true;
      unawaited(_firmware.checkGitHubRelease());
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
    try {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.locationWhenInUse.request();
      await Permission.notification.request();
    } catch (_) {}
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
    await _ble.sendCommand(
      _capacitiveTouchEnabled ? 'TOUCH:ON' : 'TOUCH:OFF',
    );
  }

  Future<void> setIdleAnimations(bool enabled) async {
    _idleAnimationsEnabled = enabled;
    notifyListeners();
    await _ble.sendCommand(enabled ? 'ANIM:ON' : 'ANIM:OFF');
  }

  Future<void> setBuzzerEnabled(bool enabled) async {
    await _ble.sendCommand(enabled ? 'BUZZER:ON' : 'BUZZER:OFF');
  }

  // ── Expression / sound ───────────────────────────────────────

  Future<void> setExpression(String expression) async {
    _currentExpression = expression;
    notifyListeners();
    await _ble.sendCommand('EXPR:$expression');
  }

  /// Send an expression command to the robot (e.g., HAPPY, SAD, ANGRY, LOVE).
  Future<void> sendExpression(String expressionName) async {
    await _ble.sendCommand('EXP:$expressionName');
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

  // ── Factory Reset ────────────────────────────────────────────

  Future<void> factoryReset() async {
    _timerRunning = false;
    _timer?.cancel();
    _stopwatchSync?.cancel();
    _timerSeconds = BlinkConstants.pomodoroMinutes * 60;
    _batteryLevel = 0;
    _capacitiveTouchEnabled = true;
    _idleAnimationsEnabled = true;
    _currentExpression = 'Idle Core';
    _selectedExpressionPack = -1;
    notifyListeners();

    // Single RESET command: robot clears canvas, exits focus/draw,
    // re-enables touch, and replays the BLINK boot animation.
    await _ble.sendCommand('RESET');
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
