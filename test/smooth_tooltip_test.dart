import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/widgets/smooth_tooltip.dart';

Future<void> _showTooltip(
  WidgetTester tester,
  String message, {
  bool preferredAbove = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SmoothTooltip(
            message: message,
            preferredAbove: preferredAbove,
            waitDuration: Duration.zero,
            child: const Text('anchor'),
          ),
        ),
      ),
    ),
  );
  final center = tester.getCenter(find.text('anchor'));
  final gesture = await tester.startGesture(center);
  await tester.pump(const Duration(milliseconds: 60));
  await gesture.up();
  // Доводим появление пузыря до конца: первый тик тикера только привязывает
  // часы, поэтому кадр «устанавливающий» + кадр анимации.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Внутренний Padding пузыря (тот, что вокруг текста).
Finder _bubblePaddingFinder(String message) => find
    .descendant(
      of: find.byType(Overlay),
      matching: find.ancestor(
        of: find.text(message),
        matching: find.byType(Padding),
      ),
    )
    .last;

Padding _bubblePadding(WidgetTester tester, String message) =>
    tester.widget<Padding>(_bubblePaddingFinder(message));

/// Проверка реальной геометрии, а не только свойств виджета: текст стоит
/// по центру ТЕЛА пузыря, а хвостик (6 px) лежит снаружи тела — со своей
/// стороны. Иначе подпись «съезжает» к краю.
void _expectBodyCentered(
  WidgetTester tester,
  String message, {
  required bool tailAbove,
}) {
  const tail = 6.0; // _kArrowH
  final textRect = tester.getRect(find.text(message));
  final box = tester.getRect(_bubblePaddingFinder(message));
  final body = tailAbove
      ? Rect.fromLTWH(box.left, box.top + tail, box.width, box.height - tail)
      : Rect.fromLTWH(box.left, box.top, box.width, box.height - tail);
  expect(textRect.center.dy, moreOrLessEquals(body.center.dy, epsilon: 1.0));
}

RenderParagraph _paragraph(WidgetTester tester, String message) {
  final paragraphs = tester.renderObjectList<RenderParagraph>(
    find.text(message, findRichText: true),
  );
  return paragraphs.last;
}

/// Пузырь тултипа — FadeTransition вокруг его текста; по нему видно, что
/// исчезание именно плавное, а не мгновенный Remove.
FadeTransition _bubble(WidgetTester tester, String message) {
  return tester.widget<FadeTransition>(
    find.descendant(
      of: find.byType(Overlay),
      matching: find.ancestor(
        of: find.text(message),
        matching: find.byType(FadeTransition),
      ),
    ),
  );
}

void main() {
  testWidgets('текст тултипа не наследует fallback-стиль оверлея', (
    tester,
  ) async {
    const message = 'Проверка реальности';
    await _showTooltip(tester, message);

    final p = _paragraph(tester, message);
    final style = p.text.style!;
    // Жёлтое двойное подчёркивание из DefaultTextStyle.fallback должно уйти.
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.decorationColor, isNot(const Color(0xFFFFFF00)));
    // Fallback-стиль ещё и monospace: если он протёк, замер ширины шёл другим
    // шрифтом, чем отрисовка, и последняя буква срезалась.
    expect(style.fontFamily, isNot('monospace'));
    expect(style.fontSize, 12);
    // Последняя буква не срезается: текст не выходит за свои ограничения.
    expect(p.didExceedMaxLines, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('длинная подпись переносится и не переполняет пузырь', (
    tester,
  ) async {
    const message =
        'Очень длинная подсказка, которая точно не влезает в одну строку пузыря';
    await _showTooltip(tester, message);

    final p = _paragraph(tester, message);
    expect(p.didExceedMaxLines, isFalse);
    expect(p.size.width, lessThanOrEqualTo(244));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'контроль: Text без Material в оверлее получает жёлтое подчёркивание',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  Overlay.of(context).insert(
                    OverlayEntry(builder: (_) => const Text('raw overlay')),
                  );
                },
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();

      final p = _paragraph(tester, 'raw overlay');
      expect(p.text.style!.decoration, TextDecoration.underline);
      expect(p.text.style!.decorationColor, const Color(0xFFFFFF00));
    },
  );

  testWidgets('пузырь над кнопкой: текст по центру тела, хвост снизу', (
    tester,
  ) async {
    const message = 'Привычки';
    await _showTooltip(tester, message);

    // Пузырь над кнопкой → хвост смотрит ВНИЗ, значит добавочные 6 px
    // стрелки достаются НИЖНЕЙ стороне. Если перепутать стороны, текст уезжает
    // вверх/вниз («тексты в тултипах съехали»).
    expect(
      _bubblePadding(tester, message).padding,
      const EdgeInsets.fromLTRB(11, 6, 11, 12),
    );
    _expectBodyCentered(tester, message, tailAbove: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пузырь под кнопкой: хвост сверху, стороны зеркалятся', (
    tester,
  ) async {
    const message = 'Назад';
    await _showTooltip(tester, message, preferredAbove: false);

    expect(
      _bubblePadding(tester, message).padding,
      const EdgeInsets.fromLTRB(11, 12, 11, 6),
    );
    _expectBodyCentered(tester, message, tailAbove: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('уход с экрана: пузырь доигрывает плавное исчезание', (
    tester,
  ) async {
    const message = 'Проверка реальности';
    await _showTooltip(tester, message);
    expect(find.text(message), findsOneWidget);

    // «Смена экрана»: владелец-кнопка исчезает, а тултип ещё горит.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: const SizedBox.shrink())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    // Пузырь НЕ снят резко: он всё ещё в оверлее и на середине фейда.
    expect(find.text(message), findsOneWidget);
    expect(_bubble(tester, message).opacity.value, lessThan(1.0));
    expect(_bubble(tester, message).opacity.value, greaterThan(0.0));

    // После длительности фейда пузырь убирается полностью.
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(message), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'повторное нажатие: старый пузырь гаснет плавно, затем показывается заново',
    (tester) async {
      const message = 'Привычки';
      await _showTooltip(tester, message);
      final center = tester.getCenter(find.text('anchor'));

      final gesture = await tester.startGesture(center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      // Старый пузырь не «гаснет щелчком»: он всё ещё в оверлее и уже тает.
      expect(find.text(message), findsOneWidget);
      expect(_bubble(tester, message).opacity.value, lessThan(1.0));

      await gesture.up();
      // Новый показ стартует только когда старый догорел (_kFade = 420 мс).
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text(message), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_bubble(tester, message).opacity.value, 1.0);

      // Догоняем страховочные таймеры, иначе тест завершится с висящим Timer.
      await tester.pump(const Duration(seconds: 6));
      expect(tester.takeException(), isNull);
    },
  );
}
