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

    // Ключ списка теперь зависит от содержимого (чтобы AnimatedSwitcher
    // кросс-фейдил обновление), поэтому проверяем по типу, а не по фикс. ключу.
    expect(find.byType(ListView), findsWidgets);
    expect(find.text('1.6.72'), findsOneWidget);
    expect(find.text('1.6.71'), findsOneWidget);
    expect(find.byType(Card), findsWidgets);
    // Кнопки «Повторить» больше нет: обновление — свайпом (RefreshIndicator),
    // чтобы офлайн-экран не выглядел «сломанным» с лишней кнопкой.
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    // Плашка списка изменений: заголовок — сразу «Как развивается
    // приложение», ниже мелким текстом план; «Список изменений» убран.
    expect(
      find.textContaining('Как развивается приложение'),
      findsOneWidget,
    );
    expect(find.textContaining('Мелкие доработки'), findsOneWidget);
    expect(find.textContaining('PR в 2027'), findsOneWidget);
    // Пункты списка помечены разными значками, а не одинаковыми галочками.
    expect(find.byIcon(Icons.ac_unit_rounded), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChangelogScreen: подчёркивание под свежей версией', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ChangelogScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    // Самая свежая версия — первая в списке, и именно у неё есть полоса
    // подчёркивания (в остальных карточках версия — обычный Text).
    final latest = find.text('1.6.72');
    expect(latest, findsOneWidget);
    expect(
      find.ancestor(
        of: latest,
        matching: find.byType(Stack),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });
}
