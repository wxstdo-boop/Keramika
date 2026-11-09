import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/swipe_to_delete.dart';

/// Свайп-удаление должно быть ОТЗЫВЧИВЫМ: карточка едет 1:1 за пальцем, без
/// кастомного слоя сглаживания с кадровым тикером (он давал лаг, тормозил
/// скролл и «удар» на возврате). Красная плашка проявляется по ходу жеста.
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

  testWidgets('карточка идёт 1:1 за пальцем (без лага)', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();
    // Ещё несколько сдвигов: карточка обязана повторять палец без отставания
    // (прежний сглаживающий слой «придерживал» её на десятки пикселей).
    var raw = 60.0;
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-8, 0));
      raw += 8;
      await tester.pump(const Duration(milliseconds: 16));
    }
    final moved = dx(tester, start);
    expect(
      (-raw - moved).abs(),
      lessThan(2.0),
      reason: 'без сглаживания карточка едет ровно за пальцем',
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
    expect(dismissed, isTrue, reason: 'осознанный свайп удаляет карточку');
  });

  testWidgets('возврат домой плавный и без скачка на финише', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('card')),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();

    final samples = <double>[];
    for (var i = 0; i < 40; i++) {
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
      reason: 'возврат не должен прыгать кадром',
    );
    expect(samples.last.abs(), lessThan(1.0));
  });
}
