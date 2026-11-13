import 'package:flutter/foundation.dart';

import 'prefs.dart';

/// Категория начисления очков «Agysha-рейтинга». Каждая — за реальное
/// действие в приложении, поэтому цифра в рейтинге что-то значит, а не
/// рисуется случайно.
enum ScoreKind {
  /// Отметка привычки (очки за стрик).
  habit,

  /// Выполненная задача.
  task,

  /// Сообщение Аде (общение с ИИ).
  ai,

  /// Записанный приём пищи.
  meal,

  /// Пройденная проверка реальности (РП).
  check,

  /// Активный день (в нём была хоть какая-то активность).
  day,
}

/// Веса категорий. Держим в одном месте: и рейтинг, и разбор «за что очки»
/// считаются отсюда, поэтому подписи в интерфейсе не разъедутся со счётом.
class ScoreWeight {
  static const int habitPerStreak = 1;
  static const int task = 1;
  static const int ai = 2;
  static const int meal = 3;
  static const int check = 2;
  static const int activeDay = 3;
}

/// Счётчик «Agysha-очков» — ПОЖИЗНЕННЫЙ (не сбрасывается).
///
/// Раньше рейтинг считался только из ТЕКУЩИХ стриков и числа невыполненных
/// задач: стоило снять галочку или потерять стрик — очки падали, и цифра
/// ничего не значила. Теперь копилка растёт от каждого действия (привычка,
/// задача, сообщение Аде, приём пищи, проверка реальности, активный день) и
/// только прибавляется, поэтому рейтинг читается как достижение.
///
/// Счёт ведётся ПО КАТЕГОРИЯМ: сумма и разбор «за что очки» берутся из
/// одного места, а не пересчитываются двумя путями.
class ScoreService extends ChangeNotifier {
  ScoreService._();
  static final ScoreService _instance = ScoreService._();
  factory ScoreService() => _instance;

  static const String _prefix = 'score_';

  /// Кэш значений в памяти: prefs читается синхронно, но с диска, а рейтинг
  /// опрашивается на каждой перерисовке профиля.
  final Map<ScoreKind, int> _cache = {};

  bool _loaded = false;
  bool get loaded => _loaded;

  static String _key(ScoreKind kind) => '$_prefix${kind.name}';

  int pointsOf(ScoreKind kind) => _cache[kind] ??= _read(kind);

  int _read(ScoreKind kind) {
    try {
      return globalPrefs.getInt(_key(kind)) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Итог копилки: сумма очков по всем категориям.
  int get total {
    var sum = 0;
    for (final kind in ScoreKind.values) {
      sum += pointsOf(kind);
    }
    return sum;
  }

  /// Разбор по категориям для интерфейса: «за что начислено».
  Map<ScoreKind, int> get breakdown => {
    for (final kind in ScoreKind.values) kind: pointsOf(kind),
  };

  /// Сколько очков приносит одна единица категории (для подписей).
  static int weightOf(ScoreKind kind) => switch (kind) {
    ScoreKind.habit => ScoreWeight.habitPerStreak,
    ScoreKind.task => ScoreWeight.task,
    ScoreKind.ai => ScoreWeight.ai,
    ScoreKind.meal => ScoreWeight.meal,
    ScoreKind.check => ScoreWeight.check,
    ScoreKind.day => ScoreWeight.activeDay,
  };

  /// Загрузить копилку с диска (вызывается в main() вместе с остальными).
  Future<void> load() async {
    _cache.clear();
    for (final kind in ScoreKind.values) {
      _cache[kind] = _read(kind);
    }
    _loaded = true;
    notifyListeners();
  }

  /// Начислить очки за действие. [count] — сколько единиц (например, длина
  /// стрика за привычку). Считаем ТОЛЬКО прибавление: снятие галочки копилку
  /// не уменьшает — достижения не отбираем.
  Future<void> award(ScoreKind kind, [int count = 1]) async {
    if (count <= 0) return;
    final next = pointsOf(kind) + count * weightOf(kind);
    _cache[kind] = next;
    notifyListeners();
    try {
      await globalPrefs.setInt(_key(kind), next);
    } catch (_) {}
  }

  /// Очки за АКТИВНЫЙ ДЕНЬ: начисляются один раз в сутки — при первом
  /// действии дня (отметил привычку, закрыл задачу, написал Аде). Ключ дня
  /// не даёт «нафармить» их повторными тапами.
  Future<void> markActiveDay() async {
    final today = _dayKey();
    try {
      if (globalPrefs.getString(_activeDayKey) == today) return;
      await globalPrefs.setString(_activeDayKey, today);
    } catch (_) {
      return;
    }
    await award(ScoreKind.day);
  }

  static const String _activeDayKey = 'score_active_day';

  String _dayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  /// Сбросить копилку (для тестов и «сброса статистики»).
  Future<void> reset() async {
    for (final kind in ScoreKind.values) {
      _cache[kind] = 0;
      try {
        await globalPrefs.remove(_key(kind));
      } catch (_) {}
    }
    notifyListeners();
  }
}
