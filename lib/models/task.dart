import 'dart:convert';
import 'package:flutter/material.dart';
import '../utils/icon_map.dart';

class Task {
  final String id;
  String title;
  bool done;
  int iconCodePoint;
  String category;
  int priority;
  String note;
  DateTime createdAt;

  Task({
    required this.id,
    required this.title,
    this.done = false,
    this.iconCodePoint = 58830,
    this.category = '',
    this.priority = 0,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  IconData get icon => iconDataForCodePoint(iconCodePoint);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'done': done,
    'iconCodePoint': iconCodePoint,
    'category': category,
    'priority': priority,
    'note': note,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: json['id'] as String,
    title: json['title'] as String,
    done: json['done'] is bool
        ? (json['done'] as bool)
        : json['done'] is num
        ? (json['done'] as num) != 0
        : false,
    iconCodePoint: json['iconCodePoint'] as int? ?? 58830,
    category: json['category'] as String? ?? '',
    priority: json['priority'] as int? ?? 0,
    note: json['note'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
  );
}

String tasksToJson(List<Task> tasks) =>
    jsonEncode(tasks.map((t) => t.toJson()).toList());

List<Task> tasksFromJson(String json) {
  final list = jsonDecode(json) as List;
  return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
}
