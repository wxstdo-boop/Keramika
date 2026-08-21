import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/icon_map.dart';

class RealityCheck {
  final String id;
  String question;
  int totalChecks;
  DateTime? lastCheckedAt;
  int doneToday;
  bool notificationsCancelledToday;
  String? lastDoneDate;
  int iconCodePoint;
  DateTime createdAt;

  RealityCheck({
    required this.id,
    required this.question,
    this.totalChecks = 0,
    this.lastCheckedAt,
    this.doneToday = 0,
    this.notificationsCancelledToday = false,
    this.lastDoneDate,
    this.iconCodePoint = 0xe1a0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  IconData get icon => iconDataForCodePoint(iconCodePoint);

  static String todayKey() {
    // Calendar day by Moscow time (UTC+3, no DST) so streak / done-today
    // bookkeeping matches the same 00:00 boundary as HabitService.
    final n = DateTime.now().toUtc().add(const Duration(hours: 3));
    return '${n.year}-${n.month}-${n.day}';
  }

  bool get isDoneToday {
    return lastDoneDate == todayKey();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'question': question,
    'totalChecks': totalChecks,
    'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    'doneToday': doneToday,
    'notificationsCancelledToday': notificationsCancelledToday,
    'lastDoneDate': lastDoneDate,
    'iconCodePoint': iconCodePoint,
    'createdAt': createdAt.toIso8601String(),
  };

  factory RealityCheck.fromJson(Map<String, dynamic> json) => RealityCheck(
    id: json['id'] as String,
    question: json['question'] as String,
    totalChecks: json['totalChecks'] as int? ?? 0,
    lastCheckedAt: DateTime.tryParse(json['lastCheckedAt'] as String? ?? ''),
    doneToday: json['doneToday'] as int? ?? 0,
    notificationsCancelledToday: json['notificationsCancelledToday'] is bool
        ? (json['notificationsCancelledToday'] as bool)
        : json['notificationsCancelledToday'] is num
        ? (json['notificationsCancelledToday'] as num) != 0
        : false,
    lastDoneDate: json['lastDoneDate'] as String?,
    iconCodePoint: json['iconCodePoint'] as int? ?? 0xe1a0,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

String realityChecksToJson(List<RealityCheck> checks) =>
    jsonEncode(checks.map((c) => c.toJson()).toList());

List<RealityCheck> realityChecksFromJson(String json) {
  final list = jsonDecode(json) as List;
  return list
      .map((e) => RealityCheck.fromJson(e as Map<String, dynamic>))
      .toList();
}
