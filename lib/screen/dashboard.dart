import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/sensor_data.dart';
import '../models/threshold_config.dart';
import '../utils/theme.dart';
import '../widgets/ui_elements.dart';
import 'trends.dart';

/// Reading-frequency presets shown in the picker dialog.
const _intervalPresets = <(int, String)>[
  (15, '15 seconds'),
  (60, '1 minute'),
  (900, '15 minutes'),
  (10800, '3 hours'),
  (21600, '6 hours'),
  (43200, '12 hours'),
  (86400, '24 hours'),
];

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<SensorData>(
          stream: dbService.streamSensorData(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2.5),
              );
            }

            return StreamBuilder<ThresholdConfig>(
              stream: dbService.streamThresholdConfig(),
              builder: (context, configSnap) {
                // Thresholds come from the admin web app via Firebase.
                // Fall back to sensible defaults until the admin saves.
                final config = configSnap.data ?? const ThresholdConfig();
                final phMin = config.phMin > 0 ? config.phMin : 6.5;
                final phMax = config.phMax > 0 ? config.phMax : 9.0;
                final tempMin = config.tempMin > 0 ? config.tempMin : 26.0;
                final tempMax = config.tempMax > 0 ? config.tempMax : 32.0;
                final tdsMax = config.tdsMax > 0 ? config.tdsMax : 500.0;
                final waterMin =
                    config.waterLevelMin > 0 ? config.waterLevelMin : 30.0;

                return StreamBuilder<int>(
                  stream: dbService.streamReadingInterval(),
                  builder: (context, intervalSnap) {
                    final intervalSec = intervalSnap.data ?? 15;

                    final isTdsStable = data.tds <= tdsMax;
                    final isWaterStable = data.waterLevel >= waterMin;
                    final isPhStable = data.ph >= phMin && data.ph <= phMax;
                    final isTempStable =
                        data.temperature >= tempMin &&
                            data.temperature <= tempMax;

                    // Freshness window scales with the reading interval so a
                    // healthy device on a slow schedule never shows OFFLINE.
                    final freshWindowSec =
                        intervalSec * 2 > 30 ? intervalSec * 2 : 30;
                    final dataAge =
                        DateTime.now().difference(data.timestamp).inSeconds;
                    final isFresh = dataAge <= freshWindowSec;

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header: AquaWatch + controls + LIVE ──────
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'AquaWatch',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.googleBlue,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.speed, size: 20),
                                color: AppColors.darkText,
                                tooltip: 'Reading frequency',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                onPressed: () => _showIntervalDialog(
                                    context, dbService, intervalSec),
                              ),
                              IconButton(
                                icon: const Icon(Icons.show_chart, size: 20),
                                color: AppColors.darkText,
                                tooltip: 'Trends & forecast',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const TrendsScreen()),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.white,
                                  border: Border.all(
                                    color: isFresh
                                        ? AppColors.googleGreen
                                        : AppColors.greyText,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      color: isFresh
                                          ? AppColors.googleGreen
                                          : AppColors.greyText,
                                      size: 9,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isFresh ? 'LIVE' : 'OFFLINE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                        color: isFresh
                                            ? AppColors.googleGreen
                                            : AppColors.greyText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                isFresh
                                    ? Icons.signal_cellular_alt
                                    : Icons.signal_cellular_off,
                                color: isFresh
                                    ? AppColors.googleBlue
                                    : AppColors.greyText,
                                size: 22,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // ── Live Monitor card ───────────────────────────
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Live Monitor',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.darkText,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Every ${_intervalLabel(intervalSec)} · '
                                    'Last sync: ${_formatTime(data.timestamp.toLocal())}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.greyText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          // ── Parameters (thresholds from Firebase) ───────
                          _paramCard(
                            label: 'TDS (mg/L)',
                            value: data.tds.toStringAsFixed(0),
                            accent: AppColors.googleGreen,
                            stable: isTdsStable,
                          ),
                          _paramCard(
                            label: 'WATER LEVEL (m)',
                            value: data.waterLevel.toStringAsFixed(2),
                            accent: AppColors.googleBlue,
                            stable: isWaterStable,
                          ),
                          _paramCard(
                            label: 'PH LEVEL',
                            value: data.ph.toStringAsFixed(1),
                            accent: AppColors.googleYellowDark,
                            stable: isPhStable,
                          ),
                          _paramCard(
                            label: 'TEMPERATURE (°C)',
                            value: data.temperature.toStringAsFixed(1),
                            accent: AppColors.googleRed,
                            stable: isTempStable,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _intervalLabel(int seconds) {
    for (final (secs, label) in _intervalPresets) {
      if (secs == seconds) return label;
    }
    if (seconds % 3600 == 0) return '${seconds ~/ 3600} h';
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds s';
  }

  Future<void> _showIntervalDialog(
      BuildContext context, DatabaseService dbService, int currentSec) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Reading Frequency'),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Current: every ${_intervalLabel(currentSec)}\n'
              'The ESP32 applies changes within ~1 minute.',
              style:
                  const TextStyle(fontSize: 13, color: AppColors.greyText),
            ),
          ),
          const SizedBox(height: 8),
          for (final (secs, label) in _intervalPresets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, secs),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    if (secs == currentSec)
                      const Icon(Icons.check_circle,
                          size: 18, color: AppColors.googleBlue)
                    else
                      const SizedBox(width: 18),
                    const SizedBox(width: 10),
                    Text(
                      label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (selected == null || selected == currentSec) return;
    await dbService.setReadingInterval(selected);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reading frequency set to every ${_intervalLabel(selected)} — '
          'ESP32 applies within ~1 minute.',
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _paramCard({
    required String label,
    required String value,
    required Color accent,
    required bool stable,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      color: AppColors.darkText,
                    ),
                  ),
                ],
              ),
            ),
            StatusTag(
              stable ? 'STABLE' : 'CAUTION',
              color: stable ? AppColors.stable : AppColors.caution,
              inverted: !stable,
            ),
          ],
        ),
      ),
    );
  }
}
