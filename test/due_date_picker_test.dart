import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/widgets/due_date_picker.dart';

/// Диалог выбора даты не должен менять высоту при смене месяца: раньше
/// число недель менялось (5↔6) и диалог «скукоживался»/раздувался скачком —
/// экран дёргался.
void main() {
  testWidgets('высота диалога не меняется при перелистывании месяца', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      ),
    );

    // Открываем пикер на феврале 2026 (28 дней — ровно 5 недель).
    final future = showDueDatePicker(ctx, DateTime(2026, 2, 10));
    await tester.pumpAndSettle();
    final h1 = tester.getSize(find.byType(Dialog)).height;

    // Листаем вперёд на месяц с 6 неделями (март 2026).
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    final h2 = tester.getSize(find.byType(Dialog)).height;

    expect(
      h2,
      closeTo(h1, 0.5),
      reason: 'высота календаря фиксирована — диалог не должен дёргаться',
    );

    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();
    await future;
  });
}
