import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import '../widgets/ui_elements.dart';
import 'login.dart';
import 'notification_settings.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Current Station'),
              const Text(
                'Seabass Alpha - North Tank',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 14),

              // ── User card ──────────────────────────────────────
              FutureBuilder<String?>(
                future: user != null
                    ? dbService.getUserName(user.uid)
                    : Future.value(null),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? user?.email ?? 'Operator';
                  final initials = _initials(name);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: AppColors.avatarBg,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.darkText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkText,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'OPERATOR',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                    color: AppColors.greyText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              // ── Settings card ──────────────────────────────────
              const SectionLabel('Settings'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.notifications_outlined,
                      color: AppColors.googleBlue),
                  title: const Text(
                    'Notification Settings',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  subtitle: const Text(
                    'Push alerts, sound and vibration',
                    style: TextStyle(fontSize: 12, color: AppColors.greyText),
                  ),
                  trailing:
                      const Icon(Icons.chevron_right, color: AppColors.greyText),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationSettingsScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Telemetry card ─────────────────────────────────
              const SectionLabel('Telemetry'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _TelemetryRow(
                        'Last Login',
                        user?.metadata.lastSignInTime != null
                            ? _formatDate(
                                user!.metadata.lastSignInTime!.toLocal())
                            : '—',
                      ),
                      const Divider(height: 20, color: AppColors.border),
                      const _TelemetryRow(
                        'Device',
                        'Android',
                        showDivider: false,
                      ),
                      const SizedBox(height: 12),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 13, color: AppColors.googleGreen),
                          SizedBox(width: 4),
                          Text(
                            'ENCRYPTED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              color: AppColors.googleGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              OutlinedButton.icon(
                onPressed: () async {
                  await AuthService().signOut();
                  if (!context.mounted) return;
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.googleRed,
                  side: const BorderSide(color: AppColors.googleRed),
                ),
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('LOGOUT'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String _formatDate(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h12 = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '${days[t.weekday - 1]}, ${t.day} ${months[t.month - 1]} · '
        '$h12:${t.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class _TelemetryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool showDivider;

  const _TelemetryRow(this.label, this.value, {this.showDivider = true});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: AppColors.greyText,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
        if (showDivider) const Divider(height: 20, color: AppColors.border),
      ],
    );
  }
}
