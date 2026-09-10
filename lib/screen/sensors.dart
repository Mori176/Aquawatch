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

  /// Sensors hidden this session (dismissed / being removed) so a stream
  /// event in flight cannot re-insert the card into the tree.
  final Set<String> _hiddenIds = {};

  /// Last known status per sensor, kept in memory so time-based
  /// transitions (active → replace/inactive) alert exactly ONCE.
  final Map<String, String> _lastKnownStatus = {};

  static const _types = ['Water Level', 'Temperature', 'pH', 'TDS'];

  @override
  void initState() {
    super.initState();
    _sub = _dbService.streamSensors().listen((sensors) {
      _syncStatus(sensors);
      if (!mounted) return;
      setState(() {
        _sensors = sensors
            .where((s) =>
                !_hiddenIds.contains(s.id) && s.removedAt == null)
            .toList();
        _loading = false;
      });
    });
    // Re-evaluate every minute so countdown/status updates without
    // waiting for a Firebase data change.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
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

  /// Time-based transition detection (active → replace/inactive as the
  /// countdown ticks down). Alerts and echoes fire exactly once per
  /// transition thanks to the in-memory _lastKnownStatus guard —
  /// immune to stream/timer races.
  Future<void> _syncStatus(List<SensorInfo> sensors) async {
    for (final sensor in sensors) {
      if (_hiddenIds.contains(sensor.id) || sensor.removedAt != null) continue;

      final computed = sensor.computedStatus;
      final lastKnown = _lastKnownStatus[sensor.id] ??
          (sensor.status.isEmpty ? computed : sensor.status);
      _lastKnownStatus[sensor.id] = computed;

      if (computed == lastKnown) continue;

      if (computed == 'replace' || computed == 'inactive') {
        await _dbService.logSensorAlert(
            sensorId: sensor.id, status: computed);
      }
      await _dbService.echoSensorStatus(sensor.id, computed);
    }
  }

  // ── Add / remove ─────────────────────────────────────────────

  Future<void> _addSensor() async {
    final idController = TextEditingController();
    final lifespanController =
        TextEditingController(text: '${SensorInfo.defaultLifespanDays}');
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
              const SizedBox(height: 12),
              TextField(
                controller: lifespanController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'LIFESPAN (DAYS)',
                  hintText: 'e.g. 45',
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'The countdown starts the moment you install.',
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
              style:
                  ElevatedButton.styleFrom(minimumSize: const Size(90, 40)),
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
    final lifespan = int.tryParse(lifespanController.text.trim()) ?? 0;
    if (lifespan <= 0) {
      _showSnack('Lifespan must be a whole number of days (at least 1).');
      return;
    }
    _hiddenIds.remove(id);
    _lastKnownStatus[id] = 'active';
    await _dbService.installSensor(id: id, type: type, lifespanDays: lifespan);
    if (mounted) {
      _showSnack('Sensor $id installed ($lifespan-day countdown started).');
    }
  }

  /// Confirmation dialog only — returns the worker's choice.
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
    return ok ?? false;
  }

  /// Performs the removal: hide the card from the tree IMMEDIATELY
  /// (same frame as the dismiss animation), then persist to Firebase.
  Future<void> _performRemove(SensorInfo sensor) async {
    setState(() {
      _hiddenIds.add(sensor.id);
      _sensors.removeWhere((s) => s.id == sensor.id);
    });
    await _dbService.removeSensor(sensor.id);
    await _dbService.logSensorAlert(sensorId: sensor.id, status: 'inactive');
    await _dbService.echoSensorStatus(sensor.id, 'inactive');
    if (mounted) _showSnack('Sensor ${sensor.id} removed.');
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
      onDismissed: (_) => _performRemove(sensor),
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
              _infoRow(
                'Expires',
                _formatDate(sensor.expiresAt),
                highlight: status != 'active',
              ),
              _infoRow('Lifespan', '${sensor.lifespanDays} days'),
              _infoRow(
                'Remaining',
                '${sensor.remainingDays} days',
                highlight: status != 'active',
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    if (await _confirmRemove(sensor)) {
                      _performRemove(sensor);
                    }
                  },
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
