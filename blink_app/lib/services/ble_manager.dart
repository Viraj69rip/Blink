import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/robot_animation_snapshot.dart';

/// BLE manager for the BLINK ESP32-C3 robot.
///
/// UUID remap: keep these identical to firmware
/// `firmware/BLINK_Robot/BLINK_Robot.ino` (#define SERVICE_UUID / TIME_ / CMD_ / DRAW_).
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

  bool get isScanning => _scanning;
  bool get isConnected => _connected;
  String? get statusMessage => _statusMessage;
  RobotAnimationSnapshot? get robotAnimation => _robotAnimation;
  String? get firmwareVersion => _firmwareVersion;
  bool get firmwareUpdateSupported =>
      _otaControlChar != null && _otaDataChar != null && _otaStatusChar != null;
  bool get firmwareUpdateInProgress => _firmwareUpdateInProgress;
  double get firmwareUpdateProgress => _firmwareUpdateProgress;
  String? get firmwareUpdateMessage => _firmwareUpdateMessage;
  String get connectedName => _device?.platformName.isNotEmpty == true
      ? _device!.platformName
      : deviceName;

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

  Future<void> startScanAndConnect({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_connected || _scanning) return;

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
    notifyListeners();

    _device = device;
    await _connSub?.cancel();
    _connSub = device.connectionState.listen((s) {
      _connected = s == BluetoothConnectionState.connected;
      if (!_connected) {
        _timeChar = null;
        _cmdChar = null;
        _drawChar = null;
        _stateChar = null;
        _otaControlChar = null;
        _otaDataChar = null;
        _otaStatusChar = null;
        _robotAnimation = null;
        _stateSub?.cancel();
        _otaStatusSub?.cancel();
        _stateSub = null;
        _otaStatusSub = null;
        _firmwareUpdateInProgress = false;
        _statusMessage = 'Disconnected';
      }
      notifyListeners();
    });

    try {
      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );
      try {
        await device.requestMtu(128);
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
        _statusMessage = 'GATT characteristics missing — check UUIDs';
        notifyListeners();
        return;
      }

      _connected = true;
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
    }
  }

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

  /// Draw line segment mapped to OLED pixels: "X1,Y1,X2,Y2"
  Future<void> sendDrawLine(int x1, int y1, int x2, int y2) async {
    await _write(_drawChar, '$x1,$y1,$x2,$y2', withoutResponse: true);
  }

  Future<void> _subscribeRobotState() async {
    await _stateSub?.cancel();
    _stateSub = null;
    final char = _stateChar;
    if (char == null) return;

    try {
      await char.setNotifyValue(true);
      _stateSub = char.onValueReceived.listen((data) {
        final parsed = RobotAnimationSnapshot.tryParse(utf8.decode(data));
        if (parsed != null) {
          _robotAnimation = parsed;
          notifyListeners();
        }
      });

      // Seed the live preview immediately instead of waiting for the first notify.
      try {
        final initial = await char.read();
        final parsed = RobotAnimationSnapshot.tryParse(utf8.decode(initial));
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
        _handleOtaStatus(utf8.decode(data));
      });
      final initial = await char.read();
      _handleOtaStatus(utf8.decode(initial));
      await _writeFirmwareControl('VERSION');
    } catch (e) {
      debugPrint('[BLE] OTA status subscribe failed: $e');
    }
  }

  void _handleOtaStatus(String raw) {
    final value = raw.trim();
    if (value.startsWith('VERSION:')) {
      _firmwareVersion = value.substring('VERSION:'.length);
    } else if (value == 'OTA:READY') {
      _firmwareUpdateMessage = 'Transferring firmware…';
      _otaWaiter?.complete();
      _otaWaiter = null;
    } else if (value.startsWith('OTA:PROGRESS:')) {
      final parts = value.split(':');
      if (parts.length == 4) {
        final received = int.tryParse(parts[2]) ?? 0;
        final total = int.tryParse(parts[3]) ?? 1;
        _firmwareUpdateProgress = (received / total).clamp(0.0, 1.0) as double;
        _firmwareUpdateMessage =
            'Installing ${(100 * _firmwareUpdateProgress).round()}%';
      }
    } else if (value == 'OTA:SUCCESS') {
      _firmwareUpdateProgress = 1;
      _firmwareUpdateMessage = 'Installed — BLINK is restarting';
      _otaWaiter?.complete();
      _otaWaiter = null;
    } else if (value.startsWith('OTA:ERROR:')) {
      _firmwareUpdateMessage = 'Update failed: ${value.substring(10)}';
      _otaWaiter?.completeError(StateError(_firmwareUpdateMessage ?? 'OTA error'));
      _otaWaiter = null;
    }
    notifyListeners();
  }

  Future<void> installFirmware(Uint8List firmware) async {
    final control = _otaControlChar;
    final data = _otaDataChar;
    final device = _device;
    if (!_connected || control == null || data == null || device == null) {
      throw StateError(
          'Connect to a BLINK robot with firmware update support first.');
    }
    if (firmware.isEmpty)
      throw ArgumentError.value(
          firmware, 'firmware', 'Firmware file is empty.');
    if (_firmwareUpdateInProgress)
      throw StateError('A firmware update is already running.');

    _firmwareUpdateInProgress = true;
    _firmwareUpdateProgress = 0;
    _firmwareUpdateMessage = 'Preparing update…';
    notifyListeners();

    try {
      _otaWaiter = Completer<void>();
      await _writeFirmwareControl('BEGIN:${firmware.length}');
      await _otaWaiter!.future.timeout(const Duration(seconds: 12));

      // A response write keeps chunks ordered. The size follows the negotiated
      // MTU, so it also works when a phone cannot negotiate a large MTU.
      final chunkSize = (device.mtuNow - 3).clamp(20, 180) as int;
      for (var offset = 0; offset < firmware.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, firmware.length) as int;
        await data.write(firmware.sublist(offset, end), withoutResponse: false);
        _firmwareUpdateProgress = end / firmware.length;
        _firmwareUpdateMessage =
            'Transferring ${(100 * _firmwareUpdateProgress).round()}%';
        notifyListeners();
      }

      _otaWaiter = Completer<void>();
      await _writeFirmwareControl('END');
      await _otaWaiter!.future.timeout(const Duration(seconds: 18));
    } catch (_) {
      try {
        await _writeFirmwareControl('ABORT');
      } catch (_) {}
      rethrow;
    } finally {
      _otaWaiter = null;
      _firmwareUpdateInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _writeFirmwareControl(String value) async {
    final char = _otaControlChar;
    if (!_connected || char == null) {
      throw StateError('Firmware update channel is unavailable.');
    }
    await char.write(utf8.encode(value), withoutResponse: false);
  }

  Future<void> _write(
    BluetoothCharacteristic? char,
    String value, {
    bool withoutResponse = true,
  }) async {
    if (!_connected || char == null) return;
    final bytes = utf8.encode(value);
    try {
      await char.write(bytes, withoutResponse: withoutResponse);
    } catch (_) {
      try {
        await char.write(bytes, withoutResponse: false);
      } catch (e2) {
        debugPrint('[BLE] write failed: $e2');
      }
    }
  }

  Future<void> disconnect() async {
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
    _device = null;
    _timeChar = null;
    _cmdChar = null;
    _drawChar = null;
    _stateChar = null;
    _otaControlChar = null;
    _otaDataChar = null;
    _otaStatusChar = null;
    _robotAnimation = null;
    _connected = false;
    _statusMessage = 'Disconnected';
    notifyListeners();
  }
}
