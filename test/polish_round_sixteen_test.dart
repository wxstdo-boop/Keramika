import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест круга 16: жалобы на зайчика, кольцо музыки, новогоднее окно
/// и плавность питания.
///
/// Проверяем инварианты кода, каждый из которых закрывал конкретную жалобу:
///  * зайчик больше НЕ «дышит» вечно (дрожь, лишняя растеризация за кадр);
///  * кольцо музыки — один обход окружности свечения, а не «туча кругов»;
///  * окно ивента — своя полоса прогресса, бейдж дня и стаггер содержимого;
///  * после закрытия ивента фокус снимается (клавиатура не «приезжает»);
///  * числа питания меняются ПО ЦИФРАМ ([SmoothDigits]), а не барабаном;
///  * [SmoothDigits] не заводит скрытое `TextField` (иначе ломает выбор
///    настоящих полей в тестах и семантике);
///  * переход «пусто ↔ история» не выбрасывает уходящего ребёнка кадром.
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

  test('зайчик обновления появляется разово, без вечного «дыхания»', () {
    final src = read('lib/widgets/update_pill.dart');
    expect(
      src.contains('_spin.repeat()'),
      isFalse,
      reason: 'вечное «дыхание» значка убрано по жалобе на дрожь',
    );
    expect(
      RegExp(r'_enter\.forward\(\)').allMatches(src).length,
      2,
      reason: 'и таблетка, и окно входят один раз',
    );
    expect(src.contains('SquirrelWheel'), isTrue);
    expect(src.contains('AnimatedBunny'), isFalse);
  });

  test('кольцо музыки: расходящиеся волны без градиентных шейдеров', () {
    final src = read('lib/widgets/music_pulse_ring.dart');
    // Монотонный пульс: тон один, поэтому шейдеры-градиенты не нужны вовсе —
    // кадр стоит две обводки вместо прежних трёх шейдеров и трёх обходов.
    expect(
      RegExp(r'\.createShader\(').allMatches(src).length,
      0,
      reason: 'градиентных шейдеров больше нет — только ровные обводки',
    );
    expect(
      RegExp(r'canvas\.drawCircle\(').allMatches(src).length,
      2,
      reason: 'опорная кромка и волны — по одному вызову',
    );
    expect(src.contains('MaskFilter'), isFalse);
  });

  test('окно ивента: своя полоса, бейдж дня и стаггер содержимого', () {
    final src = read('lib/widgets/new_year_event_banner.dart');
    expect(src.contains('class _DayBadge'), isTrue);
    expect(
      RegExp(r'LinearProgressIndicator\(').hasMatch(src),
      isFalse,
      reason: 'штатная полоса «щёлкала» на смене значения',
    );
    expect(
      src.contains('FractionallySizedBox'),
      isTrue,
      reason: 'заливка полосы идёт дробным значением волны',
    );
    expect(
      RegExp(r'_contentIn = CurvedAnimation').hasMatch(src),
      isTrue,
      reason: 'содержимое «догоняет» появление карточки',
    );
  });

  test('после закрытия ивента фокус снимается — клавиатура не приезжает', () {
    final src = read('lib/screens/profile_screen.dart');
    final start = src.indexOf('Future<void> _openEventBanner()');
    final end = src.indexOf('Future<void> _openEvent(String url)');
    expect(start, greaterThan(0));
    final body = src.substring(start, end);
    expect(
      RegExp(r'_nameFocus\.unfocus\(\)').hasMatch(body),
      isTrue,
      reason: 'возврат роутом поднимал IME на поле имени',
    );
  });

  test('числа питания меняются посимвольно, а не барабаном', () {
    final src = read('lib/screens/nutrition_screen.dart');
    final stat = src.indexOf('Widget _statLine(');
    final macro = src.indexOf('Widget _macroBar(');
    expect(stat, greaterThan(0));
    expect(macro, greaterThan(stat));
    for (final slice in [src.substring(stat, macro), src.substring(macro)]) {
      expect(
        slice.contains('SmoothDigits('),
        isTrue,
        reason: 'значение сменяется по цифрам, как очки рейтинга',
      );
      expect(
        slice.contains('AnimatedCounter('),
        isFalse,
        reason: 'барабан читался грубой подменой',
      );
    }
  });

  test('SmoothDigits не заводит скрытое поле ввода', () {
    final src = read('lib/widgets/smooth_digits.dart');
    expect(
      src.contains('TextField('),
      isFalse,
      reason: 'скрытое поле ломало find.byType(TextField) в тестах',
    );
    expect(
      src.contains('SmoothTyping'),
      isFalse,
      reason: 'для числа достаточно поразрядной смены',
    );
  });

  test('переход «пусто ↔ история» тянется по высоте, без подмены кадром', () {
    final src = read('lib/screens/nutrition_screen.dart');
    // Пустая подсказка и история живут в ОДНОМ блоке под одним AnimatedSize:
    // подсказка сама раскрывается и схлопывается по высоте (heightFactor),
    // поэтому переход «пусто ↔ история» идёт непрерывно, а не подменой
    // состояния AnimatedSwitcher'ом (тот мигал текстом).
    final hint = src.indexOf('Widget _emptyMealsHint(');
    expect(hint, greaterThan(0));
    final body = src.substring(hint, hint + 900);
    expect(
      body.contains('heightFactor'),
      isTrue,
      reason: 'подсказка тает и схлопывается, а не пропадает кадром',
    );
    expect(
      body.contains('_mealCollapse'),
      isTrue,
      reason: 'та же длительность, что у истории и строки',
    );
    expect(
      src.contains("ValueKey('meals_empty')"),
      isTrue,
      reason: 'у подсказки свой ключ',
    );
  });
}
