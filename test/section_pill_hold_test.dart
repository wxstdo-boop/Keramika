import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/section_pill.dart';

/// Удержание таблетки пальцем не должно «дёргать» карусель разделов.
///
/// На дорожке таблетки камень занимает ~1/4 ширины, а на экране — целую
/// страницу, поэтому микродрожание пальца усиливается в разы и, попадая в
/// кадровый тикер, двигает сразу все keep-alive разделы. Дедзона на палец
/// глушит это дрожание, но осознанный свайп проходит.
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

  testWidgets('микродрожание пальца при удержании не двигает камень', (
    tester,
  ) async {
    await pumpPill(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final before = sectionDragPage.value;
    // Палец «стоит», но дрожит ±2 px — как живая рука.
    for (var i = 0; i < 40; i++) {
      await gesture.moveBy(Offset(i.isEven ? -2 : 2, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(sectionDragPage.value, before, reason: 'дрожание руки не двигает камень');
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('осознанный медленный свайп всё же двигает камень', (
    tester,
  ) async {
    await pumpPill(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    // Шаги по 8 px — заметно больше дедзоны, должны накапливаться.
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(8, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      sectionDragPage.value,
      isNotNull,
      reason: 'осознанный свайп не должен глушиться дедзоной',
    );
    expect(sectionDragPage.value!, greaterThan(0.5));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('отпускание растянутого камня возвращает форму плавно', (
    tester,
  ) async {
    await pumpPill(tester);
    double stoneWidth() {
      final r = tester.getRect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_GlassStone',
        ),
      );
      return r.width;
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SectionPill)),
    );
    await tester.pump();
    // Долгая тяга к правому краю — камень заметно растянут.
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(18, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    final stretched = stoneWidth();
    await gesture.up();
    // Первый кадр после отпускания: форма не должна схлопнуться скачком.
    await tester.pump(const Duration(milliseconds: 16));
    final first = stoneWidth();
    expect(
      first,
      greaterThan(stretched * 0.9),
      reason: 'растяжка не должна пропадать в первом же кадре '
          '(раньше захваченная тяга обнулялась на статусе forward)',
    );
    // И дальше ширина только уменьшается — форма «расслабляется» плавно.
    var prev = first;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 32));
      final w = stoneWidth();
      expect(w, lessThanOrEqualTo(prev + 0.01));
      prev = w;
    }
    expect(prev, lessThan(first), reason: 'форма всё же возвращается к покою');
    await tester.pumpAndSettle();
  });
}
