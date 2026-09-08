import 'dart:async';
import 'package:flutter/material.dart';
import '../models/sensor_info.dart';
import '../services/database_service.dart';
import '../utils/theme.dart';
import '../widgets/ui_elements.dart';

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key});

  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  final _dbService = DatabaseService();
  List<SensorInfo> _sensors = [];
  StreamSubscription? _sub;
  Timer? _timer;
  bool _loading = true;

  static const _types = ['Water Level', 'Temperature', 'pH', 'TDS'];

  @override
  void initState() {
    super.initState();
    _sub = _dbService.streamSensors().listen((sensors) {
      _syncStatus(sensors);
      setState(() {
        _sensors = sensors;
        _loading = false;
      });
    });
    // Re-evaluate every minute so countdown/status updates without
    // waiting for a Firebase data change.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _syncStatus(_sensors);
      setState(() {}); // refresh countdown display
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  /// State machine: on any status change, echo it to Firebase and log
  /// an alert when a sensor enters Replace or Inactive.
  Future<void> _syncStatus(List<SensorInfo> sensors) async {
    for (final sensor in sensors) {
      final newStatus = sensor.computedStatus;
      if (newStatus != sensor.status) {
        if (newStatus == 'replace' || newStatus == 'inactive') {
          await _dbService.logSensorAlert(
              sensorId: sensor.id, status: newStatus);
        }
        await _dbService.echoSensorStatus(sensor.id, newStatus);
      }
    }
  }

  Future<void> _addSensor() async {
    final idController = TextEditingController();
    String type = _types.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Install Sensor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                decoration: const InputDecoration(
                  labelText: 'SENSOR ID',
                  hintText: 'e.g. WL-01, PH-01, TMP-01, TDS-01',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'TYPE'),
                items: _types
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setDialogState(() => type = v ?? _types.first),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'A 45-day lifespan countdown starts on install.',
                  style: TextStyle(fontSize: 12, color: AppColors.greyText),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(90, 40)),
              child: const Text('Install'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final id = idController.text.trim().toUpperCase();
    if (id.isEmpty) {
      _showSnack('Please enter a sensor ID.');
      return;
    }
    await _dbService.installSensor(id: id, type: type);
    if (mounted) _showSnack('Sensor $id installed (45-day countdown started).');
  }

  Future<bool> _confirmRemove(SensorInfo sensor) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${sensor.id}?'),
        content: const Text(
            'This marks the sensor as inactive and notifies the alerts dashboard.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.googleRed,
                minimumSize: const Size(90, 40)),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _dbService.removeSensor(sensor.id);
    }
    return ok ?? false;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sensors')),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSensor,
        backgroundColor: AppColors.googleBlue,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : _sensors.isEmpty
              ? const Center(
                  child: Text(
                    'No sensors installed yet.\nTap + to install one.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: AppColors.greyText, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                  itemCount: _sensors.length,
                  itemBuilder: (context, index) =>
                      _sensorCard(_sensors[index]),
                ),
    );
  }

  Widget _sensorCard(SensorInfo sensor) {
    final status = sensor.computedStatus;
    final (Color color, String label, bool inverted) = switch (status) {
      'inactive' => (AppColors.googleRed, 'INACTIVE', true),
      'replace' => (AppColors.googleYellowDark, 'REPLACE', false),
      _ => (AppColors.googleGreen, 'ACTIVE', false),
    };

    return Dismissible(
      key: ValueKey(sensor.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmRemove(sensor),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.googleRed,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.white),
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sensor.id,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                  StatusTag(label, color: color, inverted: inverted),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                sensor.type.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppColors.greyText,
                ),
              ),
              const Divider(height: 20, color: AppColors.border),
              _infoRow('Installed', _formatDate(sensor.installedAt)),
              _infoRow('Lifespan', '${sensor.lifespanDays} days'),
              _infoRow(
                'Remaining',
                sensor.removedAt != null
                    ? 'Removed ${_formatDate(sensor.removedAt!)}'
                    : '${sensor.remainingDays} days',
                highlight: status != 'active',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => _confirmRemove(sensor),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.googleRed,
                    side: const BorderSide(color: AppColors.googleRed),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('REMOVE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
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
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.googleYellowDark : AppColors.darkText,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${t.day} ${months[t.month - 1]} ${t.year}';
  }
}
