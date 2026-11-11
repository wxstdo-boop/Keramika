import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/widgets/section_pill.dart';

/// Таблетку разделов можно не только тапнуть, но и «протянуть» пальцем —
/// как выбор приоритета.
///
/// Жест — ПОЗИЦИОННЫЙ скраббер: доля прохода пальца по капсуле сразу
/// становится позицией камня, поэтому камень едет ровно под пальцем, и
/// палец вправо ведёт к ПОСЛЕДНЕМУ разделу (позиция = выбор, как в
/// приоритете). На отпускании выбирается ближайший раздел.
///
/// Жест использует `DragStartBehavior.start`: точка старта берётся в момент
/// РАСПОЗНАВАНИЯ жеста (после touch-slop), а не в момент касания. Иначе
/// первый же update приносил позицию «касание + slop», и камень прыгал на
/// ~18 px в первом кадре — тот самый скачок при лёгкой тяге.
///
/// Проверяем ИНВАРИАНТЫ, а не абсолютную геометрию: точный размер дорожки
/// в тестовом дереве отличается от боевого, а вот направление, монотонность,
/// мгновенный старт, зажим краёв и доводка от размера не зависят.
void main() {
  setUp(() {
    sectionCurrentIndex.value = 0;
    sectionRailPage.value = 0;
    sectionDragPage.value = null;
  });

  Future<int> pumpPill(WidgetTester tester) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 304, height: 54, child: SectionPill()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return sectionLabels(tester.element(find.byType(SectionPill))).length;
  }

  testWidgets('жест стартует сразу и палец вправо ведёт к последнему разделу', (
    tester,
  ) async {
    final count = await pumpPill(tester);
    expect(count, greaterThan(1));

    final center = tester.getCenter(find.byType(SectionPill));
    final gesture = await tester.startGesture(center);
    await tester.pump();

    // Первый сдвиг за порог распознавания (touch-slop) камень НЕ двигает и
    // НЕ прыгает: точка старта берётся здесь же, а не в точке касания.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    final atSlop = sectionDragPage.value;
    expect(
      atSlop ?? 0.0,
      lessThan(0.05),
      reason: 'на пороге распознавания камень ещё стоит — без скачка',
    );

    // Осознанный сдвиг дальше ведёт камень к последующим разделам.
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final first = sectionDragPage.value;
    expect(first, isNotNull, reason: 'после порога жест ведёт камень');
    expect(
      first!,
      greaterThan(0),
      reason: 'вправо сдвигает камень к последующим разделам',
    );

    await gesture.up();
    await tester.pump();
    expect(sectionDragPage.value, isNull);
  });

  testWidgets('движение монотонно: вправо — больше, влево — меньше', (
    tester,
  ) async {
    final count = await pumpPill(tester);
    expect(count, greaterThan(1));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();

    // Камень ведётся напрямую за пальцем (без догоняющего тикера), поэтому
    // монотонность проверяем сразу после каждого шага.
    // Первый сдвиг лишь распознаёт жест (порог slop) — камень ещё стоит.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    var prev = sectionDragPage.value ?? sectionRailPage.value;
    for (var i = 0; i < 3; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      final now = sectionDragPage.value!;
      expect(now, greaterThan(prev));
      prev = now;
    }

    // А теперь шагами влево — только падает, и не уходит ниже нуля.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(-30, 0));
      for (var f = 0; f < 60; f++) {
        await tester.pump();
      }
      final now = sectionDragPage.value!;
      expect(now, lessThanOrEqualTo(prev));
      expect(now, greaterThanOrEqualTo(0));
      prev = now;
    }
    expect(
      prev,
      closeTo(0.0, 0.01),
      reason: 'левый край дорожки — первый раздел',
    );

    await gesture.up();
    await tester.pump();
    expect(sectionCurrentIndex.value, 0);
  });

  testWidgets('зажим правого края уводит на последний раздел', (tester) async {
    final count = await pumpPill(tester);
    expect(count, greaterThan(1));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    // Первый сдвиг распознаёт жест, затем большой ход до правого края.
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    expect(
      sectionDragPage.value,
      closeTo((count - 1).toDouble(), 0.01),
      reason: 'зажим правого края = последняя страница (после сходимости)',
    );

    await gesture.up();
    await tester.pump();
    expect(
      sectionCurrentIndex.value,
      count - 1,
      reason: 'на отпускании выбирается ближайший раздел',
    );
  });

  testWidgets('обычный тап по разделу не считается тягой', (tester) async {
    await pumpPill(tester);

    await tester.tap(find.byType(SectionPill), warnIfMissed: false);
    await tester.pump();

    expect(sectionDragPage.value, isNull);
    expect(sectionCurrentIndex.value, isNot(0));
  });
}
