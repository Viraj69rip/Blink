import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_info.dart';
import 'ble_manager.dart';

/// Persists a selected firmware binary, exposes its install state, and keeps a
/// daily local reminder active until BLINK accepts the update.
///
/// Also handles checking for app updates from the same GitHub release,
/// downloading the APK, and triggering the Android package installer.
class FirmwareUpdateService extends ChangeNotifier {
  FirmwareUpdateService._();
  static final FirmwareUpdateService instance = FirmwareUpdateService._();

  static const _reminderId = 101;
  static const _fileKey = 'pending_firmware_file';
  static const _nameKey = 'pending_firmware_name';

  /// GitHub repository that hosts the compiled BLINK firmware .bin assets.
  /// Hardcoded for the closed-source companion app so no --dart-define is needed.
  static const githubRepository = 'Viraj69rip/Blink';

  /// Current app version — compared against GitHub release for app updates.
  /// Resolved from the platform package metadata; see [AppInfo].
  static String get appVersion => AppInfo.version;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _notificationsReady = true;
  bool _hasPendingUpdate = false;
  String? _fileName;
  String? _filePath;
  String? _error;
  bool _checkingGitHub = false;
  bool _downloadingFirmware = false;
  double _downloadProgress = 0;
  String? _githubVersion;
  String? _githubAssetName;
  String? _githubAssetUrl;
  String? _githubReleaseNotes;
  String? _githubError;
  String? _robotVersion;
  bool _isUpdateAvailable = false;
  bool _notifiedUpdateAvailable = false;

  /// True while a BLE firmware transfer is running.  Set by [installPendingUpdate]
  /// so no background download or auto-download can start mid-OTA and blow up
  /// the heap while the radio is saturated.
  bool _otaInProgress = false;

  /// Progress updates arrive thousands of times per download.  Rebuilding the
  /// whole widget tree on each one was a major source of jank and of
  /// out-of-memory pressure during OTA.  Coalesce to ~10 Hz / 1% deltas.
  DateTime _lastProgressNotifyAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _lastNotifiedProgress = -1;

  void _notifyProgress(double progress) {
    final now = DateTime.now();
    final movedEnough = (progress - _lastNotifiedProgress).abs() >= 0.01;
    final waitedEnough =
        now.difference(_lastProgressNotifyAt) >= const Duration(milliseconds: 100);
    if (!movedEnough && !waitedEnough) return;
    _lastProgressNotifyAt = now;
    _lastNotifiedProgress = progress;
    notifyListeners();
  }

  // ── App self-update state ──────────────────────────────────────
  bool _isAppUpdateAvailable = false;
  String? _githubApkUrl;
  String? _githubApkName;
  bool _downloadingApk = false;
  double _apkDownloadProgress = 0;
  String? _pendingApkPath;
  String? _appUpdateError;

  bool get hasPendingUpdate => _hasPendingUpdate;
  String? get fileName => _fileName;
  String? get error => _error;
  bool get isCheckingGitHub => _checkingGitHub;
  bool get isDownloadingFirmware => _downloadingFirmware;
  double get downloadProgress => _downloadProgress;
  String? get githubVersion => _githubVersion;
  String? get githubAssetName => _githubAssetName;
  String? get githubReleaseNotes => _githubReleaseNotes;
  String? get githubError => _githubError;
  bool get hasGitHubFirmware => _githubAssetUrl != null;
  String? get robotVersion => _robotVersion;
  bool get isUpdateAvailable => _isUpdateAvailable;

  bool get robotVersionKnown => _robotVersion != null;
  bool get otaInProgress => _otaInProgress;

  // App update getters
  bool get isAppUpdateAvailable => _isAppUpdateAvailable;
  bool get isDownloadingApk => _downloadingApk;
  double get apkDownloadProgress => _apkDownloadProgress;
  bool get hasDownloadedApk => _pendingApkPath != null;
  String? get appUpdateError => _appUpdateError;

  /// Called by RobotStateProvider whenever the BLE-reported firmware version changes.
  void updateRobotVersion(String? version) {
    _robotVersion = version;
    if (version == null) _notifiedUpdateAvailable = false;
    _evaluateUpdateAvailability();
  }

  /// Compares [githubVersion] with [robotVersion] and sets [_isUpdateAvailable].
  ///
  /// This runs on the BLE-notify path (~20 Hz), so it must never start work.
  /// Auto-download is deliberately *not* triggered here: doing so meant every
  /// `OTA:PROGRESS` packet could kick off a fresh multi-megabyte HTTP download
  /// while the robot was mid-flash.  Downloads are now started only from
  /// [checkGitHubRelease] or by explicit user action.
  void _evaluateUpdateAvailability({bool allowAutoDownload = false}) {
    _isUpdateAvailable = _isNewerVersion(_githubVersion, _robotVersion);
    if (allowAutoDownload &&
        _isUpdateAvailable &&
        !_hasPendingUpdate &&
        !_downloadingFirmware &&
        !_otaInProgress &&
        _githubAssetUrl != null) {
      unawaited(downloadGitHubFirmware().catchError((_) {}));
    }
    notifyListeners();
  }

  /// Simple x.y.z semver comparison — returns true iff [a] > [b].
  static bool _isNewerVersion(String? a, String? b) {
    if (a == null || b == null) return false;
    final aParts = a.split('.');
    final bParts = b.split('.');
    for (var i = 0; i < 3; i++) {
      final aVal = int.tryParse(i < aParts.length ? aParts[i] : '0') ?? 0;
      final bVal = int.tryParse(i < bParts.length ? bParts[i] : '0') ?? 0;
      if (aVal != bVal) return aVal > bVal;
    }
    return false;
  }

  /// Fires a one-shot local notification about an available firmware update.
  Future<void> notifyUpdateAvailable() async {
    if (_notifiedUpdateAvailable || !_isUpdateAvailable) return;
    if (!_notificationsReady) return;
    _notifiedUpdateAvailable = true;
    await _requestNotificationPermission();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'firmware_update_available',
        'Firmware update available',
        channelDescription: 'New BLINK firmware release detected',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    try {
      await _notifications.show(
        102,
        'BLINK update available',
        'v$_robotVersion → v$_githubVersion — install from Settings.',
        details,
      );
    } catch (error) {
      debugPrint('[BLINK] update notification failed: $error');
    }
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Every step below touches a platform plugin or the filesystem and can
    // throw while the Android activity is being recreated.  A throw here used
    // to abort the whole startup chain silently — the app's "opens once per
    // install" bug.  Each step is now independently guarded.
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notifications.initialize(settings);
    } catch (error) {
      debugPrint('[BLINK] notification init failed (non-fatal): $error');
      _notificationsReady = false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString(_fileKey);
      final savedName = prefs.getString(_nameKey);
      if (savedPath != null && await File(savedPath).exists()) {
        _filePath = savedPath;
        _fileName = savedName ?? File(savedPath).uri.pathSegments.last;
        _hasPendingUpdate = true;
        await _scheduleDailyReminder();
      } else {
        await _clearPersistedUpdate(prefs: prefs, cancelReminder: true);
      }
    } catch (error) {
      debugPrint('[BLINK] firmware state restore failed (non-fatal): $error');
      // Fall back to "nothing pending" rather than leaving half-restored state.
      _filePath = null;
      _fileName = null;
      _hasPendingUpdate = false;
    }

    unawaited(checkGitHubRelease());
    notifyListeners();
  }

  /// Reads the newest published GitHub release. No token is needed for a
  /// public repository; private repositories should use the file-picker flow.
  Future<void> checkGitHubRelease() async {
    if (_checkingGitHub) return;
    // Yield once before touching any state.  The firmware update sheet calls
    // this from build(); mutating + notifying synchronously threw
    // "setState() called during build" and red-screened the sheet.
    await Future<void>.delayed(Duration.zero);
    if (_checkingGitHub) return;
    _checkingGitHub = true;
    _githubError = null;
    _appUpdateError = null;
    notifyListeners();

    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.https('api.github.com', '/repos/$githubRepository/releases/latest'),
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'BLINK-Companion');
      request.headers
          .set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub returned ${response.statusCode}');
      }
      final release = jsonDecode(text) as Map<String, dynamic>;
      final assets = (release['assets'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>();

      // Find firmware .bin asset
      final binary = assets.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => (asset?['name'] as String? ?? '')
                .toLowerCase()
                .endsWith('.bin'),
            orElse: () => null,
          );
      if (binary == null) {
        throw const FormatException(
            'The latest release has no .bin firmware asset.');
      }

      _githubVersion = (release['tag_name'] as String? ?? 'latest')
          .replaceFirst(RegExp(r'^[vV]'), '');
      _githubAssetName = binary['name'] as String?;
      _githubAssetUrl = binary['browser_download_url'] as String?;
      _githubReleaseNotes = release['body'] as String?;
      if (_githubAssetUrl == null || _githubAssetName == null) {
        throw const FormatException('The GitHub firmware asset is incomplete.');
      }

      // Find APK asset for app self-update
      final apk = assets.cast<Map<String, dynamic>?>().firstWhere(
            (asset) => (asset?['name'] as String? ?? '')
                .toLowerCase()
                .endsWith('.apk'),
            orElse: () => null,
          );
      if (apk != null) {
        _githubApkUrl = apk['browser_download_url'] as String?;
        _githubApkName = apk['name'] as String?;
        // Check if GitHub release version is newer than the installed app
        _isAppUpdateAvailable = _isNewerVersion(_githubVersion, appVersion);
      } else {
        _githubApkUrl = null;
        _githubApkName = null;
        _isAppUpdateAvailable = false;
      }

      _evaluateUpdateAvailability(allowAutoDownload: true);
    } catch (error) {
      _githubAssetUrl = null;
      _githubError = error.toString().replaceFirst('Bad state: ', '');
    } finally {
      client.close(force: true);
      _checkingGitHub = false;
      notifyListeners();
    }
  }

  /// Downloads the selected GitHub release and turns it into the same pending
  /// update used by a manually chosen file. Reports progress via [downloadProgress].
  ///
  /// The payload is streamed straight to disk.  The previous implementation
  /// accumulated it into a growable `List<int>` (8 bytes of heap per firmware
  /// byte on ARM64, plus grow-and-copy reallocations, plus a final full copy),
  /// which is what made the update flow OOM on lower-RAM phones.
  Future<void> downloadGitHubFirmware() async {
    if (_downloadingFirmware || _otaInProgress) return;
    final url = _githubAssetUrl;
    final name = _githubAssetName;
    if (url == null || name == null) {
      throw StateError('Check GitHub releases before downloading firmware.');
    }

    _downloadingFirmware = true;
    _downloadProgress = 0;
    _error = null;
    notifyListeners();

    final client = HttpClient();
    File? partial;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BLINK-Companion');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
            'Firmware download returned ${response.statusCode}');
      }

      final directory = await getApplicationDocumentsDirectory();
      partial = File('${directory.path}${Platform.pathSeparator}'
          'blink_pending_firmware.bin.part');
      final sink = partial.openWrite();
      final contentLength = response.contentLength;
      int received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          // dart:io reports -1, not null, when the server omits Content-Length.
          if (contentLength > 0) {
            _downloadProgress = (received / contentLength).clamp(0.0, 1.0);
            _notifyProgress(_downloadProgress);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received == 0) {
        throw const FormatException('Downloaded firmware is empty.');
      }
      _downloadProgress = 1;
      notifyListeners();
      await _promoteDownloadedFirmware(partial, name);
      partial = null;
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      if (partial != null && await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {/* best effort */}
      }
      _downloadingFirmware = false;
      _downloadProgress = 0;
      _lastNotifiedProgress = -1;
      client.close(force: true);
    }
  }

  // ── App self-update methods ────────────────────────────────────

  /// Downloads the APK asset from the latest GitHub release.
  ///
  /// Streamed to disk for the same reason as the firmware: an APK is several
  /// times larger than a .bin and buffering it in a growable list was a
  /// guaranteed OOM on mid-range hardware.
  Future<void> downloadAppUpdate() async {
    if (_downloadingApk) return;
    final url = _githubApkUrl;
    final name = _githubApkName;
    if (url == null || name == null) {
      throw StateError('No APK asset found in the latest GitHub release.');
    }

    _downloadingApk = true;
    _apkDownloadProgress = 0;
    _appUpdateError = null;
    notifyListeners();

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BLINK-Companion');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('APK download returned ${response.statusCode}');
      }

      final directory = await getApplicationDocumentsDirectory();
      final target = File(
          '${directory.path}${Platform.pathSeparator}blink_app_update.apk');
      final sink = target.openWrite();
      final contentLength = response.contentLength;
      int received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          // dart:io reports -1, not null, when the server omits Content-Length.
          if (contentLength > 0) {
            _apkDownloadProgress = (received / contentLength).clamp(0.0, 1.0);
            _notifyProgress(_apkDownloadProgress);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (received == 0) {
        throw const FormatException('Downloaded APK is empty.');
      }

      _pendingApkPath = target.path;
      _apkDownloadProgress = 1;
      notifyListeners();
    } catch (error) {
      _appUpdateError = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _downloadingApk = false;
      _lastNotifiedProgress = -1;
      client.close(force: true);
    }
  }

  /// Returns the path to the downloaded APK for installation.
  /// The caller should use a platform channel or package (e.g. open_filex)
  /// to trigger the Android package installer.
  String? get pendingApkPath => _pendingApkPath;

  /// Renames a fully-downloaded `.part` file into place and registers it as the
  /// pending update.  Atomic-ish: the pending path only ever points at a
  /// complete file.
  Future<void> _promoteDownloadedFirmware(File partial, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final targetPath =
        '${directory.path}${Platform.pathSeparator}blink_pending_firmware.bin';
    final existing = File(targetPath);
    if (await existing.exists()) {
      try {
        await existing.delete();
      } catch (_) {/* overwrite below */}
    }
    final target = await partial.rename(targetPath);
    await _registerPendingFirmware(target.path, name);
  }

  Future<void> _storeFirmware(Uint8List bytes, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final target = File(
        '${directory.path}${Platform.pathSeparator}blink_pending_firmware.bin');
    await target.writeAsBytes(bytes, flush: true);
    await _registerPendingFirmware(target.path, name);
  }

  /// Registers an externally supplied firmware image (e.g. a user-picked
  /// `.bin`) as the pending update.
  Future<void> storeFirmwareBytes(Uint8List bytes, String name) =>
      _storeFirmware(bytes, name);

  Future<void> _registerPendingFirmware(String path, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileKey, path);
    await prefs.setString(_nameKey, name);
    _filePath = path;
    _fileName = name;
    _hasPendingUpdate = true;
    await _requestNotificationPermission();
    await _scheduleDailyReminder();
    notifyListeners();
  }

  /// Streams the pending firmware to BLINK over BLE.
  ///
  /// A successful transfer ends with the robot rebooting, which tears down the
  /// link.  That is expected, not a failure — [BleManager.installFirmware]
  /// resolves normally in that case, so the pending file is cleared here.
  Future<void> installPendingUpdate(BleManager ble) async {
    final path = _filePath;
    if (!_hasPendingUpdate || path == null || !await File(path).exists()) {
      throw StateError('Download a firmware release before updating BLINK.');
    }
    if (_otaInProgress) {
      throw StateError('A firmware update is already running.');
    }

    _error = null;
    _otaInProgress = true;
    notifyListeners();
    try {
      await ble.installFirmware(await File(path).readAsBytes());
      await _clearPersistedUpdate(cancelReminder: true);
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _otaInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (!_notificationsReady) return;
    try {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('[BLINK] notification permission request failed: $error');
    }
  }

  Future<void> _scheduleDailyReminder() async {
    if (!_notificationsReady) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'firmware_updates',
        'Firmware updates',
        channelDescription: 'Daily reminders to install a pending BLINK update',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    try {
      await _notifications.periodicallyShow(
        _reminderId,
        'BLINK update ready',
        'Install ${_fileName ?? 'the selected firmware'} when BLINK is nearby.',
        RepeatInterval.daily,
        details,
        // Inexact deliberately: exact alarms need SCHEDULE_EXACT_ALARM /
        // USE_EXACT_ALARM, which are not declared.  Do not switch to an exact
        // mode without adding the permission or this will start throwing.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (error) {
      debugPrint('[BLINK] daily reminder schedule failed: $error');
    }
  }

  Future<void> _clearPersistedUpdate({
    SharedPreferences? prefs,
    required bool cancelReminder,
  }) async {
    final storedPrefs = prefs ?? await SharedPreferences.getInstance();
    final path = _filePath ?? storedPrefs.getString(_fileKey);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('[BLINK] could not delete stale firmware: $error');
      }
    }
    await storedPrefs.remove(_fileKey);
    await storedPrefs.remove(_nameKey);
    if (cancelReminder && _notificationsReady) {
      try {
        await _notifications.cancel(_reminderId);
      } catch (error) {
        debugPrint('[BLINK] reminder cancel failed: $error');
      }
    }
    _filePath = null;
    _fileName = null;
    _hasPendingUpdate = false;
    _error = null;
    notifyListeners();
  }

  /// Clears every persisted firmware/app-update artefact.  Used by the
  /// in-app reset flow.
  Future<void> resetAll() async {
    await _clearPersistedUpdate(cancelReminder: true);
    final apk = _pendingApkPath;
    if (apk != null) {
      try {
        final file = File(apk);
        if (await file.exists()) await file.delete();
      } catch (_) {/* best effort */}
    }
    _pendingApkPath = null;
    _githubVersion = null;
    _githubAssetName = null;
    _githubAssetUrl = null;
    _githubReleaseNotes = null;
    _githubApkUrl = null;
    _githubApkName = null;
    _githubError = null;
    _appUpdateError = null;
    _isUpdateAvailable = false;
    _isAppUpdateAvailable = false;
    _notifiedUpdateAvailable = false;
    _robotVersion = null;
    notifyListeners();
  }
}
