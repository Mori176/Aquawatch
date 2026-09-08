import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_settings.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import '../widgets/ui_elements.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _dbService = DatabaseService();
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _update(
      NotificationSettings Function(NotificationSettings) mutate) async {
    final uid = _uid;
    if (uid == null) return;
    final settings = await _dbService.getNotificationSettings(uid);
    await _dbService.saveNotificationSettings(uid, mutate(settings));
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Not signed in')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Settings')),
      body: StreamBuilder<NotificationSettings>(
        stream: _dbService.streamNotificationSettings(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final settings = snapshot.data ?? const NotificationSettings();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SectionLabel('Preferences'),
              Card(
                child: Column(
                  children: [
                    SwitchListTile(
                      value: settings.push,
                      onChanged: (v) => _update((s) =>
                          NotificationSettings(
                              push: v, sound: s.sound, vibration: s.vibration)),
                      activeTrackColor: AppColors.googleBlue,
                      title: const Text(
                        'Push Alerts',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      subtitle: const Text(
                        'Receive live alerts for this operator',
                        style: TextStyle(fontSize: 12, color: AppColors.greyText),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    SwitchListTile(
                      value: settings.sound,
                      onChanged: (v) => _update((s) =>
                          NotificationSettings(
                              push: s.push, sound: v, vibration: s.vibration)),
                      activeTrackColor: AppColors.googleBlue,
                      title: const Text(
                        'Sound',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      subtitle: const Text(
                        'Play an alert tone',
                        style: TextStyle(fontSize: 12, color: AppColors.greyText),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    SwitchListTile(
                      value: settings.vibration,
                      onChanged: (v) => _update((s) =>
                          NotificationSettings(
                              push: s.push, sound: s.sound, vibration: v)),
                      activeTrackColor: AppColors.googleBlue,
                      title: const Text(
                        'Vibration',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      subtitle: const Text(
                        'Vibrate when an alert arrives',
                        style: TextStyle(fontSize: 12, color: AppColors.greyText),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Settings are synced to your operator account and apply '
                'to alert banners shown while the app is open.',
                style: TextStyle(fontSize: 12, color: AppColors.greyText),
              ),
            ],
          );
        },
      ),
    );
  }
}
