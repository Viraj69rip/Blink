import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/robot_animation_snapshot.dart';

/// BLE manager for the BLINK ESP32-C3 robot.
///
/// UUID map: keep these identical to firmware
/// `firmware/BLINK_Robot/BLINK_Robot.ino` (SERVICE_UUID / TIME_ / CMD_ / DRAW_ / OTA_).
///
/// Design notes worth preserving:
///
///  * **All GATT writes are serialized** through [_enqueue].  Four independent
///    producers (the 1 Hz focus-timer sync, the 1 min weather/time sync, the
///    drawing canvas, and the OTA transfer) used to race each other onto the
///    same link, which interleaved command bytes into the firmware stream and
///    stalled OTA transfers.
///  * **OTA takes an exclusive lock.**  While a firmware transfer is running,
///    every non-OTA write is dropped rather than queued, so nothing can inject
///    a `MOOD:` or `FOCUS:` packet into the middle of a flash image.
///  * **The post-OTA disconnect is a success, not a failure.**  The robot
///    reboots as soon as it has flashed the image, which tears the link down
///    before the app can read a reply.  [installFirmware] treats a disconnect
///    that follows `OTA:SUCCESS` (or a completed byte count) as a normal end.
class BleManager extends ChangeNotifier {
  BleManager._();
  static final BleManager instance = BleManager._();

  // ── GATT map (must match ESP32 firmware) ─────────────────────
  static const String deviceName = 'BLINK_C3';
  static const String serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const String timeCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const String commandCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
  static const String drawCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';
  static const String stateCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ab';
  static const String otaControlCharUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26ac';
  static const String otaDataCharUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26ad';
  static const String otaStatusCharUuid =
      'beb5483e-36e1-4688-b7f5-ea07361b26ae';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _timeChar;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _drawChar;
  BluetoothCharacteristic? _stateChar;
  BluetoothCharacteristic? _otaControlChar;
  BluetoothCharacteristic? _otaDataChar;
  BluetoothCharacteristic? _otaStatusChar;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _stateSub;
  StreamSubscription<List<int>>? _otaStatusSub;

  bool _scanning = false;
  bool _connected = false;
  String? _statusMessage;
  RobotAnimationSnapshot? _robotAnimation;
  String? _firmwareVersion;
  bool _firmwareUpdateInProgress = false;
  double _firmwareUpdateProgress = 0;
  String? _firmwareUpdateMessage;
  Completer<void>? _otaWaiter;

  /// Set by the OTA status notify handler.  Polled by the transfer loop so a
  /// firmware-side abort stops the transfer immediately instead of the app
  /// blasting the remaining image at a device that already gave up.
  String? _otaFatalError;
  bool _otaSucceeded = false;
  bool _otaExclusive = false;

  /// Serializes every GATT operation.
  Future<void> _writeChain = Future<void>.value();

  // ── Auto-reconnect ───────────────────────────────────────────
  DeviceIdentifier? _lastRemoteId;
  bool _userInitiatedDisconnect = false;
  bool _reconnecting = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const int _maxReconnectAttempts = 6;

  bool get isScanning => _scanning;
  bool get isConnected => _connected;
  bool get isReconnecting => _reconnecting;
  String? get statusMessage => _statusMessage;
  RobotAnimationSnapshot? get robotAnimation => _robotAnimation;
  String? get firmwareVersion => _firmwareVersion;
  bool get firmwareUpdateSupported =>
      _otaControlChar != null && _otaDataChar != null && _otaStatusChar != null;
  bool get firmwareUpdateInProgress => _firmwareUpdateInProgress;
  double get firmwareUpdateProgress => _firmwareUpdateProgress;
  String? get firmwareUpdateMessage => _firmwareUpdateMessage;

  /// True once a device has been connected at least once this session, so the
  /// UI can offer "reconnect" instead of "scan".
  bool get hasKnownDevice => _lastRemoteId != null;

  String get connectedName {
    try {
      final device = _device;
      if (device != null && device.platformName.isNotEmpty) {
        return device.platformName;
      }
    } catch (_) {}
    return deviceName;
  }

  // ── Write serialization ──────────────────────────────────────

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _writeChain = _writeChain.then((_) async {
      if (completer.isCompleted) return;
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    // Never let a rejected link poison the chain for everyone behind it.
    _writeChain = _writeChain.catchError((Object _) {});
    return completer.future;
  }

  /// Waits until every queued GATT operation has drained.
  Future<void> _drainQueue() => _enqueue(() async {});

  // ── Permissions ──────────────────────────────────────────────

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final scan = await Permission.bluetoothScan.request();
      final connect = await Permission.bluetoothConnect.request();
      // Pre-Android 12 scan often still needs location.
      await Permission.locationWhenInUse.request();
      return scan.isGranted && connect.isGranted;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return true; // CoreBluetooth prompts system dialogs as needed
    }

    return true;
  }

  // ── Scan & connect ───────────────────────────────────────────

  Future<void> startScanAndConnect({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_connected || _scanning) return;
    _userInitiatedDisconnect = false;
    _cancelReconnect();

    final ok = await _ensurePermissions();
    if (!ok) {
      _statusMessage = 'Bluetooth permission denied';
      notifyListeners();
      return;
    }

    if (await FlutterBluePlus.isSupported == false) {
      _statusMessage = 'BLE not supported on this device';
      notifyListeners();
      return;
    }

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      _statusMessage = 'Turn on Bluetooth';
      notifyListeners();
      return;
    }

    _scanning = true;
    _statusMessage = 'Scanning for $deviceName…';
    notifyListeners();

    final completer = Completer<BluetoothDevice?>();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        final hasService = r.advertisementData.serviceUuids.any(
          (u) => u.str.toLowerCase() == serviceUuid.toLowerCase(),
        );
        if (name == deviceName || hasService) {
          if (!completer.isCompleted) completer.complete(r.device);
          return;
        }
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (e) {
      _scanning = false;
      _statusMessage = 'Scan failed: $e';
      notifyListeners();
      await _scanSub?.cancel();
      _scanSub = null;
      return;
    }

    BluetoothDevice? found;
    try {
      found = await completer.future.timeout(timeout);
    } on TimeoutException {
      found = null;
    }

    await stopScan();

    if (found == null) {
      _statusMessage = 'No BLINK robot found';
      notifyListeners();
      return;
    }

    await connect(found);
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    _scanning = false;
    notifyListeners();
  }

  Future<void> connect(BluetoothDevice device) async {
    _statusMessage = 'Connecting…';
    _userInitiatedDisconnect = false;
    notifyListeners();

    _device = device;
    _lastRemoteId = device.remoteId;
    _firmwareVersion = null;
    await _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionStateChanged);

    try {
      await device.connect(timeout: const Duration(seconds: 12));
      try {
        // Bigger MTU is the single biggest lever on OTA duration: chunk size is
        // derived from it below.  connect() already asks for 512 on Android;
        // this is a belt-and-braces retry that is safe to fail.
        await device.requestMtu(512);
      } catch (_) {}

      final services = await device.discoverServices();
      for (final service in services) {
        if (service.uuid.str.toLowerCase() != serviceUuid.toLowerCase()) {
          continue;
        }
        for (final c in service.characteristics) {
          final id = c.uuid.str.toLowerCase();
          if (id == timeCharUuid.toLowerCase()) _timeChar = c;
          if (id == commandCharUuid.toLowerCase()) _cmdChar = c;
          if (id == drawCharUuid.toLowerCase()) _drawChar = c;
          if (id == stateCharUuid.toLowerCase()) _stateChar = c;
          if (id == otaControlCharUuid.toLowerCase()) _otaControlChar = c;
          if (id == otaDataCharUuid.toLowerCase()) _otaDataChar = c;
          if (id == otaStatusCharUuid.toLowerCase()) _otaStatusChar = c;
        }
      }

      if (_timeChar == null ||
          _cmdChar == null ||
          _drawChar == null ||
          _stateChar == null) {
        // Do NOT leave a zombie "connected" state here: the connectionState
        // stream has already flipped _connected to true, so returning without
        // tearing the link down left the UI permanently claiming a connection
        // whose writes all silently no-op.
        _statusMessage = 'GATT characteristics missing — check UUIDs';
        notifyListeners();
        await disconnect();
        return;
      }

      _connected = true;
      _reconnectAttempt = 0;
      _reconnecting = false;
      _statusMessage = 'Connected';
      notifyListeners();

      await _subscribeRobotState();
      await _subscribeOtaStatus();

      // Sync phone time immediately so the robot RTC works offline later.
      await syncTime();
    } catch (e) {
      _statusMessage = 'Connect failed: $e';
      _connected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _onConnectionStateChanged(BluetoothConnectionState s) {
    final nowConnected = s == BluetoothConnectionState.connected;
    if (nowConnected == _connected) return;
    _connected = nowConnected;

    if (!_connected) {
      _timeChar = null;
      _cmdChar = null;
      _drawChar = null;
      _stateChar = null;
      _otaControlChar = null;
      _otaDataChar = null;
      _otaStatusChar = null;
      _robotAnimation = null;
      unawaited(_stateSub?.cancel());
      unawaited(_otaStatusSub?.cancel());
      _stateSub = null;
      _otaStatusSub = null;

      if (_firmwareUpdateInProgress) {
        // Expected: the robot reboots the moment it finishes flashing.
        _statusMessage = 'BLINK is restarting…';
        final waiter = _otaWaiter;
        if (_otaSucceeded && waiter != null && !waiter.isCompleted) {
          waiter.complete();
        }
      } else {
        _statusMessage = 'Disconnected';
        _scheduleReconnect();
      }
    }
    notifyListeners();
  }

  // ── Auto-reconnect ───────────────────────────────────────────

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnecting = false;
    _reconnectAttempt = 0;
  }

  /// Reconnects with exponential backoff (1s, 2s, 4s … capped at 30s).
  ///
  /// Skipped for user-initiated disconnects and while an OTA is running — the
  /// post-flash reboot is handled explicitly by [installFirmware].
  void _scheduleReconnect() {
    if (_userInitiatedDisconnect) return;
    if (_firmwareUpdateInProgress) return;
    if (_lastRemoteId == null) return;
    if (_reconnectTimer != null) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _reconnecting = false;
      _statusMessage = 'Disconnected — tap to reconnect';
      notifyListeners();
      return;
    }

    final delaySeconds = math.min(30, 1 << _reconnectAttempt);
    _reconnectAttempt++;
    _reconnecting = true;
    _statusMessage = 'Reconnecting to BLINK…';
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_connected || _userInitiatedDisconnect) {
        _cancelReconnect();
        return;
      }
      final device = _device;
      if (device == null) {
        _cancelReconnect();
        return;
      }
      try {
        await connect(device);
      } catch (error) {
        debugPrint('[BLE] reconnect attempt failed: $error');
        _scheduleReconnect();
      }
    });
  }

  /// Reconnects to the most recently used robot without a fresh scan.
  Future<void> reconnect() async {
    final device = _device;
    _userInitiatedDisconnect = false;
    _cancelReconnect();
    if (device == null) {
      await startScanAndConnect();
      return;
    }
    await connect(device);
  }

  // ── Commands ─────────────────────────────────────────────────

  /// Unix timestamp in seconds → Time Sync characteristic.
  Future<void> syncTime([DateTime? when]) async {
    final dt = when ?? DateTime.now();
    final unixSec = dt.millisecondsSinceEpoch ~/ 1000;
    await _write(_timeChar, unixSec.toString());
  }

  /// Command strings: FOCUS, IDLE, DRAW, CLEAR, SW:12:34, TOUCH:ON…
  Future<void> sendCommand(String command) async {
    await _write(_cmdChar, command);
  }

  /// Draw line segment mapped to OLED pixels: "X1,Y1,X2,Y2".
  ///
  /// Always a *segment*, never a bare point — the firmware rasterises the span
  /// with Bresenham so strokes come out as connected lines.
  Future<void> sendDrawLine(int x1, int y1, int x2, int y2) async {
    await _write(_drawChar, '$x1,$y1,$x2,$y2', withoutResponse: true);
  }

  // ── Notifications ────────────────────────────────────────────

  Future<void> _subscribeRobotState() async {
    await _stateSub?.cancel();
    _stateSub = null;
    final char = _stateChar;
    if (char == null) return;

    try {
      await char.setNotifyValue(true);
      _stateSub = char.onValueReceived.listen((data) {
        final parsed = RobotAnimationSnapshot.tryParse(_decode(data));
        if (parsed != null) {
          _robotAnimation = parsed;
          notifyListeners();
        }
      });

      // Seed the live preview immediately instead of waiting for the first notify.
      try {
        final initial = await char.read();
        final parsed = RobotAnimationSnapshot.tryParse(_decode(initial));
        if (parsed != null) {
          _robotAnimation = parsed;
          notifyListeners();
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('[BLE] state notify subscribe failed: $e');
    }
  }

  Future<void> _subscribeOtaStatus() async {
    await _otaStatusSub?.cancel();
    _otaStatusSub = null;
    final char = _otaStatusChar;
    if (char == null) return;

    try {
      await char.setNotifyValue(true);
      _otaStatusSub = char.onValueReceived.listen((data) {
        _handleOtaStatus(_decode(data));
      });
      final initial = await char.read();
      _handleOtaStatus(_decode(initial));
      await _writeFirmwareControl('VERSION');
    } catch (e) {
      debugPrint('[BLE] OTA status subscribe failed: $e');
    }
  }

  /// Lenient UTF-8 decode — a malformed notify payload must never throw inside
  /// a stream listener, where it would become an unhandled zone error.
  static String _decode(List<int> data) {
    try {
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  void _handleOtaStatus(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return;

    if (value.startsWith('VERSION:')) {
      _firmwareVersion = value.substring('VERSION:'.length);
    } else if (value == 'OTA:READY') {
      _firmwareUpdateMessage = 'Transferring firmware…';
      _completeOtaWaiter();
    } else if (value.startsWith('OTA:PROGRESS:')) {
      final parts = value.split(':');
      if (parts.length == 4) {
        final received = int.tryParse(parts[2]) ?? 0;
        final total = int.tryParse(parts[3]) ?? 1;
        _firmwareUpdateProgress = (received / total).clamp(0.0, 1.0);
        _firmwareUpdateMessage =
            'Installing ${(100 * _firmwareUpdateProgress).round()}%';
      }
    } else if (value == 'OTA:SUCCESS') {
      _otaSucceeded = true;
      _firmwareUpdateProgress = 1;
      _firmwareUpdateMessage = 'Installed — BLINK is restarting';
      _completeOtaWaiter();
    } else if (value.startsWith('OTA:ERROR:')) {
      final reason = value.substring('OTA:ERROR:'.length);
      _firmwareUpdateMessage = 'Update failed: $reason';
      // Latched, because nobody is awaiting _otaWaiter during the transfer
      // loop — completeError there would be swallowed by the timeout handler.
      _otaFatalError = reason;
      final waiter = _otaWaiter;
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(StateError('Update failed: $reason'));
      }
    } else if (value.startsWith('OTA:FLASHING:')) {
      final pct = int.tryParse(value.substring('OTA:FLASHING:'.length)) ?? 0;
      _firmwareUpdateMessage = 'Flashing $pct%';
      _firmwareUpdateProgress = (pct / 100).clamp(0.0, 1.0);
    }
    notifyListeners();
  }

  void _completeOtaWaiter() {
    final waiter = _otaWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  // ── OTA ──────────────────────────────────────────────────────

  /// Streams [firmware] to the robot over BLE and waits for it to flash.
  ///
  /// Cancellable via [cancelFirmwareUpdate].
  Future<void> installFirmware(Uint8List firmware) async {
    final control = _otaControlChar;
    final data = _otaDataChar;
    final device = _device;
    if (!_connected || control == null || data == null || device == null) {
      throw StateError(
          'Connect to a BLINK robot with firmware update support first.');
    }
    if (firmware.isEmpty) {
      throw ArgumentError.value(firmware, 'firmware', 'Firmware file is empty.');
    }
    if (_firmwareUpdateInProgress) {
      throw StateError('A firmware update is already running.');
    }

    _firmwareUpdateInProgress = true;
    _firmwareUpdateProgress = 0;
    _firmwareUpdateMessage = 'Preparing update…';
    _otaFatalError = null;
    _otaSucceeded = false;
    _otaCancelled = false;
    notifyListeners();

    // Drain anything already queued, then lock the link so no background timer
    // can inject a command byte into the firmware image.
    await _drainQueue();
    _otaExclusive = true;

    // The robot's OTA data characteristic is written WITH a response.  That is
    // deliberate: the ATT response is only sent after the firmware has written
    // the chunk to flash, which gives free end-to-end flow control.  Using
    // write-without-response here overran the receiver and silently dropped
    // packets, so the transfer always ended in "incomplete" — and the firmware
    // did not even declare WRITE_NR, so every ATT Write Command was discarded.
    final negotiatedMtu = device.mtuNow;
    final chunkSize = (negotiatedMtu - 3).clamp(20, 512).toInt();

    try {
      _otaWaiter = Completer<void>();
      await _otaWrite(control, utf8.encode('BEGIN:${firmware.length}'));
      await _otaWaiter!.future.timeout(const Duration(seconds: 15));

      for (var offset = 0; offset < firmware.length; offset += chunkSize) {
        if (_otaCancelled) {
          throw StateError('Update cancelled.');
        }
        final fatal = _otaFatalError;
        if (fatal != null) {
          throw StateError('BLINK rejected the update: $fatal');
        }
        if (!_connected) {
          throw StateError('Connection lost during firmware transfer.');
        }

        final end = math.min(offset + chunkSize, firmware.length);
        // sublistView is a *view*, not a copy — the old sublist() allocated a
        // fresh Uint8List per chunk (thousands of allocations per image).
        final view = Uint8List.sublistView(firmware, offset, end);
        try {
          await data
              .write(view, withoutResponse: false)
              .timeout(const Duration(seconds: 10));
        } catch (e) {
          _firmwareUpdateMessage = 'Write failed at byte $offset: $e';
          notifyListeners();
          rethrow;
        }

        _firmwareUpdateProgress = end / firmware.length;
        _notifyTransferProgress();
      }

      _firmwareUpdateProgress = 1;
      _firmwareUpdateMessage = 'Verifying…';
      notifyListeners();

      _otaWaiter = Completer<void>();
      await _otaWrite(control, utf8.encode('END'));
      try {
        await _otaWaiter!.future.timeout(const Duration(seconds: 45));
      } on TimeoutException {
        // The robot may already have rebooted before the reply reached us.  If
        // the whole image went out and nothing reported an error, treat it as
        // installed rather than telling the user a successful flash failed.
        if (_otaFatalError != null) rethrow;
        _firmwareUpdateMessage = 'Installed — BLINK is restarting';
      }
    } catch (error) {
      // Only try to abort if the link is still alive; a post-reboot abort just
      // produces a second, more confusing error.
      if (_connected && !_otaSucceeded) {
        try {
          await _otaWrite(control, utf8.encode('ABORT'));
        } catch (_) {}
      }
      if (_otaSucceeded) {
        // Reboot raced the reply — the flash itself succeeded.
        _firmwareUpdateMessage = 'Installed — BLINK is restarting';
      } else {
        rethrow;
      }
    } finally {
      _otaWaiter = null;
      _otaExclusive = false;
      _firmwareUpdateInProgress = false;
      _lastTransferNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
      notifyListeners();
      // The robot is rebooting into the new image; give it a moment, then come
      // back automatically so the user sees the new version without fiddling.
      if (_otaSucceeded && !_userInitiatedDisconnect) {
        _reconnectAttempt = 0;
        Timer(const Duration(seconds: 4), () {
          if (!_connected) _scheduleReconnect();
        });
      }
    }
  }

  bool _otaCancelled = false;

  /// Aborts an in-flight firmware transfer.
  void cancelFirmwareUpdate() {
    if (!_firmwareUpdateInProgress) return;
    _otaCancelled = true;
    _firmwareUpdateMessage = 'Cancelling…';
    notifyListeners();
  }

  DateTime _lastTransferNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Coalesces transfer progress to ~10 Hz.  Notifying on every chunk rebuilt
  /// the whole tree thousands of times per image.
  void _notifyTransferProgress() {
    final now = DateTime.now();
    if (now.difference(_lastTransferNotifyAt) <
        const Duration(milliseconds: 100)) {
      return;
    }
    _lastTransferNotifyAt = now;
    _firmwareUpdateMessage =
        'Transferring ${(100 * _firmwareUpdateProgress).round()}%';
    notifyListeners();
  }

  /// OTA writes bypass [_enqueue] because [installFirmware] already holds the
  /// exclusive lock and drained the queue.
  Future<void> _otaWrite(BluetoothCharacteristic char, List<int> bytes) async {
    await char.write(bytes, withoutResponse: false);
  }

  Future<void> _writeFirmwareControl(String value) async {
    final char = _otaControlChar;
    if (!_connected || char == null) {
      throw StateError('Firmware update channel is unavailable.');
    }
    await _enqueue(() => char.write(utf8.encode(value), withoutResponse: false));
  }

  // ── Low-level write ──────────────────────────────────────────

  Future<void> _write(
    BluetoothCharacteristic? char,
    String value, {
    bool withoutResponse = true,
  }) async {
    if (!_connected || char == null) return;
    // Never interleave app chatter into a firmware image.
    if (_otaExclusive) return;

    // Only use write-without-response if the characteristic actually advertises
    // it.  The previous code always tried WNR first and blindly retried with a
    // response on failure, which doubled the round trip on every write and hid
    // real link errors.
    final useNoResponse = withoutResponse && char.properties.writeWithoutResponse;
    final bytes = utf8.encode(value);

    await _enqueue(() async {
      if (!_connected) return;
      try {
        await char
            .write(bytes, withoutResponse: useNoResponse)
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[BLE] write failed ($value): $e');
      }
    });
  }

  // ── Teardown ─────────────────────────────────────────────────

  Future<void> disconnect() async {
    _userInitiatedDisconnect = true;
    _cancelReconnect();
    await stopScan();
    await _connSub?.cancel();
    await _stateSub?.cancel();
    await _otaStatusSub?.cancel();
    _connSub = null;
    _stateSub = null;
    _otaStatusSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _timeChar = null;
    _cmdChar = null;
    _drawChar = null;
    _stateChar = null;
    _otaControlChar = null;
    _otaDataChar = null;
    _otaStatusChar = null;
    _robotAnimation = null;
    _connected = false;
    _otaExclusive = false;
    _firmwareUpdateInProgress = false;
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  /// Disconnects and forgets the device, so no auto-reconnect is attempted.
  /// Used by the in-app reset flow.
  Future<void> forgetDevice() async {
    await disconnect();
    _device = null;
    _lastRemoteId = null;
    _firmwareVersion = null;
    _firmwareUpdateProgress = 0;
    _firmwareUpdateMessage = null;
    _statusMessage = null;
    notifyListeners();
  }
}
