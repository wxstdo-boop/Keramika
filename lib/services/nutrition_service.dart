import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/json_file.dart';

class Meal {
  final String id;
  final String name;
  final int calories;
  final DateTime date;
  bool pinned;

  Meal({
    required this.id,
    required this.name,
    required this.calories,
    required this.date,
    this.pinned = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'calories': calories,
    'date': date.toIso8601String(),
    'pinned': pinned,
  };
  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: json['id'],
    name: json['name'],
    calories: json['calories'],
    date: DateTime.parse(json['date']),
    pinned: json['pinned'] ?? false,
  );
}

class NutritionService extends ChangeNotifier {
  static final NutritionService _instance = NutritionService._();
  factory NutritionService() => _instance;
  NutritionService._();

  List<Meal> _meals = [];
  static const _key = 'nutrition_meals';

  /// Видимые приёмы пищи — только последние 7 дней (история), закреплённые
  /// сортируются первыми. Единый фильтр для списка И калорий, чтобы счётчик
  /// сверху всегда совпадал с тем, что показано в истории. Записи с датой
  /// В БУДУЩЕМ (часовые пояса/битые данные) не считаются — иначе было
  /// «приёмов нет, а калории висят».
  static bool _withinHistory(Meal m) {
    final diff = DateTime.now().difference(m.date).inDays;
    return diff >= 0 && diff < 7;
  }

  int get totalCalories =>
      _meals.where(_withinHistory).fold(0, (sum, m) => sum + m.calories);

  List<Meal> get meals => List.unmodifiable(
    _meals.where(_withinHistory).toList()..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.date.compareTo(a.date);
    }),
  );

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null) {
        final data = jsonDecode(raw) as List;
        _meals = data.map((e) => Meal.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('Error loading nutrition data: $e');
      _meals = [];
    }
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    _meals.removeWhere((m) => m.date.isBefore(cutoff) && !m.pinned);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    await JsonFile.write(
      _key,
      jsonEncode(_meals.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(Meal meal) async {
    if (_meals.length >= 20) {
      throw Exception('Maximum number of meals (20) reached');
    }
    if (meal.name.length > 100) {
      throw Exception('Meal name is too long');
    }
    if (meal.calories > 10000) {
      throw Exception('Calories per meal exceed maximum');
    }
    _meals.add(meal);
    try {
      await _save();
      notifyListeners();
    } catch (e) {
      _meals.remove(meal);
      debugPrint('Error saving nutrition data: $e');
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    _meals.removeWhere((m) => m.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> togglePin(String id) async {
    final idx = _meals.indexWhere((m) => m.id == id);
    if (idx != -1) {
      _meals[idx] = Meal(
        id: _meals[idx].id,
        name: _meals[idx].name,
        calories: _meals[idx].calories,
        date: _meals[idx].date,
        pinned: !_meals[idx].pinned,
      );
      notifyListeners();
      await _save();
    }
  }
}
