// Firebase Realtime Database paths for AquaMonitor (worker mobile app)
class AppConstants {
  // Tank ID — must match the ID used in your ESP32 firmware
  static const String tankId = 'TANK_01';

  static String get tankStatusPath => 'tank_status';
  static String get configPath => '$tankId/config/thresholds';
  static String get sensorLifespanPath => '$tankId/config/sensor_lifespan';
  static String get alertsPath => '$tankId/alerts';
  static String get reportsPath => '$tankId/reports';
  static String get sensorsPath => '$tankId/sensors';
  static const String usersPath = 'users';

  static const String appName = 'AquaWatch';
}
