import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/swipe_to_delete.dart';

/// Свайп-удаление должно ехать ПЛАВНО, а не «дико дёргаться» от дрожания
/// пальца. Палец задаёт цель, карточка догоняет её логарифмически, поэтому
/// мелкое разнонаправленное дрожание гасится, а осознанный свайп проходит
/// почти без задержки.
///
/// Проверяем инварианты, а не абсолютные пиксели: размах дрожания заметно
/// меньше амплитуды самого дрожания, карточка всё же уезжает за пальцем и
/// догоняет его, когда палец останавливается.
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

  testWidgets('дрожание пальца гасится, а не идёт 1:1', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    // Пройти порог арбитра жестов и дать Dismissible победить.
    await gesture.moveBy(const Offset(-60, 0));
    await tester.pump();

    // Палец дрожит ±6 px вокруг точки удержания.
    final samples = <double>[];
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(Offset(i.isEven ? -6 : 6, 0));
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(dx(tester, start));
    }
    // AC-размах по установившимся кадрам: сколько карточка «болтается».
    final tail = samples.sublist(samples.length - 6);
    final swing = tail.reduce((a, b) => a > b ? a : b) -
        tail.reduce((a, b) => a < b ? a : b);
    expect(
      swing,
      lessThan(6.0),
      reason: 'без сглаживания размах был бы равен амплитуде дрожания (6 px)',
    );

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('осознанный свайп уезжает и догоняет палец', (tester) async {
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    var raw = 40.0;
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-6, 0));
      raw += 6;
      await tester.pump(const Duration(milliseconds: 16));
    }
    final moved = dx(tester, start);
    expect(moved, lessThan(-40), reason: 'карточка реально уезжает влево');
    // Отставание от пальца на осознанном свайпе невелико.
    expect(
      (-raw - moved).abs(),
      lessThan(0.25 * raw),
      reason: 'карточка идёт за пальцем почти без задержки',
    );

    // Палец остановился — карточка догоняет его.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      (dx(tester, start) - moved).abs(),
      greaterThan(0),
      reason: 'после остановки пальца карточка подтягивается к нему',
    );
    expect((dx(tester, start) - (-raw)).abs(), lessThan(1.0));

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

  testWidgets('возврат домой идёт без удара на финише', (tester) async {
    // Слабое потягивание (не дотянули до порога) — карточка обязана вернуться
    // плавно и остановиться БЕЗ скачка. Прежний экспоненциальный фильтр копил
    // «хвост» и в конце приклеивал карточку скачком — это читалось как удар.
    await pumpCard(tester);
    final start = tester.getTopLeft(find.text('card'));
    final gesture = await tester.startGesture(tester.getCenter(find.text('card')));
    await tester.pump();
    await gesture.moveBy(const Offset(-90, 0));
    await tester.pump();
    // Пауза без движения перед отпусканием: скорость пальца к моменту `up`
    // падает до нуля, поэтому Dismissible не флингнет, а именно ПОВЕРНЁТ
    // карточку назад — ровно тот сценарий, где раньше бил «удар».
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();

    final samples = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(dx(tester, start));
    }

    // Ход возврата обязан быть МОНОТОННЫМ (без «кивка» наружу) и без скачков:
    // раньше остаток «приклеивался» одним прыжком — это и читалось как удар.
    var maxStep = 0.0;
    for (var i = 1; i < samples.length; i++) {
      final step = samples[i] - samples[i - 1];
      if (step > maxStep) maxStep = step;
      expect(
        step,
        greaterThanOrEqualTo(-0.01),
        reason: 'на возврате карточка не должна отскакивать назад (кивок)',
      );
    }
    // Пружина в разгоне проходит ~2 % ширины за кадр — это плавно. «Удар» же
    // был бы скачком в разы больше, поэтому 3 % ширины надёжно ловят регресс.
    expect(
      maxStep,
      lessThan(0.03 * 400),
      reason: 'возврат не должен прыгать кадром — это и есть «удар» на финише',
    );
    // И карточка реально вернулась домой.
    expect(samples.last.abs(), lessThan(1.0));
  });
}
