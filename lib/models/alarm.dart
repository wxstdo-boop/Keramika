import 'dart:convert';
import 'package:flutter/material.dart';
import 'wake_task.dart';

class Alarm {
  final String id;
  TimeOfDay time;
  List<int> repeatDays;
  String label;
  bool enabled;
  bool pinned;
  WakeUpTask taskType;
  bool vibrate;
  String soundName;
  String? customSoundPath;
  String notes;

  static const sounds = [
    'Default',
    'Gentle',
    'Classic',
    'Digital',
    'Nature',
    'Custom',
  ];

  Alarm({
    required this.id,
    required this.time,
    this.repeatDays = const [],
    this.label = '',
    this.enabled = true,
    this.pinned = false,
    this.taskType = WakeUpTask.none,
    this.vibrate = true,
    this.soundName = 'Default',
    this.customSoundPath,
    this.notes = '',
  });

  Alarm copyWith({
    TimeOfDay? time,
    List<int>? repeatDays,
    String? label,
    bool? enabled,
    bool? pinned,
    WakeUpTask? taskType,
    bool? vibrate,
    String? soundName,
    String? customSoundPath,
    String? notes,
  }) {
    return Alarm(
      id: id,
      time: time ?? this.time,
      repeatDays: repeatDays ?? this.repeatDays,
      label: label ?? this.label,
      enabled: enabled ?? this.enabled,
      pinned: pinned ?? this.pinned,
      taskType: taskType ?? this.taskType,
      vibrate: vibrate ?? this.vibrate,
      soundName: soundName ?? this.soundName,
      customSoundPath: customSoundPath ?? this.customSoundPath,
      notes: notes ?? this.notes,
    );
  }

  String get timeLabel {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'hour': time.hour,
    'minute': time.minute,
    'repeatDays': repeatDays,
    'label': label,
    'enabled': enabled,
    'pinned': pinned,
    'taskType': taskType.name,
    'vibrate': vibrate,
    'soundName': soundName,
    'customSoundPath': customSoundPath,
    'notes': notes,
  };

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
    id: json['id'] as String,
    time: TimeOfDay(hour: json['hour'] as int, minute: json['minute'] as int),
    repeatDays: (json['repeatDays'] as List).cast<int>(),
    label: json['label'] as String? ?? '',
    enabled: json['enabled'] is bool
        ? (json['enabled'] as bool)
        : json['enabled'] is num
        ? (json['enabled'] as num) != 0
        : true,
    pinned: json['pinned'] is bool
        ? (json['pinned'] as bool)
        : json['pinned'] is num
        ? (json['pinned'] as num) != 0
        : false,
    taskType: WakeUpTask.values.firstWhere(
      (e) => e.name == json['taskType'],
      orElse: () => WakeUpTask.none,
    ),
    vibrate: json['vibrate'] is bool
        ? (json['vibrate'] as bool)
        : json['vibrate'] is num
        ? (json['vibrate'] as num) != 0
        : true,
    soundName: json['soundName'] as String? ?? 'Default',
    customSoundPath: json['customSoundPath'] as String?,
    notes: json['notes'] as String? ?? '',
  );
}

String alarmsToJson(List<Alarm> alarms) {
  return jsonEncode(alarms.map((a) => a.toJson()).toList());
}

List<Alarm> alarmsFromJson(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Alarm.fromJson(e as Map<String, dynamic>)).toList();
}
