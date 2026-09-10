/// Alert thresholds written by the admin web app to
/// TANK_01/config/thresholds and read live by the mobile app + ESP32.
/// Field names match the web app / ESP32 (ph_min, ph_max, ...).
class ThresholdConfig {
  final double phMin;
  final double phMax;
  final double tempMin;
  final double tempMax;
  final double tdsMax;
  final double waterLevelMin;

  const ThresholdConfig({
    this.phMin = 0,
    this.phMax = 0,
    this.tempMin = 0,
    this.tempMax = 0,
    this.tdsMax = 0,
    this.waterLevelMin = 0,
  });

  factory ThresholdConfig.fromMap(Map<dynamic, dynamic> map) {
    return ThresholdConfig(
      phMin: (map['ph_min'] as num?)?.toDouble() ?? 0,
      phMax: (map['ph_max'] as num?)?.toDouble() ?? 0,
      tempMin: (map['temp_min'] as num?)?.toDouble() ?? 0,
      tempMax: (map['temp_max'] as num?)?.toDouble() ?? 0,
      tdsMax: (map['tds_max'] as num?)?.toDouble() ?? 0,
      waterLevelMin: (map['waterlevel_min'] as num?)?.toDouble() ?? 0,
    );
  }

  /// True once the admin has actually saved a config node.
  bool get hasValues => phMin != 0 || phMax != 0 || tdsMax != 0;
}
