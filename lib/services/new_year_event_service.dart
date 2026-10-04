import 'dart:convert';
import 'package:flutter/material.dart';
import 'json_file.dart';
import 'prefs.dart';

/// Новый год 2027 — каждый день дарят по одной шапке.
/// Пользователь открывает приложение в день D и забирает шапку дня («Забрать»).
/// За день выдаётся ровно одна, до 31.12 накапливается 12 шапок; на сам НГ —
/// финальный день ивента.
///
/// Формат файла: {'2026-12-21': true, '2026-12-23': true, ...}
/// Ключ = дата в формате YYYY-MM-DD, значение = true когда шапка забрана.
class NewYearEventService extends ChangeNotifier {
  static final NewYearEventService _instance = NewYearEventService._();
  factory NewYearEventService() => _instance;
  NewYearEventService._();

  static const String _fileKey = 'ny_event_2027';

  /// Подарок ивента выдан — хранится ОТДЕЛЬНО от файла шапок. В файле лежат
  /// только даты-булевы, и служебный ключ внутри него [hatCount] посчитал бы
  /// как ещё одну шапку.
  static const String _prizeKey = 'ny_prize_2027';

  // Даты ивента: 12 дней от 21.12.2026 до 01.01.2027 включительно.
  static const int totalDays = 12;
  static final DateTime _start = DateTime(2026, 12, 21);

  /// Исключительная граница: 01.01 вечером ещё внутри ивента, 02.01 — уже нет.
  static final DateTime _end = DateTime(2026, 12, 21 + totalDays);

  /// Тестовая панель: пока true — ивент доступен в любую дату, иначе его
  /// нельзя проверить до 21 декабря. В бою переключить в false.
  static const bool _forceActive = true;
  static bool get isActive =>
      _forceActive ||
      (DateTime.now().isAfter(_start.subtract(const Duration(days: 1))) &&
          DateTime.now().isBefore(_end));

  /// Ивент открыт не по календарю, а насильно (тест). По нему же решается,
  /// что делать с забором в просмотре дня: в тесте он доезжает до показанного
  /// дня по-настоящему (см. [fillTo]), в бою — только возвращает к своему дню.
  static bool get isTestMode => _forceActive;

  /// Сколько шапок забрано. Кэшируется при каждом чтении файла, чтобы номер
  /// дня и состояние подарка были доступны синхронно (в виджете дня нет
  /// никакой асинхронщины).
  int _hats = 0;
  int get hats => _hats;

  /// Номер показываемого дня = сколько шапок уже есть + 1, то есть какая
  /// шапка следующая. По календарю эти числа совпадают (за день выдаётся
  /// ровно одна), а вне календаря дней просто нет — иначе ивент, сдвинутый
  /// на тестирование, вечно показывал бы «день 1».
  int get currentDay => (_hats + 1).clamp(1, totalDays);

  /// Подарок 12-го дня выдан навсегда.
  bool get prizeGranted {
    try {
      return globalPrefs.getBool(_prizeKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Выдать подарок. Повторный вызов безвреден.
  ///
  /// Возвращает true, только если флаг реально лег на диск: без проверки тема
  /// включалась в интерфейсе, а после перезапуска подарок исчезал — ровно та
  /// же причина, что и с «пропавшими шапками».
  Future<bool> grantPrize() async {
    if (prizeGranted) return true;
    try {
      await globalPrefs.setBool(_prizeKey, true);
    } catch (_) {}
    notifyListeners();
    return prizeGranted;
  }

  Future<Map<String, bool>> _load() async {
    final raw = await JsonFile.read(_fileKey);
    if (raw == null || raw.isEmpty) {
      _hats = 0;
      return {};
    }
    try {
      final map = Map<String, bool>.from(jsonDecode(raw) as Map);
      _hats = map.values.where((v) => v).length;
      return map;
    } catch (_) {
      _hats = 0;
      return {};
    }
  }

  /// Пишем и СРАЗУ читаем обратно. [JsonFile.write] глотает любую ошибку
  /// молча, и без проверки шапка в интерфейсе «забрана», а после перезапуска
  /// оказывается, что на диске её нет — вот он «прогресс сбрасывается».
  Future<void> _save(Map<String, bool> data) async {
    final payload = jsonEncode(data);
    await JsonFile.write(_fileKey, payload);
    if (await JsonFile.read(_fileKey) != payload) {
      throw Exception('Не удалось сохранить прогресс ивента');
    }
    _hats = data.values.where((v) => v).length;
  }

  /// Есть ли отметка за конкретную дату?
  Future<bool> isMarked(String date) async {
    final map = await _load();
    return map[date] == true;
  }

  /// Отметить сегодня как «шапка забрана» (если ещё не забрана).
  /// Возвращает false, если сегодня уже забрано; кидает, если не записалось.
  Future<bool> markToday() async {
    if (!isActive) return false;
    final today = _todayKey();
    final map = await _load();
    if (map[today] == true) return false;
    map[today] = true;
    await _save(map);
    notifyListeners();
    return true;
  }

  /// Довести коллекцию до первых [n] дней ивента, записав их календарные даты.
  ///
  /// Нужно потому, что шапка выдаётся ровно раз в календарный день: на
  /// тестовой сборке ([isTestMode]) 12 дней ждать физически невозможно, и без
  /// этой доводки 12-й день вместе с подарком просто недостижимы. В бою
  /// вызова нет — там просмотр дня ничего не пишет.
  Future<void> fillTo(int n) async {
    final days = n.clamp(1, totalDays);
    final map = await _load();
    for (var i = 0; i < days; i++) {
      final d = DateTime(_start.year, _start.month, _start.day + i);
      map['${d.year}-${_pad(d.month)}-${_pad(d.day)}'] = true;
    }
    await _save(map);
    notifyListeners();
  }

  /// Сколько шапок накоплено.
  Future<int> hatCount() async {
    await _load();
    return _hats;
  }

  /// Полностью обнулить накопленное. Скрытая отладка: долгое нажатие на
  /// крестик в окне ивента — без неё ивент привязан к календарю и его
  /// невозможно перепроверить в одну и ту же дату.
  ///
  /// Сброс отбирает и подарок (тема «Метель», скин скважины, расширенные
  /// лимиты): по словам автора, «сбрасываешь 12-й день — всё это пропадает».
  /// Иначе остаётся дыра: тема выключена в интерфейсе, а флаг приза живёт, и
  /// на следующем старте подарок возвращается сам.
  Future<void> reset() async {
    await _save(const {});
    try {
      await globalPrefs.setBool(_prizeKey, false);
    } catch (_) {}
    notifyListeners();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Форматирует дату ключа в читаемый вид «21 дек».
  static String formatDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    final m = int.parse(parts[1]);
    final d = int.parse(parts[2]);
    const months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    return '$d ${months[m - 1]}';
  }
}
