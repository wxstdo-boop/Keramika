import 'package:flutter/material.dart';
import '../models/habit.dart';
import 'json_file.dart';
import 'notification_service_instance.dart';
import 'settings_service.dart';

class HabitService extends ChangeNotifier {
  static final HabitService _instance = HabitService._();
  factory HabitService() => _instance;
  HabitService._();

  List<Habit> _habits = [];
  bool _loaded = false;
  static const _key = 'habits';

  List<Habit> get habits => List.unmodifiable(_habits);

  /// Текущий момент по Москве (UTC+3, без DST). Все сравнения
  /// «отмечено сегодня» идут через него, чтобы галочка сбрасывалась
  /// ровно в 00:00 МСК независимо от часового пояса телефона.
  static DateTime mskNow() =>
      DateTime.now().toUtc().add(const Duration(hours: 3));

  /// Дата по Москве (без времени).
  static DateTime mskToday() {
    final m = mskNow();
    return DateTime(m.year, m.month, m.day);
  }

  /// Перепроверяет в памяти флаг doneToday на основе MSK-даты.
  /// Вызывается из app-resume (главный state) — если пользователь
  /// оставил приложение открытым через полночь, галочки сбросятся
  /// корректно даже без перезапуска процесса.
  void normalizeIfDayChanged() {
    if (!_loaded) return;
    bool changed = false;
    final out = <Habit>[];
    for (final h in _habits) {
      final n = _normalizeForToday(h);
      // Сравниваем и стрик: _normalizeForToday чинит «осиротевший»
      // streak>0 без lastDoneDate (мёртвые данные старой версии),
      // и этот ремонт тоже должен записаться на диск.
      if (n.doneToday != h.doneToday || n.streak != h.streak) changed = true;
      out.add(n);
    }
    if (!changed) return;
    _habits = out;
    notifyListeners();
    _save();
  }

  /// Сбрасывает doneToday, если привычка НЕ была отмечена по Москве
  /// сегодня. Streak НЕ трогает — им управляет toggle().
  Habit _normalizeForToday(Habit h) {
    if (h.lastDoneDate == null) {
      // Никогда не отмечалась (или был сброс стрика). Флага doneToday
      // быть не должно. Плюс ремонт «осиротевшего» стрика: streak>0
      // без lastDoneDate — мёртвые данные (старая версия/импорт).
      // Если их не обнулить, первая же отметка «оживит» старый счётчик
      // и стрик поведёт себя так, будто сброса не было.
      if (h.streak > 0) {
        return h.copyWith(streak: 0, doneToday: false);
      }
      return h.doneToday ? h.copyWith(doneToday: false) : h;
    }
    final today = mskToday();
    final lastDay = DateTime(
      h.lastDoneDate!.year,
      h.lastDoneDate!.month,
      h.lastDoneDate!.day,
    );
    if (today.year == lastDay.year &&
        today.month == lastDay.month &&
        today.day == lastDay.day)
      return h;
    // День сменился. Если между последней отметкой и сегодня пропущено
    // 2+ дня — цепочка фактически оборвана: честно сбрасываем стрик прямо
    // здесь, а не только при следующем toggle. Иначе на карточке висит
    // «мёртвый» завышенный счётчик (например, 6 точек после недельного
    // перерыва), и следующая отметка выглядит как «стрик 2» вместо нового
    // начала — именно этот эффект и есть «на второй день считает как два».
    if (today.difference(lastDay).inDays >= 2) {
      return h.copyWith(doneToday: false, streak: 0);
    }
    return h.copyWith(doneToday: false);
  }

  Future<void> load() async {
    List<Habit>? normalized;
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        normalized = habitsFromJson(raw).map(_normalizeForToday).toList();
      }
    } catch (_) {}
    _habits = normalized ?? _habits;
    // _loaded должен стать true ДО _save(), иначе _save() выйдет по гарду
    // и нормализованное состояние не запишется на диск.
    _loaded = true;
    _normalizeOrder();
    if (normalized != null) {
      // фиксируем нормализацию один раз, чтобы при следующем запуске не считать diff заново
      await _save();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    await JsonFile.write(_key, habitsToJson(_habits));
  }

  /// Keeps pinned habits at the top of the list while preserving the
  /// user-defined relative order inside each group.
  void _normalizeOrder() {
    final pinned = <Habit>[];
    final unpinned = <Habit>[];
    for (final h in _habits) {
      if (h.pinned) {
        pinned.add(h);
      } else {
        unpinned.add(h);
      }
    }
    _habits = [...pinned, ...unpinned];
  }

  /// Детерминированный id уведомления привычки (10000–16383): от него
  /// откладываются 8 слотов — 0 = «каждый день», 1–7 = дни недели.
  static int _notifBase(String habitId) => 10000 + (habitId.hashCode & 0x3fff);

  Future<void> add(Habit habit) async {
    _habits.add(habit);
    _normalizeOrder();
    notifyListeners();
    await _save();
    await _scheduleReminder(habit);
  }

  Future<void> remove(String id) async {
    _habits.removeWhere((h) => h.id == id);
    notifyListeners();
    await _save();
    await cancelReminderFor(id);
  }

  Future<void> toggle(String id) async {
    final idx = _habits.indexWhere((h) => h.id == id);
    if (idx == -1) return;
    final h = _normalizeForToday(_habits[idx]);

    // Снимаем отметку «сегодня». Цепочка стрика укорачивается на 1 день:
    // сегодняшний день больше не засчитан, lastDoneDate откатывается на
    // вчера (а если стрик обнулился — на null, точки пропадают). Раньше
    // стрик оставался «висеть» после снятия галочки — день числился и
    // в цепочке, и снятым одновременно.
    if (h.doneToday) {
      if (h.type == 'good' && h.streak > 0) {
        final newStreak = h.streak - 1;
        final yesterday = mskToday().subtract(const Duration(days: 1));
        _habits[idx] = h.copyWith(
          doneToday: false,
          streak: newStreak,
          lastDoneDate: newStreak > 0 ? yesterday : null,
        );
      } else {
        _habits[idx] = h.copyWith(doneToday: false);
      }
      _normalizeOrder();
      notifyListeners();
      await _save();
      return;
    }

    // Ставим отметку «сегодня». newStreak/newLastDate получают
    // разумные дефолты — все реальные ветки (ниже) их перебивают,
    // а Dart-овский анализатор определённого присвоения видит, что
    // переменные уже присвоены и не требует завершающего else.
    final today = mskToday();
    int newStreak = h.streak;
    DateTime newLastDate = today;

    if (h.type != 'good') {
      // Вредная привычка: цепочки нет, только фикс даты.
      newStreak = h.streak;
      newLastDate = today;
    } else if (h.lastDoneDate == null) {
      // Первая в жизни отметка: streak начинается с 1.
      newStreak = 1;
      newLastDate = today;
    } else if (_sameLocalDay(h.lastDoneDate!, today)) {
      // Re-mark в тот же день: стрик и lastDone уже учтены.
      newStreak = h.streak;
      newLastDate = h.lastDoneDate!;
    } else {
      // Соседний день или пропуск. Сравниваем через UTC-midnight,
      // а не LOCAL, чтобы расчёт не плавал вокруг 00:00 в часовых
      // поясах вроде UTC-10..UTC+14 (раньше .inDays мог округлить
      // 23-часовой или 25-часовой гэп к 0, и код считал, что
      // «уже отмечено сегодня» → стрик молча оставался прежним).
      final todayDayUtc = DateTime.utc(today.year, today.month, today.day);
      final lastDayUtc = DateTime.utc(
        h.lastDoneDate!.year,
        h.lastDoneDate!.month,
        h.lastDoneDate!.day,
      );
      final gap = todayDayUtc.difference(lastDayUtc).inDays;
      if (gap >= 2) {
        // Пропуск — цепочка оборвана, начинаем новую.
        newStreak = 1;
        newLastDate = today;
      } else if (gap == 1) {
        // Соседний день — продлеваем цепочку.
        newStreak = h.streak + 1;
        newLastDate = today;
      } else if (gap <= 0) {
        // Защита от глитча часовых поясов: lastDone == today (та же
        // дата) или в будущем. такое возможно, если устройство только
        // что переехало в другой TZ. Не сбрасываем стрик ниже
        // сохранённого значения и не двигаем дату назад.
        newStreak = h.streak;
        newLastDate = h.lastDoneDate!;
      }
    }

    _habits[idx] = h.copyWith(
      doneToday: true,
      streak: newStreak,
      lastDoneDate: newLastDate,
    );
    _normalizeOrder();
    notifyListeners();
    await _save();
  }

  static bool _sameLocalDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> update(Habit habit) async {
    final idx = _habits.indexWhere((h) => h.id == habit.id);
    if (idx != -1) {
      _habits[idx] = habit;
      _normalizeOrder();
      notifyListeners();
      await _save();
      await cancelReminderFor(habit.id);
      await _scheduleReminder(habit);
    }
  }

  /// Планирует напоминание «Вспомнить всё» для привычки (если задано
  /// время): каждый день или по выбранным дням недели.
  Future<void> _scheduleReminder(Habit h) async {
    final time = h.reminderTime;
    if (time == null || !time.contains(':')) return;
    final parts = time.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = int.tryParse(parts[1]) ?? 0;
    final base = _notifBase(h.id);
    final body = 'Пора вспомнить: ${h.name}';
    String lang = 'ru';
    try {
      lang = await SettingsService.loadLanguageCode();
    } catch (_) {}
    final localTitle = _reminderTitle(h.name, lang);
    if (h.activeDays.isEmpty) {
      await notificationService.scheduleHabitReminder(
        base,
        0,
        hour,
        minute,
        localTitle,
        body,
        payload: 'habit:${h.id}',
      );
    } else {
      for (final day in h.activeDays) {
        await notificationService.scheduleHabitReminder(
          base + day,
          day,
          hour,
          minute,
          localTitle,
          body,
          payload: 'habit:${h.id}',
        );
      }
    }
  }

  /// Отменяет все напоминания привычки (все слоты).
  Future<void> cancelReminderFor(String habitId) async {
    final base = _notifBase(habitId);
    for (var d = 0; d <= 7; d++) {
      await notificationService.cancelReminder(base + d);
    }
  }

  /// Перепланирует напоминания всех привычек (старт приложения / возврат
  /// из фона) — система могла потерять их, пока приложение не работало.
  Future<void> rescheduleAllReminders() async {
    if (!_loaded) await load();
    for (final h in _habits) {
      await cancelReminderFor(h.id);
      await _scheduleReminder(h);
    }
  }

  /// Заголовок напоминания в локали приложения.
  static String _reminderTitle(String habitName, String lang) {
    final prefix = lang == 'ru'
        ? 'Вспомнить всё'
        : lang == 'fr'
        ? 'Rappelle-toi'
        : 'Remember';
    return '$prefix 🌱 ${habitName}';
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _habits.length) return;
    if (newIndex < 0 || newIndex > _habits.length) return;
    if (oldIndex == newIndex) return;
    // The UI uses ReorderableListView.onReorderItem, which already gives
    // newIndex for the list after the dragged item is removed.
    final item = _habits.removeAt(oldIndex);
    _habits.insert(newIndex, item);
    _normalizeOrder();
    notifyListeners();
    await _save();
  }

  Future<void> forceSave() async {
    await _save();
  }
}
