import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../services/ble_manager.dart';

/// Weather-based mood sync service.
/// Fetches weather and time data, determines robot mood, and syncs over BLE.
class WeatherMoodService extends ChangeNotifier {
  WeatherMoodService._();
  static final WeatherMoodService instance = WeatherMoodService._();

  Timer? _syncTimer;
  Timer? _weatherTimer;
  bool _isSyncing = false;
  String? _lastError;
  WeatherMoodData? _currentMoodData;
  DateTime? _lastSyncTime;

  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;
  WeatherMoodData? get currentMoodData => _currentMoodData;
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Initialize periodic sync (every 30 minutes for weather, every minute for time)
  Future<void> initialize() async {
    await _syncTimeAndMood();
    _startPeriodicSync();
  }

  void _startPeriodicSync() {
    // Sync time every minute
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncTimeOnly();
    });

    // Sync weather every 30 minutes
    _weatherTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _syncWeatherAndMood();
    });
  }

  /// Sync both time and weather-based mood
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

  /// Sync only time to robot RTC
  Future<void> _syncTimeOnly() async {
    final ble = BleManager.instance;
    if (!ble.isConnected) return;

    await ble.syncTime();
    debugPrint('[WeatherMood] Time synced to robot');
  }

  /// Fetch weather and determine mood, then send to robot
  Future<void> _syncWeatherAndMood() async {
    final ble = BleManager.instance;
    if (!ble.isConnected) return;

    try {
      final weatherData = await _fetchWeatherData();
      if (weatherData == null) return;

      final moodData = _calculateMood(weatherData);
      _currentMoodData = moodData;

      // Send mood to robot: MOOD:-2 to MOOD:2
      await ble.sendCommand('MOOD:${moodData.moodValue}');
      debugPrint('[WeatherMood] Mood synced: ${moodData.moodLabel} (${moodData.moodValue})');
    } catch (e) {
      debugPrint('[WeatherMood] Weather sync failed: $e');
    }
  }

  /// Fetch weather data from OpenWeatherMap or similar
  /// For demo, uses a mock implementation. Replace with real API key.
  Future<WeatherData?> _fetchWeatherData() async {
    // TODO: Replace with actual OpenWeatherMap API call
    // Example:
    // final response = await http.get(Uri.parse(
    //   'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey&units=metric'
    // ));
    // return WeatherData.fromJson(jsonDecode(response.body));

    // Mock implementation for testing
    return _getMockWeatherData();
  }

  WeatherData _getMockWeatherData() {
    // Simulate weather based on time of day for demo
    final hour = DateTime.now().hour;
    final isNight = hour >= 22 || hour < 6;
    final isMorning = hour >= 6 && hour < 12;
    final isAfternoon = hour >= 12 && hour < 18;
    final isEvening = hour >= 18 && hour < 22;

    // Mock weather conditions
    String condition;
    double temp;
    int humidity;
    double windSpeed;

    if (isNight) {
      condition = 'Clear';
      temp = 18.0;
      humidity = 65;
      windSpeed = 2.0;
    } else if (isMorning) {
      condition = 'Clouds';
      temp = 22.0;
      humidity = 70;
      windSpeed = 3.0;
    } else if (isAfternoon) {
      condition = 'Sunny';
      temp = 28.0;
      humidity = 50;
      windSpeed = 4.0;
    } else {
      condition = 'Rain';
      temp = 24.0;
      humidity = 80;
      windSpeed = 5.0;
    }

    return WeatherData(
      condition: condition,
      temperature: temp,
      humidity: humidity,
      windSpeed: windSpeed,
      timestamp: DateTime.now(),
    );
  }

  /// Calculate mood value (-2 to 2) based on weather and time
  WeatherMoodData _calculateMood(WeatherData weather) {
    int moodValue = 0;
    String moodLabel = 'Neutral';

    // Base mood from weather condition
    switch (weather.condition.toLowerCase()) {
      case 'clear':
      case 'sunny':
        moodValue += 2;
        moodLabel = 'Happy';
        break;
      case 'clouds':
      case 'partly cloudy':
      case 'overcast':
        moodValue += 0;
        moodLabel = 'Neutral';
        break;
      case 'rain':
      case 'drizzle':
      case 'thunderstorm':
        moodValue -= 1;
        moodLabel = 'Gloomy';
        break;
      case 'snow':
        moodValue += 1;
        moodLabel = 'Excited';
        break;
      case 'mist':
      case 'fog':
      case 'haze':
        moodValue -= 1;
        moodLabel = 'Sleepy';
        break;
      default:
        moodValue += 0;
        moodLabel = 'Neutral';
    }

    // Adjust for temperature
    if (weather.temperature > 30) {
      moodValue -= 1; // Too hot = grumpy
      moodLabel = 'Grumpy';
    } else if (weather.temperature < 10) {
      moodValue -= 1; // Too cold = sad
      moodLabel = 'Cold';
    } else if (weather.temperature >= 20 && weather.temperature <= 25) {
      moodValue += 1; // Comfortable = happy
    }

    // Adjust for time of day
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 6) {
      // Night time - sleepy
      moodValue = moodValue.clamp(-2, 0);
      if (moodValue >= 0) moodLabel = 'Sleepy';
    } else if (hour >= 6 && hour < 9) {
      // Morning - energetic
      moodValue = (moodValue + 1).clamp(-2, 2);
      moodLabel = 'Energetic';
    } else if (hour >= 12 && hour < 14) {
      // Lunch time - content
      moodValue = moodValue.clamp(-1, 1);
      moodLabel = 'Content';
    } else if (hour >= 18 && hour < 22) {
      // Evening - relaxed
      moodValue = moodValue.clamp(-1, 1);
      moodLabel = 'Relaxed';
    }

    // Clamp to valid range
    moodValue = moodValue.clamp(-2, 2);

    // Map to final labels
    final labels = {
      -2: 'Sad',
      -1: 'Gloomy',
      0: 'Neutral',
      1: 'Happy',
      2: 'Excited',
    };
    moodLabel = labels[moodValue] ?? 'Neutral';

    return WeatherMoodData(
      moodValue: moodValue,
      moodLabel: moodLabel,
      weather: weather,
      timestamp: DateTime.now(),
    );
  }

  /// Force immediate sync
  Future<void> forceSync() async {
    await _syncTimeAndMood();
  }

  /// Enable/disable automatic sync
  void setAutoSync(bool enabled) {
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

  @override
  void dispose() {
    _syncTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }
}

/// Weather data model
class WeatherData {
  final String condition;
  final double temperature;
  final int humidity;
  final double windSpeed;
  final DateTime timestamp;

  const WeatherData({
    required this.condition,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.timestamp,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      condition: json['weather']?[0]?['main']?.toString() ?? 'Unknown',
      temperature: (json['main']?['temp'] as num?)?.toDouble() ?? 20.0,
      humidity: (json['main']?['humidity'] as num?)?.toInt() ?? 50,
      windSpeed: (json['wind']?['speed'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.now(),
    );
  }
}

/// Mood data with weather context
class WeatherMoodData {
  final int moodValue; // -2 to 2
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