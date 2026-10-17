import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/widgets/smooth_typing.dart';

/// Суммарная «чернота» картинки. Буква появляется из полной прозрачности —
/// значит на старте анимации чернил почти нет, к концу их максимум.
Future<double> _ink(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  var sum = 0.0;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    for (var i = 0; i < bytes.length; i += 4) {
      // «Чернила» поверх белого: прозрачные пиксели не считаем вовсе.
      sum += (255 - bytes[i]) * bytes[i + 3] / 255;
    }
    image.dispose();
  });
  return sum;
}

Widget _host(TextEditingController controller, {bool enabled = true}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: RepaintBoundary(
          key: const ValueKey('shot'),
          child: SizedBox(
            width: 300,
            child: SmoothTyping(
              controller: controller,
              color: Colors.black,
              enabled: enabled,
              builder: (style) => TextField(
                controller: controller,
                style: style,
                maxLines: null,
                decoration: const InputDecoration(border: InputBorder.none),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Прямоугольник, который реально занят «чернилами».
Future<Rect?> _bounds(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('shot')),
  );
  Rect? result;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data!.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    var minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (bytes[(y * w + x) * 4 + 3] > 8) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX >= 0) {
      result = Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        maxX + 1.0,
        maxY + 1.0,
      );
    }
    image.dispose();
  });
  return result;
}

void main() {
  testWidgets('поле получает прозрачный текст, а буквы рисует наш слой', (
    tester,
  ) async {
    final controller = TextEditingController();
    TextStyle? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothTyping(
            controller: controller,
            builder: (style) {
              received = style;
              return const SizedBox(width: 10, height: 10);
            },
          ),
        ),
      ),
    );
    expect(received, isNotNull);
    expect(received!.color!.a, 0.0, reason: 'настоящее поле должно быть невидимым');
  });

  testWidgets('буквы проявляются постепенно, а не вспыхивают', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(controller));
    expect(await _ink(tester), 0.0, reason: 'пустое поле — нечего рисовать');

    controller.text = 'MMMM';
    await tester.pump();
    final birth = await _ink(tester);

    await tester.pump(const Duration(milliseconds: 40));
    final mid = await _ink(tester);

    await tester.pump(const Duration(milliseconds: 400));
    final done = await _ink(tester);

    expect(birth, lessThan(mid), reason: 'в момент рождения буква ещё почти прозрачна');
    expect(mid, lessThan(done), reason: 'в середине анимации буква ещё не добрала плотность');
    expect(done, greaterThan(0), reason: 'к концу буквы полностью видны');
  });

  testWidgets('буква гаснет при стирании, а не исчезает рывком', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_host(controller));

    controller.text = 'MMMM';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final full = await _ink(tester);
    expect(full, greaterThan(0));

    controller.text = 'MMM';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final fading = await _ink(tester);

    await tester.pump(const Duration(milliseconds: 400));
    final gone = await _ink(tester);

    expect(fading, greaterThan(gone), reason: 'удалённая буква ещё догорает');
    expect(fading, lessThan(full), reason: 'и уже не такая плотная, как была');
  });

  testWidgets('наш слой рисует буквы ровно там же, где поле', (tester) async {
    // Нативный рендер (эффект выключен — поле рисует текст само).
    final nativeCtrl = TextEditingController(text: 'Wg');
    await tester.pumpWidget(_host(nativeCtrl, enabled: false));
    await tester.pump();
    final native = await _bounds(tester);

    // Наш слой (эффект включён).
    final smoothCtrl = TextEditingController();
    await tester.pumpWidget(_host(smoothCtrl));
    smoothCtrl.text = 'Wg';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final overlay = await _bounds(tester);

    expect(native, isNotNull, reason: 'нативное поле должно было что-то нарисовать');
    expect(overlay, isNotNull, reason: 'наш слой должен был что-то нарисовать');
    expect(overlay!.left, closeTo(native!.left, 1.0));
    expect(overlay.top, closeTo(native.top, 1.0));
    expect(overlay.right, closeTo(native.right, 1.0));
    expect(overlay.bottom, closeTo(native.bottom, 1.0));
  });

  testWidgets('длинная строка в узком поле: слой едет вместе с прокруткой', (
    tester,
  ) async {
    Future<Rect?> shot(bool enabled) async {
      final c = TextEditingController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: const ValueKey('shot'),
                child: SizedBox(
                  width: 60,
                  child: SmoothTyping(
                    controller: c,
                    enabled: enabled,
                    color: Colors.black,
                    builder: (style) => TextField(
                      controller: c,
                      style: style,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        isDense: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      tester.testTextInput.enterText('MMMMMMMMMM');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return _bounds(tester);
    }

    final native = await shot(false);
    final overlay = await shot(true);

    expect(native, isNotNull);
    expect(overlay, isNotNull);
    expect(overlay!.left, closeTo(native!.left, 1.5));
    expect(overlay.top, closeTo(native.top, 1.5));
    expect(overlay.right, closeTo(native.right, 1.5));
    expect(overlay.bottom, closeTo(native.bottom, 1.5));
  });

  testWidgets('обёртка не сжимает поле: ширина как у родителя', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: SmoothTyping(
                controller: controller,
                builder: (style) => TextField(
                  controller: controller,
                  style: style,
                  decoration: const InputDecoration(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(TextField)).width, 200);
  });

  testWidgets('поле в Row/Expanded заполняет свою долю', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              const SizedBox(width: 40),
              Expanded(
                child: SmoothTyping(
                  controller: controller,
                  builder: (style) => TextField(
                    controller: controller,
                    style: style,
                    decoration: const InputDecoration(),
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),
      ),
    );
    final expanded = tester.getSize(find.byType(Expanded)).width;
    expect(tester.getSize(find.byType(TextField)).width, expanded);
  });

  testWidgets('слой не перехватывает тап: поле получает фокус', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: SmoothTyping(
                controller: controller,
                builder: (style) => TextField(
                  controller: controller,
                  focusNode: focus,
                  style: style,
                  decoration: const InputDecoration(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('поле без эффекта рисует текст обычным цветом', (tester) async {
    final controller = TextEditingController();
    TextStyle? received;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothTyping(
            controller: controller,
            enabled: false,
            builder: (style) {
              received = style;
              return const SizedBox(width: 10, height: 10);
            },
          ),
        ),
      ),
    );
    expect(received!.color!.a, greaterThan(0.0));
  });
}
