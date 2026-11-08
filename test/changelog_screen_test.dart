import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/changelog_screen.dart';

void main() {
  // В flutter_test сетевые запросы по умолчанию отдают 400, поэтому
  // fetchChangelog возвращает null и экран обязан показать встроенный
  // запасной список — он не должен оставаться пустым при отсутствии сети.
  testWidgets('ChangelogScreen показывает встроенный список без сети', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ChangelogScreen()),
      ),
    );
    // Прогресс-полоса видна, пока идёт загрузка.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Загрузка завершается (запрос падает) — рисуем запасной список.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('1.6.72'), findsOneWidget);
    expect(find.text('1.6.71'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    // Список не пришёл из сети — значит доступна кнопка «Повторить»,
    // иначе экран выглядел бы тупиком до перезахода.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
