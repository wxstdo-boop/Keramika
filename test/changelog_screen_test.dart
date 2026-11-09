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
    // Пока идёт загрузка — на месте списка скелет.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('changelog_loading')), findsOneWidget);

    // Загрузка завершается (запрос падает) — скелет сменяется списком.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('changelog_list')), findsOneWidget);
    expect(find.text('1.6.72'), findsOneWidget);
    expect(find.text('1.6.71'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    // Список не пришёл из сети — значит доступна кнопка «Повторить»,
    // иначе экран выглядел бы тупиком до перезахода.
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
