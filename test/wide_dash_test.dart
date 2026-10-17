import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/utils/wide_dash_controller.dart';

/// Тире должно быть ШИРОКИМ, а не просто «подменённым».
///
/// История бага: форматер в `inputFormatters` честно менял «-» на «—», и в
/// тексте действительно лежал U+2014. Но в рукописном шрифте Caveat этот
/// символ нарисован узко (566/1000 кегля против 326 у дефиса), поэтому
/// выглядел как дефис. Плюс сама подмена шла мимо форматера при вставке из
/// меню. Тесты ниже держат оба исправления.
void main() {
  /// Все «узкие» знаки, которые клавиатура может подставить вместо тире.
  const narrow = <String>[
    '-',
    '\u2010',
    '\u2011',
    '\u2012',
    '\u2013',
    '\u2212',
    '\uFE58',
    '\uFE63',
    '\uFF0D',
  ];

  group('нормализация', () {
    test('любой узкий знак становится широким тире', () {
      for (final ch in narrow) {
        final c = WideDashController();
        c.text = 'тест$chтест';
        expect(
          c.text,
          'тест\u2014тест',
          reason: 'знак U+${ch.runes.first.toRadixString(16)} не заменён',
        );
      }
    });

    test('вставка через value тоже нормализуется (мимо форматера)', () {
      final c = WideDashController();
      // Именно так работает «Вставить» из контекстного меню: форматеры
      // контроллера не участвуют вовсе.
      c.value = const TextEditingValue(
        text: 'a-b',
        selection: TextSelection.collapsed(offset: 3),
      );
      expect(c.text, 'a\u2014b');
      expect(
        c.selection.baseOffset,
        3,
        reason: 'каретка должна остаться на месте',
      );
    });

    test('начальный текст нормализуется в конструкторе', () {
      expect(WideDashController(text: 'x-y').text, 'x\u2014y');
    });

    test('обычный текст не трогается', () {
      final c = WideDashController();
      c.text = 'борщ и котлета';
      expect(c.text, 'борщ и котлета');
    });
  });

  group('широкий шрифт у тире', () {
    /// Собирает текст из спанов, чтобы проверить, что ничего не потерялось.
    String textOf(InlineSpan span) {
      final buffer = StringBuffer();
      span.visitChildren((s) {
        if (s is TextSpan && s.text != null) buffer.write(s.text);
        return true;
      });
      return buffer.toString();
    }

    testWidgets('тире рисуется шрифтом с настоящим широким тире', (
      tester,
    ) async {
      final c = WideDashController(text: 'a\u2014b');
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = c.buildTextSpan(
                context: context,
                style: const TextStyle(fontFamily: 'Caveat', fontSize: 16),
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );

      // Текст не пострадал при разбиении на куски.
      expect(textOf(span), 'a\u2014b');

      // Куски: «a», «—», «b». У куска с тире шрифт заменён на широкий,
      // у соседних — остался исходный.
      final runs = <TextSpan>[];
      span.visitChildren((s) {
        if (s is TextSpan && s.text != null) runs.add(s);
        return true;
      });
      final dashRun = runs.firstWhere((r) => r.text == '\u2014');
      final letterRun = runs.firstWhere((r) => r.text == 'a');
      expect(dashRun.style?.fontFamily, WideDashController.dashFontFamily);
      expect(letterRun.style?.fontFamily, 'Caveat');
      // Запасной шрифт очищен, иначе система снова возьмёт Caveat.
      expect(dashRun.style?.fontFamilyFallback, isEmpty);
    });

    testWidgets('без тире span собирает сам контроллер (быстрый путь)', (
      tester,
    ) async {
      final c = WideDashController(text: 'просто текст');
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = c.buildTextSpan(
                context: context,
                style: const TextStyle(fontFamily: 'Caveat'),
                withComposing: false,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(textOf(span), 'просто текст');
      expect(span.style?.fontFamily, 'Caveat');
    });

    testWidgets('подчёркивание зоны составления сохраняется', (tester) async {
      final c = WideDashController();
      c.value = const TextEditingValue(
        text: 'ab\u2014cd',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 2),
      );
      late TextSpan span;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              span = c.buildTextSpan(
                context: context,
                style: const TextStyle(),
                withComposing: true,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      expect(textOf(span), 'ab\u2014cd');
      final underlined = <String>[];
      span.visitChildren((s) {
        if (s is TextSpan &&
            s.text != null &&
            s.style?.decoration == TextDecoration.underline) {
          underlined.add(s.text!);
        }
        return true;
      });
      expect(
        underlined.join(),
        'ab',
        reason: 'подчёркнут должен быть только composing',
      );
    });
  });
}
