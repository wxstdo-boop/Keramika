import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/widgets/music_pulse_ring.dart';

/// Регресс-тест круга 12: жалобы на плавность и на «иероглиф» в кантах.
///
/// Проверяем не поведение пикселей (в CI его не снять), а инварианты кода,
/// каждый из которых закрывал конкретную жалобу:
///  * кант карточек статистики — ОДНА линия, а не диагональный градиент
///    (градиент давал разный цвет на сторонах — «иероглиф»);
///  * окно обновления затемняет барьер маршрута, а не второй слой
///    (два затемнения складывались — окно «мигало»);
///  * прыжок зайчика без округления до целых пикселей (пять ступеней на 4 px
///    читались дёргаными);
///  * сигма блюра кольца музыки постоянна (динамическая пересобирала растр
///    каждый кадр — пульс «лагал»);
///  * строка «Очки/Удалить» лежит на своём `Material` (иначе ink-волна
///    уходила под фон листа);
///  * схлопывание и растворение строки питания идут одной длительностью и
///    кривой (разнобой давал вспышку текста при удалении).
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

  test('кант карточек статистики — ровная линия, а не градиент', () {
    final src = read('lib/screens/stats_screen.dart');
    final start = src.indexOf('Widget _ringedCard(');
    final end = src.indexOf('/// Число статистики.');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    final body = src.substring(start, end);
    expect(
      body.contains('LinearGradient'),
      isFalse,
      reason:
          'диагональный градиент по периметру читается пёстрым «иероглифом»',
    );
    expect(body.contains('Border.all('), isTrue, reason: 'кант — одна линия');
  });

  test('окно обновления затемняет барьер, а не второй слой', () {
    final src = read('lib/widgets/update_pill.dart');
    expect(
      src.contains('barrierColor: Colors.transparent'),
      isFalse,
      reason: 'прозрачный барьер + свой слой затемнения складывались в мигание',
    );
    expect(
      RegExp(r'barrierColor: Colors\.black\.withValues').hasMatch(src),
      isTrue,
    );
    // Внутри transitionBuilder не должно остаться затемняющего ColoredBox.
    expect(
      src.contains('IgnorePointer(child: ColoredBox(color: dim))'),
      isFalse,
    );
  });

  test('значок обновления появляется разово, а не «дышит» вечно', () {
    final src = read('lib/widgets/update_pill.dart');
    // Вечный цикл «дыхания» убран: он читался дрожью, а глиф в нём
    // растеризовался каждый кадр. Вход — ОДИН раз, плавно и с мягкой
    // остановкой; на «убрать анимации» он не запускается вовсе.
    expect(
      src.contains('_spin.repeat()'),
      isFalse,
      reason: 'вечного «дыхания» значка больше нет',
    );
    expect(
      RegExp(r'if \(!MotionPrefs\.shouldReduceMotion\) _enter\.forward\(\)')
          .hasMatch(src),
      isTrue,
      reason: 'вход идёт один раз и уважает «убрать анимации»',
    );
    expect(
      src.contains('.roundToDouble()'),
      isFalse,
      reason: 'округление до целых пикселей давало ступени — «дёрганье»',
    );
  });

  test('свечение кольца музыки — без блюра (квадратной кромки нет)', () {
    final src = read('lib/widgets/music_pulse_ring.dart');
    // Блюр на Impeller применяется к ПРЯМОУГОЛЬНИКУ слоя и вокруг круглой
    // обводки давал светящуюся квадратную кромку.
    expect(
      src.contains('MaskFilter'),
      isFalse,
      reason: 'блюр режется по прямоугольнику слоя — «квадратное» свечение',
    );
    // Пульс МОНОТОННЫЙ: один тон темы, никакого перелива по окружности —
    // прежний sweep-градиент читался пёстрым «мигающим» кольцом.
    expect(
      src.contains('SweepGradient'),
      isFalse,
      reason: 'перелив тона по кругу — ровно то «мигание», от которого ушли',
    );
    // Волны — расходящиеся ОБВОДКИ (stroke), без заливки: опорная кромка у
    // кнопки плюс три волны в пути.
    expect(
      RegExp(r'PaintingStyle\.stroke').allMatches(src).length,
      greaterThanOrEqualTo(2),
      reason: 'волны рисуются тонкой линией, а не залитым кругом',
    );
    expect(
      RegExp(r'canvas\.drawCircle\(').allMatches(src).length,
      2,
      reason: 'опорная кромка и волны рисуются из одного места',
    );
  });

  test('строка листа действий лежит на своём Material', () {
    final src = read('lib/screens/profile_screen.dart');
    final start = src.indexOf('Widget _actionTile(');
    final body = src.substring(start, start + 1200);
    expect(
      body.contains('Material('),
      isTrue,
      reason: 'без своего Material ink-волна уходит под фон листа',
    );
  });

  test('схлопывание и растворение строки питания идут одной кривой', () {
    final src = read('lib/screens/nutrition_screen.dart');
    expect(src.contains('static const Curve _mealCollapseCurve'), isTrue);
    // Растворение содержимого карточки приёма пищи — та же кривая, что у
    // схлопывания: ищем окно вокруг [AnimatedSwitcher] удаления строки.
    final card = src.indexOf('Widget _mealCard(');
    expect(card, greaterThan(0));
    final cardSrc = src.substring(card, (card + 16000).clamp(0, src.length));
    expect(
      cardSrc.contains('Curves.easeInOutCubic'),
      isFalse,
      reason: 'своя кривая на растворении давала вспышку текста при удалении',
    );
    expect(cardSrc.contains('curve: _mealCollapseCurve'), isTrue);
  });

  testWidgets('кольцо музыки собирается и не роняет кадр', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MusicPulseRing(
              active: true,
              child: SizedBox(width: 64, height: 64),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(CustomPaint), findsWidgets);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
