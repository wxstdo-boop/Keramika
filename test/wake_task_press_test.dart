import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/wake_task.dart';
import 'package:agysha/screens/wake_task_screen.dart';
import 'package:agysha/widgets/press_scale.dart';

/// Регресс: кнопки окна пробуждения должны отдавать нажатие «вдавливанием»
/// (PressScale), как остальные кнопки приложения. Раньше отдачи не было —
/// палец нажимал на кнопку, а та не двигалась ни на пиксель.
void main() {
  Widget host(Widget child) => LocaleProvider(
    locale: const Locale('ru'),
    child: MaterialApp(home: Scaffold(body: child)),
  );

  /// Масштаб по X. `getMaxScaleOnAxis()` не годится: у `Transform.scale` ось Z
  /// остаётся единичной, и максимум всегда равен 1.0.
  double scaleOf(WidgetTester tester, Finder pressScale) {
    final t = tester.widget<Transform>(
      find.descendant(of: pressScale, matching: find.byType(Transform)).first,
    );
    return t.transform.entry(0, 0);
  }

  testWidgets('кнопка «Отключить» окна пробуждения отдаёт вдавливанием', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const WakeTaskScreen(taskType: WakeUpTask.none, isTest: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final pressScale = find.ancestor(
      of: find.byType(FilledButton),
      matching: find.byType(PressScale),
    );
    expect(
      pressScale,
      findsOneWidget,
      reason: 'кнопка окна пробуждения должна быть обёрнута в PressScale',
    );

    expect(scaleOf(tester, pressScale), closeTo(1.0, 0.001));

    final gesture = await tester.startGesture(
      tester.getCenter(pressScale),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      scaleOf(tester, pressScale),
      lessThan(0.999),
      reason: 'под пальцем кнопка должна уменьшаться',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      scaleOf(tester, pressScale),
      closeTo(1.0, 0.01),
      reason: 'после отпускания кнопка возвращается в исходный размер',
    );
  });
}
