import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/key_recovery_screen.dart';
import 'package:keramika/screens/startup_recovery_screen.dart';

void main() {
  testWidgets('shows safe recovery guidance and a non-destructive diagnostic', (
    tester,
  ) async {
    const diagnostic =
        'The encryption key is missing while encrypted data exists';
    await tester.pumpWidget(
      const StartupRecoveryApp(locale: Locale('ru'), diagnostic: diagnostic),
    );

    expect(find.text('Запуск остановлен безопасно'), findsOneWidget);
    expect(
      find.textContaining('Существующие файлы не изменены.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Не очищайте данные приложения'),
      findsOneWidget,
    );

    await tester.tap(find.text('Технические сведения'));
    await tester.pumpAndSettle();
    expect(find.text(diagnostic), findsOneWidget);
  });

  testWidgets(
    'developer recovery setup reveals a 24-word phrase only on demand',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: LocaleProvider(
            locale: Locale('en'),
            child: DeveloperCornerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Encryption recovery phrase'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      await tester.tap(find.text('Create recovery phrase'));
      await tester.pumpAndSettle();

      final phraseFinder = find.byType(SelectableText);
      expect(phraseFinder, findsOneWidget);
      final phrase = tester.widget<SelectableText>(phraseFinder).data!;
      expect(phrase.split(' '), hasLength(24));
      expect(find.textContaining('Write the phrase down'), findsOneWidget);
    },
  );
}
