import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/music_pulse_ring.dart';

/// Регресс-тест четырнадцатого круга (правки после 12-го):
///  * значок таблетки обновления — не зайчик, а «стрелка обновления», и он
///    «дышит» вечным циклом с плавными началом/концом;
///  * пятна на «+» — крупные и КРОВАВЫЕ (брендовый алый), как отпечаток;
///  * у кольца музыки нет размытия: оно давало квадратную светящуюся кромку;
///  * переход «действия → очки» в листе друга — плавный (slide + fade) и без
///    искусственной паузы;
///  * кнопки ПИН в настройках отдают нажатие вдавливанием;
///  * со сплэша убрано «разбитое стекло», кровавые пятна остались.
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

  test('значок обновления — «стрелка обновления», а не зайчик', () {
    final src = read('lib/widgets/update_pill.dart');
    expect(
      src.contains('Icons.system_update_rounded'),
      isTrue,
      reason: 'значок таблетки — стрелка обновления',
    );
    expect(
      src.contains('Icons.cruelty_free'),
      isFalse,
      reason: 'зайчик заменён',
    );
    expect(src.contains('class _UpdateGlyphPainter'), isTrue);
  });

  test('значок «дышит» вечным замкнутым циклом с плавными концами', () {
    final src = read('lib/widgets/update_pill.dart');
    // Косинус: значение И производная нулевые на обоих концах цикла — стык
    // без рывка. Один «вдох» за цикл, а не два.
    expect(
      RegExp(r'1 - math\.cos\(t \* 2 \* math\.pi\)').hasMatch(src),
      isTrue,
      reason: 'плавные начало и конец вечного цикла',
    );
    expect(
      src.contains('_bobScale('),
      isTrue,
      reason: 'значок мягко набухает, а не только смещается',
    );
    // Вечный цикл запускается в `initState`, а не только на время загрузки.
    expect(
      RegExp(r'initState\(\)[\s\S]{0,220}?_spin\.repeat\(\)').hasMatch(src),
      isTrue,
      reason: 'значок живёт всегда, а не лишь пока идёт проверка',
    );
    expect(
      src.contains('_spin.stop()'),
      isFalse,
      reason: 'вечный цикл не должен останавливаться по завершении тапа',
    );
  });

  test('пятна на «+» — крупные и кровавые, а не мелкие веснушки', () {
    final src = read('lib/widgets/press_splat.dart');
    expect(
      src.contains('0xFFE0192F'),
      isTrue,
      reason: 'пятна берут брендовый алый, а не тон поверхности',
    );
    expect(
      RegExp(r'const count = 7').hasMatch(src),
      isTrue,
      reason: 'пятен стало больше — отпечаток размашистее',
    );
    expect(
      RegExp(r'rr = 3\.4 \+ 1\.8').hasMatch(src),
      isTrue,
      reason: 'радиус пятна заметно крупнее прежних 1.5–2.9 px',
    );
    expect(
      RegExp(r'smeary: 0\.85').hasMatch(src),
      isTrue,
      reason: 'край рваный, как у жирного оттиска',
    );
  });

  test('у кольца музыки нет размытия — квадратной кромке взяться неоткуда', () {
    final src = read('lib/widgets/music_pulse_ring.dart');
    expect(
      src.contains('MaskFilter'),
      isFalse,
      reason: 'блюр режется по прямоугольнику слоя — «квадратное» свечение',
    );
    expect(
      RegExp(r'strokeWidth = stroke \* 3\.2').hasMatch(src),
      isTrue,
      reason: 'мягкость даёт широкая полупрозрачная обводка, а не блюр',
    );
  });

  testWidgets('кольцо музыки светится кругом, углы остаются чистыми', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: const SizedBox(
                width: 200,
                height: 200,
                child: Center(
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: MusicPulseRing(
                      active: true,
                      child: SizedBox(width: 64, height: 64),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final w = image.width;
      // «Цветность» пикселя: 0 на белом фоне, >0 на красном кольце. Так
      // отличим свет кольца от белого фона без опоры на альфу.
      int chroma(int x, int y) {
        if (x < 0 || y < 0 || x >= w || y >= image.height) return 0;
        final i = (y * w + x) * 4;
        final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
        final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
        final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
        return mx - mn;
      }

      // Углы окна — далеко от кольца: там не должно быть ни капли цвета.
      for (final c in [
        [0, 0],
        [199, 0],
        [0, 199],
        [199, 199],
      ]) {
        expect(
          chroma(c[0], c[1]),
          lessThan(10),
          reason: 'угол (${c[0]},${c[1]}) окрашен — свечение обрезано квадратом',
        );
      }
      // А по кромке кольца цвет ЕСТЬ: свечение рисуется, просто круглое.
      // Радиус кольца ≈ 30 px (окно 64, отступ на свечение), поэтому берём
      // точки ровно на окружности сверху/снизу/слева/справа от центра.
      var ringChroma = 0;
      for (final c in [
        [100, 70],
        [100, 130],
        [70, 100],
        [130, 100],
      ]) {
        ringChroma += chroma(c[0], c[1]);
      }
      expect(
        ringChroma,
        greaterThan(10),
        reason: 'кольцо должно светиться по периметру',
      );
    });
  });

  test('переход «действия → очки» — плавный и без паузы', () {
    final src = read('lib/screens/profile_screen.dart');
    expect(
      src.contains('Future<void> _pressThen('),
      isFalse,
      reason: 'искусственная пауза только добавляла лаг между пальцем и откликом',
    );
    final sheet = src.indexOf('class _FriendSheetState');
    expect(sheet, greaterThan(0));
    final body = src.substring(sheet, sheet + 1800);
    expect(
      body.contains('SlideTransition'),
      isTrue,
      reason: 'шаг всплывает на место, а не подменяется кадром',
    );
    expect(
      body.contains('Motion.emphasized'),
      isTrue,
      reason: 'кривая с нулевой скоростью на обоих концах — переход мягкий',
    );
  });

  test('кнопки ПИН в настройках отдают нажатие вдавливанием', () {
    final src = read('lib/screens/settings_screen.dart');
    final lock = src.indexOf("ValueKey('pin_lock_\$_hasPin')");
    expect(lock, greaterThan(0));
    expect(
      src.substring(lock - 400, lock).contains('PressScale'),
      isTrue,
      reason: 'кнопка «сменить/установить ПИН» должна вдавливаться',
    );
    final del = src.indexOf("ValueKey('pin_delete_btn')");
    expect(del, greaterThan(0));
    expect(
      src.substring(del - 400, del).contains('PressScale'),
      isTrue,
      reason: 'кнопка «удалить ПИН» должна вдавливаться',
    );
  });

  test('сплэш: разбитое стекло убрано, кровавые пятна остались', () {
    final src = read('lib/screens/splash_screen.dart');
    expect(
      src.contains('_ShatteredGlassPainter'),
      isFalse,
      reason: 'трещины поверх плиты читались наклейкой и «грязнили» логотип',
    );
    expect(
      src.contains('_PaintSplatPainter'),
      isTrue,
      reason: 'кровавые пятна должны остаться',
    );
  });
}
