import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/section_pill.dart';

/// Таблетку разделов можно не только тапнуть, но и «протянуть» пальцем —
/// как приоритет в задаче. Камень едет за пальцем, а отпускание доводит его
/// до ближайшего раздела.
void main() {
  setUp(() {
    sectionCurrentIndex.value = 0;
    sectionRailPage.value = 0;
    sectionDragPage.value = null;
  });

  Future<void> pumpPill(WidgetTester tester) async {
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
  }

  testWidgets('тяга влево уводит камень на следующий раздел', (tester) async {
    await pumpPill(tester);
    final count = sectionLabels(tester.element(find.byType(SectionPill))).length;
    expect(count, greaterThan(1), reason: 'нужно хотя бы два раздела');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();

    // Шаг одного раздела — внутренняя ширина капсулы, делённая на число
    // разделов. К первому сдвигу добавляем touch slop: распознаватель
    // «съедает» его до того, как отдаст жест тяге.
    final slot = (304 - 8) / count;
    await gesture.moveBy(Offset(-(slot * 0.8 + 24), 0));
    await tester.pump();

    expect(
      sectionDragPage.value,
      isNotNull,
      reason: 'пока палец на таблетке, камень ведёт рука',
    );
    expect(sectionDragPage.value, greaterThan(0.3));

    await gesture.moveBy(Offset(-slot * 0.4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(sectionDragPage.value, isNull, reason: 'палец отпущен — ведёт пружина');
    expect(sectionCurrentIndex.value, 1, reason: 'ближайший раздел — следующий');
  });

  testWidgets('тяга вправо за левый край не уводит в минус', (tester) async {
    await pumpPill(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();

    expect(sectionDragPage.value, 0.0, reason: 'левый край — первый раздел');

    await gesture.up();
    await tester.pump();
    expect(sectionCurrentIndex.value, 0);
  });

  testWidgets('обычный тап по разделу не считается тягой', (tester) async {
    await pumpPill(tester);

    await tester.tap(find.byType(SectionPill), warnIfMissed: false);
    await tester.pump();

    expect(sectionDragPage.value, isNull);
    expect(sectionCurrentIndex.value, isNot(0));
  });
}
