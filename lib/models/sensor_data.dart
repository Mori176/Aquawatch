class SensorData {
  final double temperature;
  final double ph;
  final double tds;
  final double waterLevel;
  final DateTime timestamp;

  SensorData({
    required this.temperature,
    required this.ph,
    required this.tds,
    required this.waterLevel,
    required this.timestamp,
  });

  factory SensorData.fromMap(Map<dynamic, dynamic> map) {
    return SensorData(
      temperature: (map['temperature'] as num?)?.toDouble() ?? 0.0,
      ph: (map['ph'] as num?)?.toDouble() ?? 0.0,
      tds: (map['tds'] as num?)?.toDouble() ?? 0.0,
      waterLevel: (map['waterlevel'] as num?)?.toDouble() ?? 0.0,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }
}
