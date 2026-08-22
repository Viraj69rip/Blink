import 'package:package_info_plus/package_info_plus.dart';

/// The single source of truth for the app's own version string.
///
/// Three places used to hardcode this independently — Settings said 5.0.0,
/// About said 1.0.0, and the update checker said 5.1.0 — so the update banner
/// and the version the user could actually read disagreed. The value now comes
/// from the platform package metadata, which is generated from pubspec's
/// `version:` at build time and therefore cannot drift.
class AppInfo {
  AppInfo._();

  /// Used until [load] completes, and if the platform channel is unavailable
  /// (unit tests, or an Activity that is still attaching). Keep in step with
  /// pubspec `version:` so the fallback is never wrong, only redundant.
  static const String fallbackVersion = '5.1.0';

  static String _version = fallbackVersion;
  static String _buildNumber = '';
  static Future<void>? _loading;

  /// Semantic version, e.g. `5.1.0`. Never empty.
  static String get version => _version;

  /// Build number, e.g. `3001`. Empty until [load] resolves.
  static String get buildNumber => _buildNumber;

  /// `5.1.0` or `5.1.0 (3001)` once the build number is known.
  static String get versionLabel =>
      _buildNumber.isEmpty ? _version : '$_version ($_buildNumber)';

  /// Reads the real version from the platform. Safe to call repeatedly — the
  /// first call does the work and later callers await the same future.
  ///
  /// Deliberately not awaited during startup: `main` does not gate the first
  /// frame on platform services, and [fallbackVersion] is correct in the
  /// meantime.
  static Future<void> load() {
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) _version = info.version;
      _buildNumber = info.buildNumber;
    } catch (_) {
      // Keep the fallback. A missing version string must never break startup.
    }
  }
}
