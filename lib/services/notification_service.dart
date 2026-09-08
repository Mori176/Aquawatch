import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'database_service.dart';
import '../utils/navigator.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final DatabaseService _dbService = DatabaseService();

  Future<void> initialize() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      final token = await _fcm.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        // Save token to Firebase if a user is already signed in
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _dbService.saveFcmToken(uid, token);
        }
      }

      // Refresh token whenever it rotates
      _fcm.onTokenRefresh.listen((newToken) async {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null) {
          await _dbService.saveFcmToken(uid, newToken);
        }
      });
    } else {
      debugPrint('Push notification permission denied.');
    }

    // Handle foreground messages — respect the operator's settings.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  /// Shows a banner (with sound/vibration) only if the operator allows it.
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final prefs = await _dbService.getNotificationSettings(uid);
    if (!prefs.push) return; // push alerts disabled

    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;

    if (prefs.vibration) {
      HapticFeedback.vibrate();
    }
    if (prefs.sound) {
      SystemSound.play(SystemSoundType.alert);
    }

    final title = message.notification?.title ?? 'AquaWatch Alert';
    final body = message.notification?.body ?? '';
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          body.isEmpty ? title : '$title\n$body',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
