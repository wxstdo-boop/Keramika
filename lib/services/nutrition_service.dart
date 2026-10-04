import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/json_file.dart';
import '../services/new_year_event_service.dart';
import '../services/prefs.dart';

/// Сколько дней истории храним и показываем. Было 7 — за это время нельзя
/// было построить ни одного тренда, а запись «приёмов не больше 20»
/// означала буквально один приём в день.
const int kNutritionHistoryDays = 20;

/// То же окно после подарка 12-го дня («Полярный набор»).
const int kNutritionPrizeHistoryDays = 60;

/// Потолок записей внутри окна истории.
const int kMaxMeals = 400;

/// Личная суточная норма калорий и границы её настройки.
const int kDefaultCalorieNorm = 2000;
const int kMinCalorieNorm = 500;
const int kMaxCalorieNorm = 10000;

/// Вода: цель по умолчанию и максимум за один приём.
const int kDefaultWaterNorm = 2000;
const int kMaxWaterPerMeal = 3000;

/// Макросы приёма, граммы.
class MealMacros {
  const MealMacros({this.protein = 0, this.fat = 0, this.carbs = 0});

  final int protein;
  final int fat;
  final int carbs;

  MealMacros operator +(MealMacros o) => MealMacros(
    protein: protein + o.protein,
    fat: fat + o.fat,
    carbs: carbs + o.carbs,
  );

  int get grams => protein + fat + carbs;
}

/// Категория блюда по названию: ОДИН классификатор кормит и значок, и
/// оценку БЖУ. Раньше ключевые слова жили только в экранном `_mealIcon`, и
/// макросы пришлось бы заводить вторым таким же списком — они бы разъехались
/// при первой же правке.
///
/// Доли — какая часть КАЛОРИЙНОСТИ приходится на нутриент (в сумме 1.0).
/// Граммы считаются классически: 4 ккал на грамм белка и углевода, 9 ккал на
/// грамм жира. Это именно усреднённая оценка «по типу блюда», а не состав
/// конкретного рецепта: зато она появляется бесплатно, без единого лишнего
/// поля ввода, — ручной ввод БЖУ забрасывают вместе с самим ручным вводом.
enum MealKind {
  veggies(Icons.eco_outlined, 0.15, 0.20, 0.65),
  meat(Icons.set_meal_outlined, 0.55, 0.35, 0.10),
  fish(Icons.waves_outlined, 0.60, 0.30, 0.10),
  soup(Icons.soup_kitchen_outlined, 0.25, 0.25, 0.50),
  bread(Icons.bakery_dining_outlined, 0.20, 0.15, 0.65),
  fruit(Icons.apple_outlined, 0.05, 0.05, 0.90),
  porridge(Icons.breakfast_dining_outlined, 0.20, 0.20, 0.60),
  fastFood(Icons.lunch_dining_outlined, 0.20, 0.45, 0.35),
  dessert(Icons.cake_outlined, 0.08, 0.42, 0.50),
  egg(Icons.egg_outlined, 0.45, 0.45, 0.10),
  dairy(Icons.local_drink_outlined, 0.45, 0.35, 0.20),
  other(Icons.fastfood_outlined, 0.25, 0.35, 0.40);

  const MealKind(this.icon, this.proteinShare, this.fatShare, this.carbShare);

  final IconData icon;
  final double proteinShare;
  final double fatShare;
  final double carbShare;

  MealMacros macrosFor(int calories) => MealMacros(
    protein: (calories * proteinShare / 4).round(),
    fat: (calories * fatShare / 9).round(),
    carbs: (calories * carbShare / 4).round(),
  );

  /// Категория по названию блюда. Порядок важен: «рыба в тесте» должна
  /// достаться рыбе, а не выпечке.
  static MealKind of(String name) {
    final lower = name.toLowerCase();
    bool has(List<String> keys) => keys.any(lower.contains);
    if (has(['салат', 'овощ', 'огурц', 'помидор', 'salad', 'veg'])) {
      return MealKind.veggies;
    }
    if (has(['мяс', 'куриц', 'говядин', 'свин', 'индейк', 'meat', 'chicken'])) {
      return MealKind.meat;
    }
    if (has(['рыб', 'лосос', 'треск', 'fish', 'tuna', 'salmon'])) {
      return MealKind.fish;
    }
    if (has(['суп', 'борщ', 'бульон', 'soup'])) {
      return MealKind.soup;
    }
    if (has(['хлеб', 'тост', 'булк', 'батон', 'bread', 'toast'])) {
      return MealKind.bread;
    }
    if (has(['фрукт', 'ягод', 'яблок', 'банан', 'fruit', 'berry'])) {
      return MealKind.fruit;
    }
    if (has(['каш', 'овсян', 'гречк', 'рис', 'porridge'])) {
      return MealKind.porridge;
    }
    if (has(['пицц', 'бургер', 'доно', 'fries', 'fast'])) {
      return MealKind.fastFood;
    }
    if (has(['печен', 'торт', 'десерт', 'шоколад', 'cake', 'cookie'])) {
      return MealKind.dessert;
    }
    if (has(['яйц', 'омлет', 'egg'])) {
      return MealKind.egg;
    }
    if (has(['молоч', 'творог', 'йогурт', 'сыр', 'milk', 'yogurt', 'cheese'])) {
      return MealKind.dairy;
    }
    return MealKind.other;
  }
}

/// Приём пищи. `water` — миллилитры, 0 если вода не указывалась; запись с
/// нулём калорий и ненулевой водой — это «выпил», а не «съел».
class Meal {
  final String id;
  final String name;
  final int calories;
  final int water;
  final DateTime date;
  bool pinned;

  Meal({
    required this.id,
    required this.name,
    required this.calories,
    required this.date,
    this.water = 0,
    this.pinned = false,
  });

  bool get isWaterOnly => calories <= 0 && water > 0;

  MealKind get kind => MealKind.of(name);

  MealMacros get macros =>
      isWaterOnly ? const MealMacros() : kind.macrosFor(calories);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'calories': calories,
    'water': water,
    'date': date.toIso8601String(),
    'pinned': pinned,
  };
  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: json['id'],
    name: json['name'],
    calories: json['calories'],
    // Старые файлы данных воды не имели вовсе.
    water: (json['water'] as num?)?.toInt() ?? 0,
    date: DateTime.parse(json['date']),
    pinned: json['pinned'] ?? false,
  );
}

/// Одна точка графика трендов: сводка за календарный день.
class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.calories,
    required this.water,
    required this.meals,
    required this.macros,
  });

  final DateTime date;
  final int calories;
  final int water;
  final int meals;
  final MealMacros macros;

  bool get hasData => meals > 0;
}

class NutritionService extends ChangeNotifier {
  static final NutritionService _instance = NutritionService._();
  factory NutritionService() => _instance;
  NutritionService._();

  List<Meal> _meals = [];
  static const _key = 'nutrition_meals';
  static const _normKey = 'nutrition_calorie_norm';

  int _norm = kDefaultCalorieNorm;

  /// Личная суточная норма калорий — то, против чего меряется кольцо.
  int get norm => _norm;

  /// Окно истории: 20 дней, а с подарком 12-го дня — 60.
  int get historyDays => NewYearEventService().prizeGranted
      ? kNutritionPrizeHistoryDays
      : kNutritionHistoryDays;

  /// Видимые приёмы пищи — последние [historyDays] дней
  /// (история), закреплённые сортируются первыми. Единый фильтр для списка
  /// И калорий, чтобы счётчик сверху всегда совпадал с тем, что показано в
  /// истории. Записи с датой В БУДУЩЕМ (часовые пояса/битые данные) не
  /// считаются — иначе было «приёмов нет, а калории висят».
  bool _withinHistory(Meal m) {
    final diff = DateTime.now().difference(m.date).inDays;
    return diff >= 0 && diff < historyDays;
  }

  /// Только сегодня, по календарному дню. Норма суточная, поэтому кольцо,
  /// подписи и потолок «добавлять или нет» меряются именно по ней, а не по
  /// всем дням истории.
  static bool _isToday(Meal m) {
    final now = DateTime.now();
    final d = m.date;
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }

  int get totalCalories =>
      _meals.where(_withinHistory).fold(0, (sum, m) => sum + m.calories);

  int get todayCalories =>
      _meals.where(_isToday).fold(0, (sum, m) => sum + m.calories);

  int get todayWater =>
      _meals.where(_isToday).fold(0, (sum, m) => sum + m.water);

  int get todayMealsCount => _meals.where(_isToday).length;

  MealMacros get todayMacros => _meals
      .where(_isToday)
      .fold(const MealMacros(), (sum, m) => sum + m.macros);

  /// Дни истории от самого старого к самому новому, ровно [historyDays]
  /// штук — график всегда полной ширины, даже когда
  /// записей нет.
  List<NutritionDay> get days {
    final today = DateTime.now();
    final anchor = DateTime(today.year, today.month, today.day);
    final out = <NutritionDay>[];
    for (var back = historyDays - 1; back >= 0; back--) {
      final day = anchor.subtract(Duration(days: back));
      final onDay = _meals.where(
        (m) => _sameDay(m.date, day) && !m.date.isAfter(DateTime.now()),
      );
      out.add(
        NutritionDay(
          date: day,
          calories: onDay.fold(0, (sum, m) => sum + m.calories),
          water: onDay.fold(0, (sum, m) => sum + m.water),
          meals: onDay.length,
          macros: onDay.fold(const MealMacros(), (sum, m) => sum + m.macros),
        ),
      );
    }
    return out;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    try {
      _norm = globalPrefs.getInt(_normKey) ?? kDefaultCalorieNorm;
    } catch (_) {
      // SharedPreferences не инициализирован (тесты) — живём с дефолтом.
      _norm = kDefaultCalorieNorm;
    }
    final cutoff = DateTime.now().subtract(Duration(days: historyDays));
    _meals.removeWhere((m) => m.date.isBefore(cutoff) && !m.pinned);
    await _save();
    notifyListeners();
  }

  /// Сохранить норму. Границы зажимаются здесь, а не в виджете: лист
  /// настройки может отдать любое число.
  Future<void> setNorm(int value) async {
    final v = value.clamp(kMinCalorieNorm, kMaxCalorieNorm);
    if (v == _norm) return;
    _norm = v;
    notifyListeners();
    try {
      await globalPrefs.setInt(_normKey, v);
    } catch (_) {}
  }

  Future<void> _save() async {
    await JsonFile.write(
      _key,
      jsonEncode(_meals.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(Meal meal) async {
    if (_meals.length >= kMaxMeals) {
      throw Exception('Maximum number of meals ($kMaxMeals) reached');
    }
    if (meal.name.length > 100) {
      throw Exception('Meal name is too long');
    }
    if (meal.calories > 10000) {
      throw Exception('Calories per meal exceed maximum');
    }
    if (meal.water > kMaxWaterPerMeal) {
      throw Exception('Water per meal exceed maximum');
    }
    // Пустая запись не нужна ни в каком виде: либо название (Ада записывает
    // «я съел на обед суп» без калорийности), либо калории, либо вода.
    if (meal.name.trim().isEmpty && meal.calories <= 0 && meal.water <= 0) {
      throw Exception('Meal needs a name, calories or water');
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
      // Меняем на месте: пересоздание Meal теряло воду.
      _meals[idx].pinned = !_meals[idx].pinned;
      notifyListeners();
      await _save();
    }
  }
}
