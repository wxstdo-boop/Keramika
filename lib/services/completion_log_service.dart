import 'dart:convert';
import 'package:flutter/material.dart';
import 'habit_service.dart';
import 'json_file.dart';
import 'task_service.dart';

/// Лог выполнения по дням (привычки + задачи). Хранит реальную историю
/// с момента установки этой версии; для дней, которые прошли ДО лога,
/// график дозаполняется реконструкцией из streak привычек (цепочка
/// «последние N дней выполнены»).
class DayCompletion {
  /// Дата 'yyyy-MM-dd' (по Москве — как считаются стрики).
  final String date;
  final int habits;
  final int tasks;

  const DayCompletion({
    required this.date,
    required this.habits,
    required this.tasks,
  });

  Map<String, dynamic> toJson() => {'d': date, 'h': habits, 't': tasks};

  factory DayCompletion.fromJson(Map<String, dynamic> j) => DayCompletion(
    date: j['d'] as String,
    habits: (j['h'] as num?)?.toInt() ?? 0,
    tasks: (j['t'] as num?)?.toInt() ?? 0,
  );
}

class CompletionLogService extends ChangeNotifier {
  static final CompletionLogService _instance = CompletionLogService._();
  factory CompletionLogService() => _instance;
  CompletionLogService._();

  static const _key = 'completion_log';
  final Map<String, DayCompletion> _log = {};
  bool _loaded = false;

  /// 'yyyy-MM-dd' по Москве (совпадает с датами стриков).
  static String dayKey(DateTime msk) =>
      '${msk.year.toString().padLeft(4, '0')}-'
      '${msk.month.toString().padLeft(2, '0')}-'
      '${msk.day.toString().padLeft(2, '0')}';

  Map<String, DayCompletion> get log => Map.unmodifiable(_log);

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          final d = DayCompletion.fromJson(e as Map<String, dynamic>);
          _log[d.date] = d;
        }
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    final list = _log.values
        .map((d) => d.toJson())
        .toList()
      ..sort((a, b) => (a['d'] as String).compareTo(b['d'] as String));
    await JsonFile.write(_key, jsonEncode(list));
  }

  /// Записывает/обновляет «сегодня» и сохраняет. Вызывается при каждом
  /// открытии статистики — лог постепенно накапливает реальную историю.
  Future<void> recordToday() async {
    if (!_loaded) return;
    final habits = HabitService()
        .habits
        .where((h) => h.doneToday)
        .length;
    final tasks = TaskService().tasks.where((t) => t.done).length;
    final key = dayKey(HabitService.mskToday());
    final prev = _log[key];
    // Не перезаписываем большим числом, если пользователь снял галочки
    // позже — берём максимум, чтобы график отражал «пик» дня.
    final merged = DayCompletion(
      date: key,
      habits: prev == null ? habits : (prev.habits > habits ? prev.habits : habits),
      tasks: prev == null ? tasks : (prev.tasks > tasks ? prev.tasks : tasks),
    );
    if (prev == null ||
        prev.habits != merged.habits ||
        prev.tasks != merged.tasks) {
      _log[key] = merged;
      notifyListeners();
      await _save();
    }
  }

  /// Последние [days] дней (включая сегодня), по Москве. Дни, которых нет
  /// в логе, заполняются реконструкцией из streak привычек: если цепочка
  /// привычки длиннее «давности» дня — день считается выполненным.
  List<DayCompletion> lastDays(int days) {
    final today = HabitService.mskToday();
    final habits = HabitService().habits;
    final result = <DayCompletion>[];
    for (var i = days - 1; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final key = dayKey(day);
      final cached = _log[key];
      if (cached != null) {
        result.add(cached);
        continue;
      }
      // Реконструкция по стрикам: цепочка «непрерывных» дней покрывает
      // i дней назад, если streak > i (учитываем, что streak включает
      // сегодня, а lastDoneDate стоит на конце цепочки).
      var habitsDone = 0;
      final dayMsk = day;
      for (final h in habits) {
        if (h.lastDoneDate == null || h.streak <= 0) continue;
        final last = h.lastDoneDate!;
        // streak — длина цепочки, заканчивающейся на lastDoneDate.
        // День day «внутри» цепочки, если last - day < streak.
        final diffDays = dayMsk
            .difference(DateTime(last.year, last.month, last.day))
            .inDays;
        if (diffDays >= 0 && diffDays < h.streak) habitsDone++;
      }
      result.add(DayCompletion(date: key, habits: habitsDone, tasks: 0));
    }
    return result;
  }
}
