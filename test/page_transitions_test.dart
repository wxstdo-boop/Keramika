import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/utils/page_transitions.dart';

/// Блокировка и разблокировка обязаны выглядеть ОДНИМ движением.
///
/// Раньше «в блок» шёл [slideUpRoute] (экран выезжал снизу), а «из блока» —
/// [fadeRoute] с другой длительностью. Человек видел два разных жеста, и
/// разблокировка читалась рывком. Теперь обе стороны — симметричная проявка
/// [lockRoute]: время вперёд равно времени назад.
void main() {
  PageRouteBuilder<void> build() =>
      lockRoute<void>(const SizedBox.shrink()) as PageRouteBuilder<void>;

  test('lockRoute симметричен: вход и выход одной длительности', () {
    final route = build();
    expect(
      route.transitionDuration,
      route.reverseTransitionDuration,
      reason: 'разные длительности дают рывок на разблокировке',
    );
    expect(route.transitionDuration, lockRouteReverseDuration);
  });

  testWidgets('lockRoute проявляет страницу от прозрачной к плотной', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Material(child: Text('home')),
      ),
    );

    navigator.currentState!.push(lockRoute<void>(const Text('PIN')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final startOpacity = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .map((f) => f.opacity.value)
        .reduce((a, b) => a < b ? a : b);
    expect(startOpacity, lessThan(0.4), reason: 'в начале экран почти прозрачен');

    await tester.pumpAndSettle();
    final endOpacity = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .map((f) => f.opacity.value)
        .reduce((a, b) => a > b ? a : b);
    expect(endOpacity, closeTo(1, 0.01), reason: 'в конце экран плотный');
  });
}
