import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';
import '../models/threshold_config.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';

/// Worker-side trends: mini line charts for all four parameters plus a
/// predictive "days until next water change" estimator based on the TDS
/// trend (same linear-regression approach as the admin web dashboard).
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dbService = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('Trends & Forecast')),
      body: StreamBuilder<List<SensorData>>(
        stream: dbService.streamHistoricalData(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final history = snapshot.data ?? [];
          if (history.isEmpty) {
            return const Center(
              child: Text(
                'No readings yet.\nThe charts fill as the ESP32 reports.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.greyText, fontSize: 14),
              ),
            );
          }

          return StreamBuilder<ThresholdConfig>(
            stream: dbService.streamThresholdConfig(),
            builder: (context, configSnap) {
              final config = configSnap.data ?? const ThresholdConfig();
              final tdsMax = config.tdsMax > 0 ? config.tdsMax : 600.0;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _predictorCard(history, tdsMax),
                  const SizedBox(height: 8),
                  _miniChart('TEMPERATURE (°C)', history,
                      (d) => d.temperature, AppColors.googleRed),
                  _miniChart('PH LEVEL', history, (d) => d.ph,
                      AppColors.googleYellowDark),
                  _miniChart('TDS (mg/L)', history, (d) => d.tds,
                      AppColors.googleGreen),
                  _miniChart('WATER LEVEL (%)', history,
                      (d) => d.waterLevel, AppColors.googleBlue),
                  const SizedBox(height: 4),
                  Text(
                    'Showing the last ${history.length} readings from TANK_01.',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.greyText),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ── Predictive estimator (TDS linear regression) ─────────────

  /// Least-squares slope of value vs. time, per day.
  double _slopePerDay(List<SensorData> data, double Function(SensorData) f) {
    final n = data.length;
    if (n < 2) return 0;
    double sx = 0, sy = 0, sxy = 0, sxx = 0;
    for (final d in data) {
      final x = d.timestamp.millisecondsSinceEpoch.toDouble();
      final y = f(d);
      sx += x;
      sy += y;
      sxy += x * y;
      sxx += x * x;
    }
    final denom = n * sxx - sx * sx;
    if (denom == 0) return 0;
    return ((n * sxy - sx * sy) / denom) * 86400000.0; // per day
  }

  Widget _predictorCard(List<SensorData> history, double tdsMax) {
    final current = history.last.tds;
    final slope = _slopePerDay(history, (d) => d.tds);
    final enough = history.length >= 10;

    String estimate;
    if (current >= tdsMax) {
      estimate = 'Change water NOW';
    } else if (!enough) {
      estimate = 'Collecting data…';
    } else if (slope <= 0.01) {
      estimate = 'TDS stable or falling';
    } else {
      final days = (tdsMax - current) / slope;
      estimate = days <= 1 ? 'Today' : '${days.toStringAsFixed(0)} days';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.auto_graph,
                size: 36, color: AppColors.googleBlue),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next Water Change (Predicted)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: AppColors.greyText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    estimate,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.googleBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current TDS: ${current.toStringAsFixed(0)} / '
                    'limit ${tdsMax.toStringAsFixed(0)} mg/L · '
                    'trend ${slope > 0 ? '+' : ''}${slope.toStringAsFixed(1)}/day',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.greyText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mini line chart ───────────────────────────────────────────

  Widget _miniChart(
    String title,
    List<SensorData> data,
    double Function(SensorData) selector,
    Color color,
  ) {
    final spots = <FlSpot>[
      for (var i = 0; i < data.length; i++)
        FlSpot(i.toDouble(), selector(data[i])),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: color,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  gridData: const FlGridData(
                      show: true, drawVerticalLine: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.08)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
