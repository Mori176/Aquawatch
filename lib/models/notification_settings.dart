/// Per-operator notification preferences, stored at
/// users/<uid>/settings. All default to enabled.
class NotificationSettings {
  final bool push;
  final bool sound;
  final bool vibration;

  const NotificationSettings({
    this.push = true,
    this.sound = true,
    this.vibration = true,
  });

  factory NotificationSettings.fromMap(Map<dynamic, dynamic> map) {
    return NotificationSettings(
      push: map['push'] as bool? ?? true,
      sound: map['sound'] as bool? ?? true,
      vibration: map['vibration'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'push': push,
        'sound': sound,
        'vibration': vibration,
      };
}
