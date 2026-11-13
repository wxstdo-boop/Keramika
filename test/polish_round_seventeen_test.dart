import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест круга 17: жалобы на кольцо музыки, окно ивента, кнопки
/// «Забрать»/«Сбросить», профиль и статистику.
///
/// Каждая проверка закрывает конкретную жалобу владельца:
///  * кольцо музыки — ОДИН слой и один `RepaintBoundary`, ни `MaskFilter`,
///    ни `AnimatedOpacity` над ним;
///  * «День N из 12» больше не дублируется: день назван один раз, в бейдже;
///  * заголовок ивента не делит строку с бейджем — не ужимается;
///  * кнопка «Забрать» — в брендовом алом, а не в сиреневом `primary`;
///  * зажатие кнопки ивента монотонное (`easeInOut`, без «щелчка»);
///  * окно «Сбросить ивент» — своя карточка с мягкой отдачей кнопок;
///  * в профиле у «добавить друга» тонкая полупрозрачная красная оправа;
///  * статистика не пересчитывает и не перерисовывает график на каждой
///    пересборке (кэш 30 дней + сравнение по содержимому).
void main() {
  String read(String path) {
    final f = File(path);
    expect(
      f.existsSync(),
      isTrue,
      reason: '$path не найден — тест не из корня',
    );
    return f.readAsStringSync();
  }

  /// Код без строк-комментариев: иначе проверки «нет MaskFilter» ловят сами
  /// пояснения, в которых это слово упомянуто.
  String code(String path) => read(
    path,
  ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('кольцо музыки: один слой, без MaskFilter и AnimatedOpacity', () {
    final src = code('lib/widgets/music_pulse_ring.dart');
    expect(
      src.contains('MaskFilter'),
      isFalse,
      reason: 'размытие тени стоило слоя и давало «грязную» кромку',
    );
    expect(
      src.contains('AnimatedOpacity'),
      isFalse,
      reason: 'прозрачность считает painter — отдельный слой не нужен',
    );
    expect(
      RegExp(r'RepaintBoundary\(').allMatches(src).length,
      1,
      reason: 'кольцо живёт в одном слое',
    );
    // Пульс — расходящиеся волны: опорная кромка у кнопки и три волны в
    // пути. Все — обводкой, без заливки и без перелива тона.
    expect(
      RegExp(r'canvas\.drawCircle\(').allMatches(src).length,
      2,
      reason: 'опорная кромка и волны — один вызов на каждую',
    );
    expect(
      src.contains('SweepGradient'),
      isFalse,
      reason: 'перелив тона по кругу читался миганием',
    );
  });
  test('ивент: день назван один раз — в бейдже, а не и в подписи', () {
    final l10n = read('lib/l10n/translations.dart');
    // «День {0} из 12» осталось только у заголовка-шаблона? Нет: дубль убран
    // из подписи, поэтому ни в одной локали {0} в nyEventBody не осталось.
    final bodies = RegExp(
      r"'nyEventBody': '([^']*)'",
    ).allMatches(l10n).map((m) => m.group(1)!).toList();
    expect(bodies.length, 3, reason: 'ru/en/fr — три подписи');
    for (final body in bodies) {
      expect(
        body.contains('{0}'),
        isFalse,
        reason: 'день в подписи дублировал бейдж «N / 12»',
      );
    }
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(
      RegExp(r'_DayBadge\(').allMatches(src).length,
      2,
      reason: 'один вызов бейджа + его объявление',
    );
    expect(
      src.contains("swapKey: isFinalDay ? 'final' : 'day',"),
      isTrue,
      reason: 'подпись больше не пересоздаётся от смены дня',
    );
  });

  test('ивент: заголовок занимает всю строку и не ужимается бейджем', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final title = src.indexOf("Translations.t('nyEventTitle', context)");
    expect(title, greaterThan(0));
    // Бейдж дня идёт НИЖЕ заголовка: в окне вокруг заголовка его нет.
    final window = src.substring(
      (title - 700).clamp(0, src.length),
      (title + 200).clamp(0, src.length),
    );
    expect(
      window.contains('_DayBadge('),
      isFalse,
      reason: 'бейдж рядом с заголовком заставлял текст ужиматься',
    );
  });

  test('ивент: кнопка «Забрать» — брендовый алый, зажатие монотонное', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(
      src.contains('Color.lerp(BrandColors.red, cs.primary, 0.18)!'),
      isTrue,
      reason: 'сиреневый primary читался синей «заглушкой»',
    );
    expect(
      src.contains('scale: _pressed ? 0.955 : 1.0'),
      isTrue,
      reason: 'зажатие стало мягче',
    );
    expect(
      src.contains('curve: Curves.easeInOut,'),
      isTrue,
      reason: 'одна кривая на входе и отпускании — без «щелчка»',
    );
  });

  test('окно «Сбросить ивент» — своя карточка с мягкой отдачей', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(src.contains('class _ResetEventDialog'), isTrue);
    expect(
      src.contains('_ResetEventDialog('),
      isTrue,
      reason: 'сброс открывает свою карточку, а не системный AlertDialog',
    );
    final start = src.indexOf('class _ResetEventDialog');
    final body = src.substring(start);
    expect(
      body.contains('PressScale('),
      isTrue,
      reason: 'кнопки окна обязаны отдавать под пальцем',
    );
    expect(
      body.contains('pressedScale: 0.97'),
      isTrue,
      reason: 'отдача нарочно слабая — окно не «прыгает»',
    );
    // В самом баннере системного AlertDialog больше нет.
    final banner = src.substring(0, start);
    expect(
      banner.contains('AlertDialog('),
      isFalse,
      reason: 'системное окно выбивалось из «кровавой» семьи',
    );
  });

  test('профиль: у «добавить друга» НЕТ цветной оправы', () {
    final src = read('lib/screens/profile_screen.dart');
    final start = src.indexOf('profileLeaderboard');
    expect(start, greaterThan(0));
    final body = src.substring(start, (start + 1800).clamp(0, src.length));
    expect(
      body.contains('BrandColors.red'),
      isFalse,
      reason: 'красный кант вокруг иконки убран по просьбе владельца',
    );
    expect(
      body.contains('PressScale('),
      isTrue,
      reason: 'отдача под пальцем остаётся',
    );
  });

  test('статистика: график не пересчитывается и не перерисовывается зря', () {
    final src = code('lib/screens/stats_screen.dart');
    expect(
      src.contains('_recomputeMonth()'),
      isTrue,
      reason: '30 дней считаются только при смене данных',
    );
    expect(
      src.contains('!listEquals(old.days, days)'),
      isTrue,
      reason: 'сравнение по содержимому, а не по ссылке на список',
    );
    expect(
      src.contains('old.days != days'),
      isFalse,
      reason: 'сравнение по ссылке тянуло перерисовку каждый кадр',
    );
    final log = code('lib/services/completion_log_service.dart');
    expect(
      log.contains('int get hashCode => Object.hash(date, habits, tasks);'),
      isTrue,
      reason: 'без равенства DayCompletion listEquals не работал бы',
    );
  });

  test('питание: переход «пусто ↔ история» реально перелистывается', () {
    final src = read('lib/screens/nutrition_screen.dart');
    expect(
      src.contains("ValueKey('meals_empty')"),
      isTrue,
      reason: 'у пустого состояния свой ключ — иначе свитчер не срабатывал',
    );
    expect(
      src.contains("ValueKey('meals_history')"),
      isTrue,
      reason: 'у истории свой ключ',
    );
    expect(
      src.contains('_grownFromEmptyId'),
      isTrue,
      reason: 'первую запись не растим из нуля — иначе блок «проседает»',
    );
  });
}
