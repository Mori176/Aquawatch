import 'package:flutter/material.dart';
import '../services/database_service.dart';
import '../models/alert_event.dart';
import '../utils/theme.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _dbService = DatabaseService();
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: StreamBuilder<List<AlertEvent>>(
        stream: _dbService.streamAlerts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final alerts = snapshot.data ?? [];
          final critical = alerts.where((a) => a.isCritical).length;
          final warning = alerts.where((a) => a.isWarning).length;
          final info = alerts.where((a) => a.isInfo).length;

          final filtered = switch (_filter) {
            'critical' => alerts.where((a) => a.isCritical).toList(),
            'warning' => alerts.where((a) => a.isWarning).toList(),
            'info' => alerts.where((a) => a.isInfo).toList(),
            _ => alerts,
          };

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', alerts.length, 'all'),
                      const SizedBox(width: 8),
                      _filterChip('Critical', critical, 'critical'),
                      const SizedBox(width: 8),
                      _filterChip('Warning', warning, 'warning'),
                      const SizedBox(width: 8),
                      _filterChip('Info', info, 'info'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No alerts',
                          style: TextStyle(
                            color: AppColors.greyText,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) =>
                            _alertCard(filtered[index]),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, int count, String key) {
    final selected = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.googleBlue : AppColors.white,
          border: Border.all(
            color: selected ? AppColors.googleBlue : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            color: selected ? AppColors.white : AppColors.darkText,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _alertCard(AlertEvent alert) {
    final isCritical = alert.isCritical;
    final Color severityColor = isCritical
        ? AppColors.googleRed
        : alert.isWarning
            ? AppColors.googleYellowDark
            : AppColors.googleBlue;
    final icon = isCritical
        ? Icons.dangerous_outlined
        : alert.isWarning
            ? Icons.warning_amber_outlined
            : Icons.info_outline;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: severityColor),
                const SizedBox(width: 6),
                Text(
                  alert.severity.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: severityColor,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatTime(alert.timestamp.toLocal()),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.greyText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${alert.parameter} alert',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Value: ${alert.value} — ${alert.actionTaken}',
              style: const TextStyle(fontSize: 12, color: AppColors.greyText),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => _showAction(alert),
                style: isCritical
                    ? OutlinedButton.styleFrom(
                        backgroundColor: AppColors.googleRed,
                        foregroundColor: AppColors.white,
                        side: const BorderSide(color: AppColors.googleRed),
                      )
                    : OutlinedButton.styleFrom(
                        foregroundColor: severityColor,
                        side: BorderSide(color: severityColor),
                      ),
                child: const Text('ACTION  ›'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAction(AlertEvent alert) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${alert.parameter}: ${alert.value}\n${alert.actionTaken}',
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]}, '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}
