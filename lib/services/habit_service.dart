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

  /// Данные уже загружены с диска (в main() до первого кадра).
  bool get isLoaded => _loaded;

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
      // Сравниваем и стрик, и ДАТУ: _normalizeForToday чинит «осиротевший»
      // streak>0 без lastDoneDate и «сироту» streak=0 с датой-сегодня
      // (след старого бага снятия галочки) — и этот ремонт тоже должен
      // записаться на диск.
      if (n.doneToday != h.doneToday ||
          n.streak != h.streak ||
          n.lastDoneDate != h.lastDoneDate) {
        changed = true;
      }
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
        // Осиротевший стрик (streak>0 без даты) — мёртвые данные старой
        // версии/импорта: серия без последней отметки нечитаема. Обнуляем
        // счётчик, чтобы карточка не показывала завышенную серию, а первая
        // следующая отметка честно начинала новую цепочку с 1.
        return h.copyWith(doneToday: false, streak: 0);
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
        today.day == lastDay.day) {
      // «Осиротевший» след старого бага: дата — сегодня, но стрик 0 и
      // галочка снята. Такое состояние оставлял старый код снятия (null
      // в lastDoneDate игнорировался copyWith): пользователь снял галочку,
      // стрик обнулился, а дата осталась «сегодня». Если его не починить,
      // следующая отметка застрянет в ветке re-mark со стриком 0 —
      // «снял галочку — стрик умер». Возвращаем честное состояние
      // «не отмечено»: дата стирается, отметка пойдёт по ветке «первая»
      // (стрик = 1). Нормальное состояние re-mark (doneToday + streak>=1)
      // не трогаем.
      if (!h.doneToday && h.streak <= 0) {
        return h.copyWith(lastDoneDate: null);
      }
      return h;
    }
    // День сменился. Считаем пропущенные «положенные» дни так же, как
    // в toggle(): для ежедневных привычек это календарный gap−1, для
    // расписаний — только дни, входящие в activeDays. Если пропущен хотя
    // бы один такой день — серия оборвана, и на карточке честно стоит 0
    // (а не «мёртвый» завышенный счётчик, который раньше висел до следующей
    // отметки). Пропуск чужих дней расписания стрик НЕ рвёт.
    final todayDayUtc = DateTime.utc(today.year, today.month, today.day);
    final lastDayUtc = DateTime.utc(lastDay.year, lastDay.month, lastDay.day);
    if (_missedDueDays(lastDayUtc, todayDayUtc, h.activeDays) >= 1) {
      // Состояние (streak=0, lastDone=null) всегда честное: следующая
      // отметка идёт по ветке «первая в жизни» (стрик = 1).
      return h.copyWith(doneToday: false, streak: 0, lastDoneDate: null);
    }
    return h.copyWith(doneToday: false);
  }

  /// Сброс состояния для тестов: без него синглтон «перетекает»
  /// между тестами (JsonFile в тестах не читается, load() оставляет
  /// старые привычки в памяти).
  @visibleForTesting
  void debugClear() {
    _habits = [];
    _loaded = false;
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
  ///
  /// Вредную привычку закрепить нельзя: «закрепить» — значит держать перед
  /// глазами, а перед глазами держат то, что хотят сделать. Флаг снимается
  /// здесь же, иначе он остался бы висеть в файле и привычка вернулась бы на
  /// верх после перезагрузки.
  void _normalizeOrder() {
    final pinned = <Habit>[];
    final unpinned = <Habit>[];
    for (final h in _habits) {
      if (h.pinned && h.type != 'good') h.pinned = false;
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
    // вчера (а если стрик обнулился — на null, точки пропадают).
    // ВАЖНО: lastDoneDate: null здесь РЕАЛЬНО очищает дату (copyWith
    // умеет null через сентинел) — раньше null игнорировался, дата
    // оставалась «сегодня», и повторная отметка в тот же день застревала
    // в ветке re-mark со стриком 0 (баг «снял галочку — стрик умер»).
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
      // Re-mark в тот же день: стрик и lastDone уже учтены. Защита от
      // «осиротевшего» состояния (streak 0 + дата сегодня): если стрик
      // упал до нуля, а дата осталась — отметка сегодня означает минимум
      // 1 день цепочки, иначе стрик навсегда застревает на нуле.
      newStreak = h.streak < 1 ? 1 : h.streak;
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
      // СТРОГОЕ ПРАВИЛО: стрик продолжается ТОЛЬКО пока ни один
      // «положенный» день не пропущен. Пропуск хотя бы одного такого
      // дня (missedDue >= 1) обрывает цепочку — новая серия стартует с 1.
      // Для ежедневных привычек это значит: пропуск 1 дня = сброс.
      // Для расписаний (activeDays) «положен» только свой день недели,
      // поэтому пропуск чужих дней НЕ рвёт стрик.
      final missedDue = _missedDueDays(lastDayUtc, todayDayUtc, h.activeDays);
      if (gap <= 0) {
        // Защита от глитча часовых поясов: дата в будущем или та же.
        newStreak = h.streak;
        newLastDate = h.lastDoneDate!;
      } else if (missedDue == 0) {
        // Все «положенные» дни между последней отметкой и сегодня
        // выполнены — цепочка продолжает расти.
        newStreak = h.streak + 1;
        newLastDate = today;
      } else {
        // Пропущен хотя бы 1 «положенный» день (missedDue >= 1) —
        // цепочка оборвана, новая серия начинается с 1.
        newStreak = 1;
        newLastDate = today;
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

  /// Сколько «положенных» дней пропущено МЕЖДУ последней отметкой и
  /// сегодня (границы не считаются: lastDay уже отмечен, today
  /// отмечается прямо сейчас). Для привычек без activeDays «положен»
  /// каждый день — результат = календарный gap − 1. Для привычек с
  /// расписанием считаются только дни, чей weekday входит в activeDays.
  /// Loop ограничен 366 итерациями: за год каждый weekday встречается,
  /// дальнейший подсчёт не имеет смысла.
  static int _missedDueDays(
    DateTime lastDayUtc,
    DateTime todayUtc,
    List<int> activeDays,
  ) {
    if (activeDays.isEmpty) {
      return todayUtc.difference(lastDayUtc).inDays - 1;
    }
    var missed = 0;
    var d = lastDayUtc.add(const Duration(days: 1));
    for (var i = 0; i < 366 && d.isBefore(todayUtc); i++) {
      if (activeDays.contains(d.weekday)) missed++;
      d = d.add(const Duration(days: 1));
    }
    return missed;
  }

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
    // Текст напоминания в списке привычек НЕ показываем — он живёт
    // в самом уведомлении: если задан «текст напоминания», показываем
    // его, иначе стандартное «Пора вспомнить: <имя>».
    final custom = h.reminderText?.trim();
    final body = (custom != null && custom.isNotEmpty)
        ? custom
        : 'Пора вспомнить: ${h.name}';
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
    return '$prefix 🌱 $habitName';
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _habits.length) return;
    if (newIndex < 0 || newIndex > _habits.length) return;
    if (oldIndex == newIndex) return;
    // Pinned-привычки живут в начале списка. Не-pinned, которую пытаются
    // перетащить в pinned-зону (выше), не пускаем: порядок pinned сохранён.
    // Pinned между собой переставляются свободно.
    final pinnedCount = _habits.where((h) => h.pinned).length;
    if (! _habits[oldIndex].pinned && newIndex < pinnedCount) return;
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
