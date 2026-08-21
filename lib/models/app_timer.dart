import 'dart:convert';

class AppTimer {
  final String id;
  int totalSeconds;
  bool enabled;
  String label;
  String soundName;
  bool vibrate;

  static const sounds = ['Default', 'Gentle', 'Classic', 'Digital', 'Nature'];

  AppTimer({
    required this.id,
    required this.totalSeconds,
    this.enabled = true,
    this.label = '',
    this.soundName = 'Default',
    this.vibrate = true,
  });

  String get displayLabel =>
      label.isNotEmpty ? label : formatDuration(totalSeconds);

  static String formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  AppTimer copyWith({
    int? totalSeconds,
    bool? enabled,
    String? label,
    String? soundName,
    bool? vibrate,
  }) {
    return AppTimer(
      id: id,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      enabled: enabled ?? this.enabled,
      label: label ?? this.label,
      soundName: soundName ?? this.soundName,
      vibrate: vibrate ?? this.vibrate,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'totalSeconds': totalSeconds,
    'enabled': enabled,
    'label': label,
    'soundName': soundName,
    'vibrate': vibrate,
  };

  factory AppTimer.fromJson(Map<String, dynamic> json) => AppTimer(
    id: json['id'] as String,
    totalSeconds: json['totalSeconds'] as int? ?? 300,
    enabled: json['enabled'] is bool
        ? (json['enabled'] as bool)
        : json['enabled'] is num
        ? (json['enabled'] as num) != 0
        : true,
    label: json['label'] as String? ?? '',
    soundName: json['soundName'] as String? ?? 'Default',
    vibrate: json['vibrate'] is bool
        ? (json['vibrate'] as bool)
        : json['vibrate'] is num
        ? (json['vibrate'] as num) != 0
        : true,
  );
}

String appTimersToJson(List<AppTimer> timers) {
  return jsonEncode(timers.map((t) => t.toJson()).toList());
}

List<AppTimer> appTimersFromJson(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => AppTimer.fromJson(e as Map<String, dynamic>)).toList();
}
