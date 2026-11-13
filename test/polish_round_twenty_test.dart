import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест круга 20: статистика (иероглиф + лаги), тема «Метель»,
/// карточка ивента и лаги загрузки.
///
/// Каждая проверка закрывает конкретную жалобу владельца:
///  * в статистике больше нет размытия под «лучшим днём» — `MaskFilter`
///    пересчитывался каждый кадр роста и читался мутным пятном;
///  * числа статистики — чистый текст без свечения-«двойника»;
///  * кисти графика аллоцируются ОДИН раз на кадр, а не по штуке на столбик;
///  * подписи дат отступают от края и не сливаются со столбиком;
///  * «Метель» стала фоном, а не цветной кашей: три полосы вместо шести;
///  * акцент карточки ивента — алая семья, а не `primary` (в «Метели»
///    бирюзовый);
///  * скелетон окна ивента не крутит вечный индикатор;
///  * окно сброса — одна ровная кромка вместо диагонального градиента.
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

  /// Код без строк-комментариев: проверки на подстроки не должны ловить сами
  /// пояснения, в которых эти подстроки упомянуты.
  String code(String path) => read(
    path,
  ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('статистика: ни размытия, ни «глитч»-числа, ни лишних аллокаций', () {
    final src = code('lib/screens/stats_screen.dart');
    expect(
      src.contains('MaskFilter'),
      isFalse,
      reason: 'блюр под звездой пересчитывался каждый кадр — это и был лаг',
    );
    expect(
      src.contains('_glitchPhase'),
      isFalse,
      reason: 'фаза «глитча» — мёртвый груз, вечных анимаций в стате нет',
    );
    // Число — чистый текст: никаких теней-«двойников».
    final number = src.substring(
      src.indexOf('class _StatNumber'),
      src.indexOf('class _MonthChart'),
    );
    expect(
      number.contains('shadows:'),
      isFalse,
      reason: 'тень на мелком числе читалась мутным «иероглифом»',
    );
    // Кисти — до цикла по столбикам.
    final painter = src.substring(src.indexOf('class _DaysBarPainter'));
    expect(
      painter.contains('final habitPaint = Paint()..color = habitColor;'),
      isTrue,
      reason: 'кисть на столбик каждый кадр — лишний мусор на слабом GPU',
    );
    expect(
      RegExp(r'Paint\(\)\.\.color = habitColor;').allMatches(painter).length,
      1,
      reason: 'кисть привычек обязана аллоцироваться один раз',
    );
    expect(
      painter.contains('const inset = 3.0;'),
      isTrue,
      reason: 'подпись даты не должна касаться кромки холста',
    );
  });

  test('Метель: три спокойные полосы и реже снег, а не цветная каша', () {
    final src = code('lib/widgets/metel_overlay.dart');
    // Шесть полос давали четырнадцать заливок на кадр — «много хуйни».
    // Считаем только в списке _bands: объявление конструктора _Band тоже
    // начинается с `const _Band(`.
    final bands = src.substring(
      src.indexOf('_bands = ['),
      src.indexOf('];', src.indexOf('_bands = [')),
    );
    expect(
      RegExp(r'const _Band\(').allMatches(bands).length,
      3,
      reason: 'небо — фон: одна подсветка и две ленты',
    );
    expect(
      src.contains('List.generate(22,'),
      isTrue,
      reason: 'тридцать четыре снежинки читались мусором по экрану',
    );
    expect(
      src.contains('List.generate(34,'),
      isFalse,
    );
  });

  test('ивент: акцент карточки — алая семья, а не сиреневый primary', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(
      src.contains('final accent = Color.lerp(BrandColors.red, cs.primary, 0.10)!;'),
      isTrue,
      reason: 'медальон, бейдж, полоса и подарок — одним красным родом',
    );
    final card = src.substring(
      src.indexOf('Widget _card('),
      src.indexOf('class _DayBadge'),
    );
    expect(
      card.contains('glow: cs.primary'),
      isFalse,
      reason: 'в «Метели» primary бирюзовый — внутри алой карточки чужой тон',
    );
    // Полоса прогресса без третичного тона (в «Метели» он фиолетовый).
    final progress = src.substring(
      src.indexOf('class _HatProgress'),
      src.indexOf('class _NyMarkButton'),
    );
    expect(
      progress.contains('cs.tertiary'),
      isFalse,
      reason: 'примесь третичного уводила заливку в чужой цвет',
    );
  });

  test('ивент: скелетон не крутит вечный индикатор', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final skeleton = src.substring(
      src.indexOf('Widget _skeleton('),
      src.indexOf('Widget _card('),
    );
    expect(
      skeleton.contains('CircularProgressIndicator'),
      isFalse,
      reason: 'вечный спиннер перерисовывался каждый кадр — «лаг загрузки»',
    );
    expect(
      skeleton.contains('TweenAnimationBuilder'),
      isTrue,
      reason: 'заглушка дышит разовым проходом, а не вечным циклом',
    );
  });

  test('окно сброса ивента — одна ровная кромка, без диагонального градиента', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final dialog = src.substring(src.indexOf('class _ResetEventDialog'));
    expect(
      dialog.contains('LinearGradient'),
      isFalse,
      reason: 'градиент по периметру давал разный тон на каждой стороне',
    );
    expect(
      dialog.contains('BrandColors.red.withValues(alpha: 0.34)'),
      isTrue,
      reason: 'кромка — полупрозрачно-алая, волосяная',
    );
  });

  test('«Получено» — алая кромка, а не серый outlineVariant', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    final button = src.substring(src.indexOf('class _NyMarkButton'));
    expect(
      button.contains('cs.outlineVariant.withValues(alpha: dark ? 0.5 : 0.7)'),
      isFalse,
      reason: 'серое кольцо читалось грубой молочной обводкой',
    );
    expect(
      button.contains('Color.lerp(') && button.contains('BrandColors.red'),
      isTrue,
      reason: 'кромка «Получено» — в алом роду, как у капсулы подарка',
    );
  });
}
