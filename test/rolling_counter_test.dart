import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/widgets/rolling_counter.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  Future<double> pump(WidgetTester tester, double value) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RollingCounter(value: value, style: style),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(RollingCounter)).height;
  }

  testWidgets('барабан: в окне ровно два слоя на расстоянии одной строки', (
    tester,
  ) async {
    final h = await pump(tester, 3.0);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);

    // Покой (дробная часть 0): текущая строка в окне, следующая — ровно на
    // высоту строки ниже, то есть целиком за ClipRect.
    final rest = tester.getTopLeft(find.text('3')).dy;
    expect(
      tester.getTopLeft(find.text('4')).dy - rest,
      closeTo(h, 0.5),
      reason: 'следующий слой должен стоять за нижним краем окна',
    );

    // Пол-оборота: слои расходятся симметрично, ни один не виден целиком —
    // это и есть ход барабана.
    await pump(tester, 3.5);
    final mid = tester.getTopLeft(find.text('3')).dy;
    expect(mid - rest, closeTo(-h / 2, 0.5));
    expect(tester.getTopLeft(find.text('4')).dy - rest, closeTo(h / 2, 0.5));

    // Коробка при этом не дрогает: высота всегда одна строка, иначе соседние
    // виджеты в подписи скакали бы по вертикали каждый кадр.
    expect(tester.getSize(find.byType(RollingCounter)).height, closeTo(h, 0.5));
  });

  testWidgets('барабан: на переходе через разряд ширина не дёргается', (
    tester,
  ) async {
    // 9.99 → почти «10»: табло в конце строки, и пока не доехало, показан
    // предыдущий разряд, а не пустота.
    await pump(tester, 9.99);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    await pump(tester, 10.0);
    expect(find.text('10'), findsOneWidget);
    // Следующий за ним слой тоже существует, но он за клипом: на месте он
    // не виден и высоту коробки не меняет.
    expect(find.text('11'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('10')).dy,
      closeTo(tester.getTopLeft(find.byType(RollingCounter)).dy, 0.5),
    );
  });
}
