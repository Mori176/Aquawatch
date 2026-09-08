/// A remark report sent by a worker. Stored at TANK_01/reports/<pushKey>.
class Report {
  final String id;
  final String issue;
  final String sensorId;
  final String notes;
  final List<String> imageUrls;
  final DateTime timestamp;

  const Report({
    required this.id,
    required this.issue,
    required this.sensorId,
    required this.notes,
    required this.imageUrls,
    required this.timestamp,
  });

  factory Report.fromMap(Map<dynamic, dynamic> map, String id) {
    final rawUrls = map['imageUrls'];
    final urls = rawUrls is List
        ? rawUrls.map((e) => e.toString()).toList()
        : <String>[];

    return Report(
      id: id,
      issue: map['issue']?.toString() ?? 'No issue',
      sensorId: map['sensorId']?.toString() ?? 'Unknown',
      notes: map['notes']?.toString() ?? '',
      imageUrls: urls,
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int)
          : DateTime.now(),
    );
  }
}
