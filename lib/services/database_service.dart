import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/sensor_data.dart';
import '../models/sensor_lifespan.dart';
import '../models/sensor_info.dart';
import '../models/alert_event.dart';
import '../models/notification_settings.dart';
import '../models/threshold_config.dart';
import '../models/report.dart';
import '../utils/constants.dart';

class DatabaseService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Live stream of current tank sensor readings from /tank_status
  Stream<SensorData> streamSensorData() {
    return _db.ref(AppConstants.tankStatusPath).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) {
        return SensorData(
          temperature: 0,
          ph: 0,
          tds: 0,
          waterLevel: 0,
          timestamp: DateTime.now(),
        );
      }
      return SensorData.fromMap(raw as Map<dynamic, dynamic>);
    });
  }

  /// Stream of sensor lifespan (months) from /<TANK_ID>/config/sensor_lifespan
  /// Set by the admin from the web app, read here by the mobile app.
  Stream<SensorLifespan> streamSensorLifespan() {
    return _db.ref(AppConstants.sensorLifespanPath).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return const SensorLifespan();
      return SensorLifespan.fromMap(raw as Map<dynamic, dynamic>);
    });
  }

  /// Live stream of alert thresholds from /<TANK_ID>/config/thresholds
  /// Written by the admin web app, used by the mobile app for
  /// STABLE/CAUTION logic and by the ESP32 for alert checks.
  Stream<ThresholdConfig> streamThresholdConfig() {
    return _db.ref(AppConstants.configPath).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return const ThresholdConfig();
      return ThresholdConfig.fromMap(raw as Map<dynamic, dynamic>);
    });
  }

  /// Stream of the last 20 alerts from /<TANK_ID>/alerts
  Stream<List<AlertEvent>> streamAlerts() {
    return _db
        .ref(AppConstants.alertsPath)
        .limitToLast(20)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <AlertEvent>[];
      final alertMap = raw as Map<dynamic, dynamic>;
      return alertMap.entries
          .map((e) => AlertEvent.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  // ── Sensors ──────────────────────────────────────────────────

  /// Stream of all tracked sensors from /<TANK_ID>/sensors
  Stream<List<SensorInfo>> streamSensors() {
    return _db.ref(AppConstants.sensorsPath).onValue.map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <SensorInfo>[];
      final map = raw as Map<dynamic, dynamic>;
      return map.entries
          .map((e) => SensorInfo.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()))
          .toList();
    });
  }

  /// Installs a new sensor — starts the 45-day countdown.
  Future<void> installSensor({
    required String id,
    required String type,
  }) async {
    final now = DateTime.now();
    await _db.ref('${AppConstants.sensorsPath}/$id').set({
      'type': type,
      'installedAt': now.millisecondsSinceEpoch,
      'lifespanDays': SensorInfo.defaultLifespanDays,
      'expiresAt': now
          .add(const Duration(days: SensorInfo.defaultLifespanDays))
          .millisecondsSinceEpoch,
      'status': 'active',
    });
  }

  /// Marks a sensor as removed (worker action).
  Future<void> removeSensor(String id) async {
    await _db.ref('${AppConstants.sensorsPath}/$id').update({
      'removedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Echoes the computed status back so the admin dashboard sees it.
  Future<void> echoSensorStatus(String id, String status) async {
    await _db.ref('${AppConstants.sensorsPath}/$id').update({'status': status});
  }

  /// Logs a sensor transition alert to /<TANK_ID>/alerts.
  Future<void> logSensorAlert({
    required String sensorId,
    required String status,
  }) async {
    final isReplace = status == 'replace';
    await _db.ref(AppConstants.alertsPath).push().set({
      'parameter': sensorId,
      'value': 0,
      'actionTaken': isReplace
          ? 'Sensor lifespan < ${SensorInfo.replaceWarningDays} days, replace soon'
          : 'Sensor inactive — remove or reinstall',
      'severity': isReplace ? 'warning' : 'critical',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Reports ──────────────────────────────────────────────────

  /// Stream of the most recent reports from /<TANK_ID>/reports
  Stream<List<Report>> streamReports() {
    return _db
        .ref(AppConstants.reportsPath)
        .limitToLast(30)
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return <Report>[];
      final map = raw as Map<dynamic, dynamic>;
      return map.entries
          .map((e) => Report.fromMap(
              e.value as Map<dynamic, dynamic>, e.key.toString()))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    });
  }

  /// Saves the FCM token for a user to users/<uid>/fcmToken
  Future<void> saveFcmToken(String uid, String token) async {
    await _db.ref('${AppConstants.usersPath}/$uid/fcmToken').set(token);
  }

  /// Stores the operator profile on registration: users/<uid>/{name, operatorId}
  Future<void> saveUserProfile({
    required String uid,
    required String name,
    required String operatorId,
  }) async {
    await _db.ref('${AppConstants.usersPath}/$uid').update({
      'name': name,
      'operatorId': operatorId,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Reads the operator name from users/<uid>/name
  Future<String?> getUserName(String uid) async {
    final snapshot = await _db.ref('${AppConstants.usersPath}/$uid/name').get();
    return snapshot.exists ? snapshot.value.toString() : null;
  }

  /// Single read of the operator's notification settings (defaults on).
  Future<NotificationSettings> getNotificationSettings(String uid) async {
    final snapshot =
        await _db.ref('${AppConstants.usersPath}/$uid/settings').get();
    if (!snapshot.exists) return const NotificationSettings();
    return NotificationSettings.fromMap(
        snapshot.value as Map<dynamic, dynamic>);
  }

  /// Live stream of the operator's notification settings.
  Stream<NotificationSettings> streamNotificationSettings(String uid) {
    return _db
        .ref('${AppConstants.usersPath}/$uid/settings')
        .onValue
        .map((event) {
      final raw = event.snapshot.value;
      if (raw == null) return const NotificationSettings();
      return NotificationSettings.fromMap(raw as Map<dynamic, dynamic>);
    });
  }

  /// Saves the operator's notification settings to users/<uid>/settings
  Future<void> saveNotificationSettings(
      String uid, NotificationSettings settings) async {
    await _db.ref('${AppConstants.usersPath}/$uid/settings').set(settings.toMap());
  }

  /// Uploads report images to Firebase Storage under
  /// /reports/<reportId>/image_<index>.jpg and returns their download URLs.
  Future<List<String>> uploadReportImages({
    required String reportId,
    required List<File> images,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      final ref = _storage.ref(
          '${AppConstants.reportsPath}/$reportId/image_$i.jpg');
      await ref.putFile(images[i]);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  /// Sends a remark report to /<TANK_ID>/reports
  Future<void> saveReport({
    required String issue,
    required String sensorId,
    required String notes,
    List<String> imageUrls = const [],
  }) async {
    await _db.ref(AppConstants.reportsPath).push().set({
      'issue': issue,
      'sensorId': sensorId,
      'notes': notes,
      'imageUrls': imageUrls,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
