import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/widgets/sliding_picker.dart';

class _BounceScrollBehavior extends MaterialScrollBehavior {
  const _BounceScrollBehavior();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

Future<List<String>> _run(
  WidgetTester tester,
  Future<void> Function() gesture,
) async {
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      scrollBehavior: const _BounceScrollBehavior(),
      home: Scaffold(
        body: SlidingPicker<String>(
          items: const ['', 'work', 'home'],
          selected: '',
          onChanged: (c) => calls.add(c),
          itemBuilder: (context, c, selected) => Text(c.isEmpty ? 'ALL' : c),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await gesture();
  await tester.pumpAndSettle();
  // Дебаунс 150 мс — это Timer, а не кадр: двигаем fake-время.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
  return calls;
}

void main() {
  testWidgets('drag settles on neighbor — onChanged fires once with it',
      (tester) async {
    final calls =
        await _run(tester, () => tester.drag(find.byType(PageView), const Offset(-500, 0)));
    expect(calls, ['work']);
  });

  testWidgets('fast fling through 2 pages — fires ONLY the final item',
      (tester) async {
    final calls =
        await _run(tester, () => tester.fling(find.byType(PageView), const Offset(-700, 0), 3000));
    debugPrint('FLING calls: $calls');
    expect(calls, ['home']);
  });

  testWidgets('tap the visible part of a neighbor chip — applies immediately',
      (tester) async {
    // Соседняя таблетка выступает справа от центрального слота; её центр
    // за экраном, поэтому тапаем в видимую часть слота страницы 1.
    final calls =
        await _run(tester, () => tester.tapAt(const Offset(700, 20)));
    expect(calls, ['work']);
  });
}
