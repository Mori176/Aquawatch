/// A physical sensor tracked by the system. Stored at
/// TANK_01/sensors/<id>. Status is COMPUTED from facts (installedAt,
/// lifespanDays, removedAt) and echoed back to Firebase for the admin.
class SensorInfo {
  static const int defaultLifespanDays = 45;
  static const int replaceWarningDays = 7;

  final String id;
  final String type;
  final DateTime installedAt;
  final int lifespanDays;
  final DateTime? removedAt;
  final String status; // last echoed status ('active'/'replace'/'inactive'/'')
  final DateTime expiresAt;

  const SensorInfo({
    required this.id,
    required this.type,
    required this.installedAt,
    required this.lifespanDays,
    required this.expiresAt,
    this.removedAt,
    this.status = '',
  });

  factory SensorInfo.fromMap(Map<dynamic, dynamic> map, String id) {
    final lifespan =
        (map['lifespanDays'] as num?)?.toInt() ?? defaultLifespanDays;
    final installedAt = map['installedAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['installedAt'] as int)
        : DateTime.now();
    final expiresAt = map['expiresAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(map['expiresAt'] as int)
        : installedAt.add(Duration(days: lifespan));

    return SensorInfo(
      id: id,
      type: map['type']?.toString() ?? 'Unknown',
      installedAt: installedAt,
      lifespanDays: lifespan,
      expiresAt: expiresAt,
      removedAt: map['removedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['removedAt'] as int)
          : null,
      status: map['status']?.toString() ?? '',
    );
  }

  int get remainingDays {
    final rem = expiresAt.difference(DateTime.now()).inDays;
    return rem < 0 ? 0 : rem;
  }

  /// The source-of-truth status, computed from the stored facts.
  /// Priority: inactive (removed or expired) > replace > active.
  String get computedStatus {
    if (removedAt != null) return 'inactive';
    if (remainingDays <= 0) return 'inactive';
    if (remainingDays <= replaceWarningDays) return 'replace';
    return 'active';
  }
}
