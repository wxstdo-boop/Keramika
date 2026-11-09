import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/swipe_to_delete.dart';

/// Свайп-удаление: карточка едет 1:1 за пальцем, красная плашка ПРОЯВЛЯЕТСЯ
/// по ходу жеста, а возврат идёт мягко (без мгновенного щелчка).
void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    ValueChanged<DismissDirection>? onDismissed,
    ConfirmDismissCallback? confirmDismiss,
  }) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                child: SwipeToDelete(
                  dismissKey: const ValueKey('d'),
                  onDismissed: onDismissed,
                  confirmDismiss: confirmDismiss,
                  child: const Card(
                    child: SizedBox(
                      height: 80,
                      child: Center(child: Text('card')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double dx(WidgetTester tester, Offset start) =>
      (tester.getTopLeft(find.text('card')) - start).dx;

  /// Альфа красной плашки (первый цвет градиента) — по ней видно, насколько
  /// плашка проявилась.
  double redAlpha(WidgetTester tester) {
    final container = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(SwipeToDelete),
        matching: find.byType(Container),
      ),
    );
    for (final c in container) {
      final d = c.decoration;
      if (d is BoxDecoration && d.gradient is LinearGradient) {
        return (d.gradient! as LinearGradient).colors.first.a;
      }
    }
    return -1;
  }

  testWidgets('карточка идёт 1:1 за пальцем (без лага)', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    var raw = 60.0;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-8, 0));
      raw += 8;
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (-raw - dx(tester, start)).abs(),
      lessThan(2.0),
      reason: 'карточка едет ровно за пальцем',
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('красная плашка появляется постепенно по ходу жеста', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(redAlpha(tester), lessThan(0.01), reason: 'в покое плашки нет');

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    // До 20 % пути плашки ещё не видно (порог осознанного жеста).
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(redAlpha(tester), lessThan(0.01), reason: 'ранний сдвиг плашку не жжёт');

    // Дальше красный наливается, и к полному свайпу он плотнее.
    await gesture.moveBy(const Offset(-120, 0));
    await tester.pump();
    final early = redAlpha(tester);

    await gesture.moveBy(const Offset(-140, 0));
    await tester.pump();
    final later = redAlpha(tester);

    expect(early, greaterThan(0.01), reason: 'плашка уже проявилась');
    expect(
      later,
      greaterThan(early),
      reason: 'чем дальше свайп, тем плотнее красный',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('сильный свайп удаляет карточку', (tester) async {
    var dismissed = false;
    await pumpCard(
      tester,
      onDismissed: (_) => dismissed = true,
      confirmDismiss: (_) async => true,
    );
    await tester.fling(find.text('card'), const Offset(-320, 0), 1500);
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('возврат домой плавный, без мгновенного щелчка', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();

    final samples = <double>[];
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(dx(tester, start));
    }
    var maxStep = 0.0;
    for (var i = 1; i < samples.length; i++) {
      final step = samples[i] - samples[i - 1];
      if (step > maxStep) maxStep = step;
    }
    expect(
      maxStep,
      lessThan(0.05 * 400),
      reason: 'возврат не прыгает кадром',
    );
    // Мягкий возврат: путь не пройден за считанные кадры.
    final firstAt = samples.indexWhere((v) => v.abs() < 1.0);
    expect(
      firstAt,
      greaterThan(5),
      reason: 'возврат занимает заметное время, а не один кадр',
    );
  });
}
