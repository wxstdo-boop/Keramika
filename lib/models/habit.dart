import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/icon_map.dart';

class Habit {
  final String id;
  String name;
  String notes;
  String status;
  bool doneToday;
  int streak;
  int iconCodePoint;
  List<int> activeDays;
  DateTime createdAt;
  bool pinned;
  DateTime? lastDoneDate;
  String type;

  /// Напоминание «Вспомнить всё»: время в формате 'HH:mm' или null.
  String? reminderTime;

  /// Текст напоминания (до 60 символов): если задан, показывается
  /// вместо времени в карточке привычки.
  String? reminderText;

  Habit({
    required this.id,
    required this.name,
    this.notes = '',
    this.status = '',
    this.doneToday = false,
    this.streak = 0,
    this.iconCodePoint = 57690,
    this.activeDays = const [],
    this.pinned = false,
    DateTime? createdAt,
    this.lastDoneDate,
    this.type = 'good',
    this.reminderTime,
    this.reminderText,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDueToday {
    if (activeDays.isEmpty) return true;
    // Считаем день недели по Москве (UTC+3), чтобы день
    // «перепрыгивал» в 00:00 МСК вне зависимости от того,
    // в каком часовом поясе устройство.
    final msk = DateTime.now().toUtc().add(const Duration(hours: 3));
    return activeDays.contains(msk.weekday);
  }

  IconData get icon => iconDataForCodePoint(iconCodePoint);

  /// Сентинел для [copyWith]'s [lastDoneDate]: `null` должен УМЕТЬ
  /// очищать дату (сброс стрика), поэтому дефолт — не null, а маркер
  /// «не менять». Раньше было `lastDoneDate ?? this.lastDoneDate`:
  /// передача null молча игнорировалась, и после снятия галочки
  /// (стрик 1 → 0) дата оставалась «сегодня» — повторная отметка в тот
  /// же день попадала в ветку re-mark и стрик навсегда застревал на 0.
  static const Object _unset = Object();

  Habit copyWith({
    String? name,
    String? notes,
    String? status,
    bool? doneToday,
    int? streak,
    int? iconCodePoint,
    List<int>? activeDays,
    bool? pinned,
    Object? lastDoneDate = _unset,
    String? type,
    String? reminderTime,
    String? reminderText,
  }) => Habit(
    id: id,
    name: name ?? this.name,
    notes: notes ?? this.notes,
    status: status ?? this.status,
    doneToday: doneToday ?? this.doneToday,
    streak: streak ?? this.streak,
    iconCodePoint: iconCodePoint ?? this.iconCodePoint,
    activeDays: activeDays ?? this.activeDays,
    pinned: pinned ?? this.pinned,
    createdAt: createdAt,
    lastDoneDate: identical(lastDoneDate, _unset)
        ? this.lastDoneDate
        : lastDoneDate as DateTime?,
    type: type ?? this.type,
    reminderTime: reminderTime ?? this.reminderTime,
    reminderText: reminderText ?? this.reminderText,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'notes': notes,
    'status': status,
    'doneToday': doneToday,
    'streak': streak,
    'iconCodePoint': iconCodePoint,
    'activeDays': activeDays,
    'createdAt': createdAt.toIso8601String(),
    'pinned': pinned,
    'lastDoneDate': lastDoneDate?.toIso8601String(),
    'type': type,
    'reminderTime': reminderTime,
    'reminderText': reminderText,
  };

  factory Habit.fromJson(Map<String, dynamic> json) => Habit(
    id: json['id'] as String,
    name: json['name'] as String,
    notes: json['notes'] as String? ?? '',
    status: json['status'] as String? ?? '',
    doneToday: json['doneToday'] is bool
        ? (json['doneToday'] as bool)
        : json['doneToday'] is num
        ? (json['doneToday'] as num) != 0
        : false,
    streak: json['streak'] as int? ?? 0,
    iconCodePoint: json['iconCodePoint'] as int? ?? 57690,
    activeDays: (json['activeDays'] as List?)?.cast<int>() ?? const [],
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    pinned: json['pinned'] is bool
        ? (json['pinned'] as bool)
        : json['pinned'] is num
        ? (json['pinned'] as num) != 0
        : false,
    lastDoneDate: DateTime.tryParse(json['lastDoneDate'] as String? ?? ''),
    type: json['type'] as String? ?? 'good',
    reminderTime: json['reminderTime'] as String?,
    reminderText: json['reminderText'] as String?,
  );
}

String habitsToJson(List<Habit> habits) =>
    jsonEncode(habits.map((h) => h.toJson()).toList());

List<Habit> habitsFromJson(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Habit.fromJson(e as Map<String, dynamic>)).toList();
}
