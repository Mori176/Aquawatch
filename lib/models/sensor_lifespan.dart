/// Sensor lifespan (in months) per parameter.
/// Set by the admin from the web app and read by the mobile app.
class SensorLifespan {
  final int waterLevel;
  final int temperature;
  final int ph;
  final int tds;

  const SensorLifespan({
    this.waterLevel = 0,
    this.temperature = 0,
    this.ph = 0,
    this.tds = 0,
  });

  factory SensorLifespan.fromMap(Map<dynamic, dynamic> map) {
    return SensorLifespan(
      waterLevel: (map['waterLevel'] as num?)?.toInt() ?? 0,
      temperature: (map['temperature'] as num?)?.toInt() ?? 0,
      ph: (map['ph'] as num?)?.toInt() ?? 0,
      tds: (map['tds'] as num?)?.toInt() ?? 0,
    );
  }

  /// Returns lifespan string like "6 months", or "N/A" when not set.
  static String monthsLabel(int months) =>
      months > 0 ? '$months mo' : 'N/A';
}
