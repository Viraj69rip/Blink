import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_manager.dart';

/// Persists a selected firmware binary, exposes its install state, and keeps a
/// daily local reminder active until BLINK accepts the update.
class FirmwareUpdateService extends ChangeNotifier {
  FirmwareUpdateService._();
  static final FirmwareUpdateService instance = FirmwareUpdateService._();

  static const _reminderId = 101;
  static const _fileKey = 'pending_firmware_file';
  static const _nameKey = 'pending_firmware_name';

  /// Configure at build time, for example:
  /// `--dart-define=BLINK_GITHUB_REPOSITORY=owner/BLINK`.
  /// Public GitHub releases must include one compiled ESP32 `.bin` asset.
  static const githubRepository =
      String.fromEnvironment('BLINK_GITHUB_REPOSITORY');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _hasPendingUpdate = false;
  String? _fileName;
  String? _filePath;
  String? _error;
  bool _checkingGitHub = false;
  String? _githubVersion;
  String? _githubAssetName;
  String? _githubAssetUrl;
  String? _githubReleaseNotes;
  String? _githubError;

  bool get hasPendingUpdate => _hasPendingUpdate;
  String? get fileName => _fileName;
  String? get error => _error;
  bool get isGitHubConfigured => githubRepository.isNotEmpty;
  bool get isCheckingGitHub => _checkingGitHub;
  String? get githubVersion => _githubVersion;
  String? get githubAssetName => _githubAssetName;
  String? get githubReleaseNotes => _githubReleaseNotes;
  String? get githubError => _githubError;
  bool get hasGitHubFirmware => _githubAssetUrl != null;

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
    if (isGitHubConfigured) unawaited(checkGitHubRelease());
    notifyListeners();
  }

  /// Reads the newest published GitHub release. No token is needed for a
  /// public repository; private repositories should use the file-picker flow.
  Future<void> checkGitHubRelease() async {
    if (!isGitHubConfigured || _checkingGitHub) return;
    _checkingGitHub = true;
    _githubError = null;
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
  /// update used by a manually chosen file.
  Future<void> downloadGitHubFirmware() async {
    final url = _githubAssetUrl;
    final name = _githubAssetName;
    if (url == null || name == null) {
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
      final bytes = Uint8List.fromList(await response.fold<List<int>>(
        <int>[],
        (buffer, chunk) => buffer..addAll(chunk),
      ));
      if (bytes.isEmpty)
        throw const FormatException('Downloaded firmware is empty.');
      await _storeFirmware(bytes, name);
    } catch (error) {
      _error = error.toString().replaceFirst('Bad state: ', '');
      notifyListeners();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> chooseFirmwareFile() async {
    _error = null;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['bin'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return false;

    final selected = result.files.single;
    Uint8List? bytes = selected.bytes;
    if (bytes == null && selected.path != null) {
      bytes = await File(selected.path!).readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) {
      _error = 'The selected firmware file could not be read.';
      notifyListeners();
      return false;
    }

    await _storeFirmware(bytes, selected.name);
    return true;
  }

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
      throw StateError('Choose a firmware .bin file before updating BLINK.');
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

  Future<void> discardPendingUpdate() =>
      _clearPersistedUpdate(cancelReminder: true);

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
