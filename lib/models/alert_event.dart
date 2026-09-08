class AlertEvent {
  final String id;
  final String parameter;
  final double value;
  final String actionTaken;
  final String severity; // 'critical', 'warning' or 'info'
  final DateTime timestamp;

  AlertEvent({
    required this.id,
    required this.parameter,
    required this.value,
    required this.actionTaken,
    required this.severity,
    required this.timestamp,
  });

  factory AlertEvent.fromMap(Map<dynamic, dynamic> map, String id) {
    return AlertEvent(
      id: id,
      parameter: map['parameter']?.toString() ?? 'Unknown',
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      actionTaken: map['actionTaken']?.toString() ?? 'No action logged',
      severity: map['severity']?.toString().toLowerCase() ?? 'warning',
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }

  bool get isCritical => severity == 'critical';
  bool get isWarning => severity == 'warning';
  bool get isInfo => severity == 'info';
}
