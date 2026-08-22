import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ble_manager.dart';

/// Weather + time driven mood sync.
///
/// Resolves a coarse location once (IP geolocation, cached in preferences),
/// pulls current conditions from **Open-Meteo** — which needs no API key and no
/// account — folds weather and local time into a single mood value in
/// `-2..2`, and pushes it to the robot as `MOOD:<n>`.
///
/// The firmware biases its idle expression pool with that number, so a rainy
/// midnight looks sleepy and gloomy while a clear spring morning looks
/// energetic.  Everything degrades gracefully: if the network is unavailable
/// the mood is derived from local time alone, which still gives the robot a
/// day/night personality offline.
class WeatherMoodService extends ChangeNotifier {
  WeatherMoodService._();
  static final WeatherMoodService instance = WeatherMoodService._();

  static const String _prefLat = 'blink_weather_lat';
  static const String _prefLon = 'blink_weather_lon';
  static const String _prefCity = 'blink_weather_city';
  static const Duration _timeSyncInterval = Duration(minutes: 15);
  static const Duration _weatherInterval = Duration(minutes: 30);
  static const Duration _netTimeout = Duration(seconds: 10);

  Timer? _syncTimer;
  Timer? _weatherTimer;
  bool _isSyncing = false;
  bool _autoSync = true;
  String? _lastError;
  WeatherMoodData? _currentMoodData;
  DateTime? _lastSyncTime;

  double? _lat;
  double? _lon;
  String? _city;

  /// Last mood actually pushed, so a reconnect can replay it without waiting
  /// for the next 30 minute tick.
  int? _lastPushedMood;

  bool get isSyncing => _isSyncing;
  bool get autoSyncEnabled => _autoSync;
  String? get lastError => _lastError;
  WeatherMoodData? get currentMoodData => _currentMoodData;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get locationLabel => _city;

  bool _initialized = false;

  /// Starts periodic sync.  Safe to call more than once — the Android activity
  /// can be recreated while this singleton survives, and the old code leaked a
  /// fresh pair of timers on every one of those rebuilds.
  Future<void> initialize() async {
    if (_initialized) {
      // Already running; just refresh so a resumed app shows current data.
      unawaited(_syncTimeAndMood());
      return;
    }
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      _lat = prefs.getDouble(_prefLat);
      _lon = prefs.getDouble(_prefLon);
      _city = prefs.getString(_prefCity);
    } catch (error) {
      debugPrint('[WeatherMood] preference load failed: $error');
    }

    await _syncTimeAndMood();
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    // Cancel first — calling this twice used to leave orphaned timers running
    // forever, each one hammering the BLE link with its own time sync.
    _syncTimer?.cancel();
    _weatherTimer?.cancel();

    _syncTimer = Timer.periodic(_timeSyncInterval, (_) {
      unawaited(_syncTimeOnly());
    });
    _weatherTimer = Timer.periodic(_weatherInterval, (_) {
      unawaited(_syncWeatherAndMood());
    });
  }

  Future<void> _syncTimeAndMood() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      await _syncTimeOnly();
      await _syncWeatherAndMood();
      _lastSyncTime = DateTime.now();
    } catch (e) {
      _lastError = 'Sync failed: $e';
      debugPrint('[WeatherMood] $_lastError');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncTimeOnly() async {
    final ble = BleManager.instance;
    if (!ble.isConnected || ble.firmwareUpdateInProgress) return;
    try {
      await ble.syncTime();
    } catch (error) {
      debugPrint('[WeatherMood] time sync failed: $error');
    }
  }

  /// Recomputes the mood and pushes it.  Never throws.
  Future<void> _syncWeatherAndMood() async {
    WeatherData? weather;
    try {
      weather = await _fetchWeatherData();
    } catch (e) {
      debugPrint('[WeatherMood] weather fetch failed: $e');
      _lastError = 'Weather unavailable — using time of day';
    }

    // Offline fallback keeps the day/night personality working.
    weather ??= _timeOnlyWeather();

    final moodData = _calculateMood(weather);
    _currentMoodData = moodData;
    notifyListeners();

    await pushMoodToRobot();
  }

  /// Sends the current mood over BLE.  Called on a timer and on reconnect.
  Future<void> pushMoodToRobot() async {
    final ble = BleManager.instance;
    final mood = _currentMoodData?.moodValue ?? _lastPushedMood;
    if (mood == null) return;
    if (!ble.isConnected || ble.firmwareUpdateInProgress) return;

    try {
      await ble.sendCommand('MOOD:$mood');
      _lastPushedMood = mood;
    } catch (error) {
      debugPrint('[WeatherMood] mood push failed: $error');
    }
  }

  // ── Network ──────────────────────────────────────────────────

  Future<WeatherData?> _fetchWeatherData() async {
    await _ensureLocation();
    final lat = _lat;
    final lon = _lon;
    if (lat == null || lon == null) return null;

    // Open-Meteo: free, no API key, no attribution requirement for non-commercial use.
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lon.toStringAsFixed(3),
      'current':
          'temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code,is_day',
      'timezone': 'auto',
    });

    final response = await http.get(uri).timeout(_netTimeout);
    if (response.statusCode != 200) {
      throw HttpExceptionLite('Open-Meteo returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected weather payload');
    }
    return WeatherData.fromOpenMeteo(decoded, city: _city);
  }

  /// Coarse IP geolocation, cached permanently.  Deliberately avoids GPS: the
  /// mood only needs city-level accuracy and asking for location permission
  /// just to pick a face would be a poor trade.
  Future<void> _ensureLocation() async {
    if (_lat != null && _lon != null) return;

    final response = await http
        .get(Uri.https('ipapi.co', '/json/'))
        .timeout(_netTimeout);
    if (response.statusCode != 200) {
      throw HttpExceptionLite('Geolocation returned ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Unexpected geolocation payload');
    }

    final lat = (decoded['latitude'] as num?)?.toDouble();
    final lon = (decoded['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      throw const FormatException('Geolocation had no coordinates');
    }

    _lat = lat;
    _lon = lon;
    _city = decoded['city']?.toString();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefLat, lat);
      await prefs.setDouble(_prefLon, lon);
      final city = _city;
      if (city != null && city.isNotEmpty) {
        await prefs.setString(_prefCity, city);
      }
    } catch (error) {
      debugPrint('[WeatherMood] could not cache location: $error');
    }
  }

  /// Neutral stand-in used when the network is unreachable, so the mood still
  /// tracks time of day.
  WeatherData _timeOnlyWeather() {
    final hour = DateTime.now().hour;
    final isNight = hour >= 22 || hour < 6;
    return WeatherData(
      condition: isNight ? 'Clear' : 'Clouds',
      temperature: 22,
      humidity: 60,
      windSpeed: 2,
      isDay: !isNight,
      timestamp: DateTime.now(),
      city: _city,
    );
  }

  // ── Mood model ───────────────────────────────────────────────

  /// Folds weather and local time into `-2..2`.
  ///
  /// Time of day is applied as a bounded *bias* rather than a hard clamp: the
  /// old version clamped to `-2..0` at night, which meant a beautiful clear
  /// night could never read as anything but sad.
  WeatherMoodData _calculateMood(WeatherData weather) {
    var score = 0.0;

    switch (_conditionFamily(weather.condition)) {
      case _ConditionFamily.clear:
        score += 1.6;
        break;
      case _ConditionFamily.cloudy:
        score += 0.1;
        break;
      case _ConditionFamily.snow:
        score += 0.9;
        break;
      case _ConditionFamily.fog:
        score -= 0.9;
        break;
      case _ConditionFamily.drizzle:
        score -= 0.5;
        break;
      case _ConditionFamily.rain:
        score -= 1.1;
        break;
      case _ConditionFamily.storm:
        score -= 1.7;
        break;
      case _ConditionFamily.unknown:
        break;
    }

    // Comfort curve: peaks around 22 °C, falls off either side.
    final comfort = 1.0 - ((weather.temperature - 22.0).abs() / 14.0);
    score += comfort.clamp(-1.0, 1.0);

    if (weather.windSpeed > 30) score -= 0.6;
    if (weather.humidity > 85) score -= 0.3;

    // Circadian bias.
    final now = DateTime.now();
    final hour = now.hour + now.minute / 60.0;
    score += _circadianBias(hour);

    final moodValue = score.round().clamp(-2, 2);

    return WeatherMoodData(
      moodValue: moodValue,
      moodLabel: _moodLabel(moodValue, hour),
      weather: weather,
      timestamp: now,
    );
  }

  /// Smooth energy curve over the day: sleepy in the small hours, brightest
  /// mid-morning, winding down after dinner.  A cosine keeps it continuous so
  /// the mood never jumps a whole step as the clock ticks over an hour.
  static double _circadianBias(double hour) {
    // Peak at 10:00, trough at 22:00 → shift so cos is 1 at hour 10.
    final phase = (hour - 10.0) / 24.0 * 2 * math.pi;
    final wave = math.cos(phase); // 1 at 10:00, -1 at 22:00
    var bias = wave * 0.8;
    // Deep night gets an extra push toward sleepy regardless of weather.
    if (hour >= 23 || hour < 6) bias -= 0.9;
    return bias;
  }

  static String _moodLabel(int mood, double hour) {
    final isNight = hour >= 22 || hour < 6;
    switch (mood) {
      case 2:
        return 'Excited';
      case 1:
        return isNight ? 'Cosy' : 'Happy';
      case 0:
        return isNight ? 'Sleepy' : 'Calm';
      case -1:
        return isNight ? 'Drowsy' : 'Gloomy';
      default:
        return isNight ? 'Exhausted' : 'Sad';
    }
  }

  static _ConditionFamily _conditionFamily(String condition) {
    switch (condition.toLowerCase()) {
      case 'clear':
      case 'sunny':
        return _ConditionFamily.clear;
      case 'clouds':
      case 'partly cloudy':
      case 'overcast':
        return _ConditionFamily.cloudy;
      case 'drizzle':
        return _ConditionFamily.drizzle;
      case 'rain':
        return _ConditionFamily.rain;
      case 'thunderstorm':
        return _ConditionFamily.storm;
      case 'snow':
        return _ConditionFamily.snow;
      case 'mist':
      case 'fog':
      case 'haze':
        return _ConditionFamily.fog;
      default:
        return _ConditionFamily.unknown;
    }
  }

  // ── Control ──────────────────────────────────────────────────

  Future<void> forceSync() async {
    await _syncTimeAndMood();
  }

  void setAutoSync(bool enabled) {
    _autoSync = enabled;
    if (enabled) {
      _startPeriodicSync();
    } else {
      _syncTimer?.cancel();
      _weatherTimer?.cancel();
      _syncTimer = null;
      _weatherTimer = null;
    }
    notifyListeners();
  }

  /// Wipes cached location and mood state.  Used by the in-app reset flow.
  Future<void> reset() async {
    _syncTimer?.cancel();
    _weatherTimer?.cancel();
    _syncTimer = null;
    _weatherTimer = null;
    _initialized = false;
    _isSyncing = false;
    _autoSync = true;
    _lastError = null;
    _currentMoodData = null;
    _lastSyncTime = null;
    _lastPushedMood = null;
    _lat = null;
    _lon = null;
    _city = null;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefLat);
      await prefs.remove(_prefLon);
      await prefs.remove(_prefCity);
    } catch (error) {
      debugPrint('[WeatherMood] could not clear cached location: $error');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }
}

enum _ConditionFamily { clear, cloudy, drizzle, rain, storm, snow, fog, unknown }

/// Small local exception type so this service does not depend on `dart:io`
/// (which would break a future web build).
class HttpExceptionLite implements Exception {
  const HttpExceptionLite(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Current-conditions snapshot.
class WeatherData {
  final String condition;
  final double temperature; // °C
  final int humidity; // %
  final double windSpeed; // km/h
  final bool isDay;
  final DateTime timestamp;
  final String? city;

  const WeatherData({
    required this.condition,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.timestamp,
    this.isDay = true,
    this.city,
  });

  /// Open-Meteo `/v1/forecast?current=…` payload.
  factory WeatherData.fromOpenMeteo(
    Map<String, dynamic> json, {
    String? city,
  }) {
    final current = json['current'];
    final map = current is Map<String, dynamic> ? current : const {};
    return WeatherData(
      condition: conditionFromWmoCode((map['weather_code'] as num?)?.toInt()),
      temperature: (map['temperature_2m'] as num?)?.toDouble() ?? 20.0,
      humidity: (map['relative_humidity_2m'] as num?)?.toInt() ?? 50,
      windSpeed: (map['wind_speed_10m'] as num?)?.toDouble() ?? 0.0,
      isDay: ((map['is_day'] as num?)?.toInt() ?? 1) == 1,
      timestamp: DateTime.now(),
      city: city,
    );
  }

  /// OpenWeatherMap payload, kept so swapping providers needs no call-site edits.
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      condition: json['weather']?[0]?['main']?.toString() ?? 'Unknown',
      temperature: (json['main']?['temp'] as num?)?.toDouble() ?? 20.0,
      humidity: (json['main']?['humidity'] as num?)?.toInt() ?? 50,
      windSpeed: (json['wind']?['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }

  /// WMO 4677 weather-code buckets used by Open-Meteo.
  static String conditionFromWmoCode(int? code) {
    if (code == null) return 'Unknown';
    if (code == 0) return 'Clear';
    if (code <= 3) return 'Clouds';
    if (code == 45 || code == 48) return 'Fog';
    if (code >= 51 && code <= 57) return 'Drizzle';
    if (code >= 61 && code <= 67) return 'Rain';
    if (code >= 71 && code <= 77) return 'Snow';
    if (code >= 80 && code <= 82) return 'Rain';
    if (code == 85 || code == 86) return 'Snow';
    if (code >= 95) return 'Thunderstorm';
    return 'Unknown';
  }

  String get summary {
    final where = (city != null && city!.isNotEmpty) ? '$city · ' : '';
    return '$where$condition ${temperature.round()}°C';
  }
}

/// Mood plus the weather context that produced it.
class WeatherMoodData {
  final int moodValue; // -2 … 2
  final String moodLabel;
  final WeatherData weather;
  final DateTime timestamp;

  const WeatherMoodData({
    required this.moodValue,
    required this.moodLabel,
    required this.weather,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'WeatherMoodData(mood: $moodLabel ($moodValue), '
        'weather: ${weather.condition} ${weather.temperature}°C, '
        'time: $timestamp)';
  }
}
