import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const appVersion = '5.0.0';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
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
  /// Auto-downloads the latest firmware when an update is detected and no
  /// pending file exists yet.
  void _evaluateUpdateAvailability() {
    _isUpdateAvailable = _isNewerVersion(_githubVersion, _robotVersion);
    if (_isUpdateAvailable &&
        !_hasPendingUpdate &&
        !_downloadingFirmware &&
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
    await _notifications.show(
      102,
      'BLINK update available',
      'v$_robotVersion → v$_githubVersion — install from Settings.',
      details,
    );
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);

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
    unawaited(checkGitHubRelease());
    notifyListeners();
  }

  /// Reads the newest published GitHub release. No token is needed for a
  /// public repository; private repositories should use the file-picker flow.
  Future<void> checkGitHubRelease() async {
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

      _evaluateUpdateAvailability();
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
  Future<void> downloadGitHubFirmware() async {
    if (_downloadingFirmware) return;
    _downloadingFirmware = true;
    _downloadProgress = 0;
    final url = _githubAssetUrl;
    final name = _githubAssetName;
    if (url == null || name == null) {
      _downloadingFirmware = false;
      throw StateError('Check GitHub releases before downloading firmware.');
    }

    _error = null;
    notifyListeners();
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'BLINK-Companion');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
            'Firmware download returned ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      final chunks = <int>[];
      int received = 0;
      await for (final chunk in response) {
        chunks.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          _downloadProgress = (received / contentLength).clamp(0.0, 1.0);
        }
        notifyListeners();
      }

      final bytes = Uint8List.fromList(chunks);
      if (bytes.isEmpty) {
        throw const FormatException('Downloaded firmware is empty.');
      }
      _downloadProgress = 1;
      notifyListeners();
      await _storeFirmware(bytes, name);
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _downloadingFirmware = false;
      _downloadProgress = 0;
      client.close(force: true);
    }
  }

  // ── App self-update methods ────────────────────────────────────

  /// Downloads the APK asset from the latest GitHub release.
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

      final contentLength = response.contentLength ?? 0;
      final chunks = <int>[];
      int received = 0;
      await for (final chunk in response) {
        chunks.addAll(chunk);
        received += chunk.length;
        if (contentLength > 0) {
          _apkDownloadProgress = (received / contentLength).clamp(0.0, 1.0);
        }
        notifyListeners();
      }

      final bytes = Uint8List.fromList(chunks);
      if (bytes.isEmpty) {
        throw const FormatException('Downloaded APK is empty.');
      }

      // Save APK to app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final target = File(
          '${directory.path}${Platform.pathSeparator}blink_app_update.apk');
      await target.writeAsBytes(bytes, flush: true);
      _pendingApkPath = target.path;
      _apkDownloadProgress = 1;
      notifyListeners();
    } catch (error) {
      _appUpdateError = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      _downloadingApk = false;
      client.close(force: true);
    }
  }

  /// Returns the path to the downloaded APK for installation.
  /// The caller should use a platform channel or package (e.g. open_filex)
  /// to trigger the Android package installer.
  String? get pendingApkPath => _pendingApkPath;

  Future<void> _storeFirmware(Uint8List bytes, String name) async {
    final directory = await getApplicationDocumentsDirectory();
    final target = File(
        '${directory.path}${Platform.pathSeparator}blink_pending_firmware.bin');
    await target.writeAsBytes(bytes, flush: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileKey, target.path);
    await prefs.setString(_nameKey, name);
    _filePath = target.path;
    _fileName = name;
    _hasPendingUpdate = true;
    await _requestNotificationPermission();
    await _scheduleDailyReminder();
    notifyListeners();
  }

  Future<void> installPendingUpdate(BleManager ble) async {
    final path = _filePath;
    if (!_hasPendingUpdate || path == null || !await File(path).exists()) {
      throw StateError('Download a firmware release before updating BLINK.');
    }

    _error = null;
    notifyListeners();
    try {
      await ble.installFirmware(await File(path).readAsBytes());
      await _clearPersistedUpdate(cancelReminder: true);
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _requestNotificationPermission() async {
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<void> _scheduleDailyReminder() async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'firmware_updates',
        'Firmware updates',
        channelDescription: 'Daily reminders to install a pending BLINK update',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _notifications.periodicallyShow(
      _reminderId,
      'BLINK update ready',
      'Install ${_fileName ?? 'the selected firmware'} when BLINK is nearby.',
      RepeatInterval.daily,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  Future<void> _clearPersistedUpdate({
    SharedPreferences? prefs,
    required bool cancelReminder,
  }) async {
    final storedPrefs = prefs ?? await SharedPreferences.getInstance();
    final path = _filePath ?? storedPrefs.getString(_fileKey);
    if (path != null) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await storedPrefs.remove(_fileKey);
    await storedPrefs.remove(_nameKey);
    if (cancelReminder) await _notifications.cancel(_reminderId);
    _filePath = null;
    _fileName = null;
    _hasPendingUpdate = false;
    _error = null;
    notifyListeners();
  }
}
