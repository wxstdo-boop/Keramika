import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/developer_corner_screen.dart';

void main() {
  testWidgets('developer code can be revealed and accepted', (tester) async {
    var unlocked = false;
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: DeveloperModePasswordDialog(
              title: 'Режим разработчика',
              prompt: 'Введите код доступа',
              invalidCode: 'Неверный код',
              cancelLabel: 'Отмена',
              unlockLabel: 'Открыть',
              onCancel: () {},
              onUnlock: () async => unlocked = true,
            ),
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
      reason: 'the glyph transition fades before switching mask state',
    );
    await tester.pump(const Duration(milliseconds: 430));
    expect(find.byTooltip('Скрыть код'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), '1111');
    final dialogSize = tester.getSize(find.byType(Dialog));
    await tester.tap(find.text('Открыть'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('Неверный код'), findsOneWidget);
    expect(tester.getSize(find.byType(Dialog)), dialogSize);
    expect(
      tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .any(
            (animation) =>
                animation.duration == const Duration(milliseconds: 240),
          ),
      isTrue,
    );
    expect(unlocked, isFalse);

    await tester.enterText(find.byType(TextField), '7720');
    await tester.tap(find.text('Открыть'));
    await tester.pump();
    expect(unlocked, isTrue);
  });

  testWidgets('password dialog does not move when keyboard opens', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: DeveloperModePasswordDialog(
              title: 'Режим разработчика',
              prompt: 'Введите код доступа',
              invalidCode: 'Неверный код',
              cancelLabel: 'Отмена',
              unlockLabel: 'Открыть',
              onCancel: () {},
              onUnlock: () async {},
            ),
          ),
        ),
      ),
    );
    final centerBefore = tester.getCenter(find.byType(Dialog));

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pump();

    expect(tester.getCenter(find.byType(Dialog)), centerBefore);
    tester.view.resetViewInsets();
  });

  testWidgets('developer corner is a screen with inline controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: DeveloperCornerScreen(
            title: 'Уголок разработчика',
            controlsLabel: 'ЭКСПЕРИМЕНТАЛЬНЫЕ НАСТРОЙКИ',
            subtitle: 'Скрытые настройки',
            disableLabel: 'Выключить режим разработчика',
            developerPrompt: '',
            onSaveDeveloperPrompt: (_) async {},
            accent: Colors.deepPurple,
            onDisable: () async {},
            children: const [
              ListTile(title: Text('Первая настройка')),
              ListTile(title: Text('Вторая настройка')),
              ListTile(title: Text('Третья настройка')),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Уголок разработчика'),
      ),
      findsOneWidget,
    );
    expect(find.text('Первая настройка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'developer prompt is limited to 10,000 characters and autosaves',
    (tester) async {
      String? saved;
      await tester.pumpWidget(
        LocaleProvider(
          locale: const Locale('ru'),
          child: MaterialApp(
            home: Scaffold(
              body: DeveloperPromptEditor(
                initialValue: '',
                accent: Colors.deepPurple,
                onSave: (value) async => saved = value,
              ),
            ),
          ),
        ),
      );

      final input = 'а' * 10005;
      await tester.enterText(find.byType(TextField), input);
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text
            .length,
        10000,
      );
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump();

      expect(saved, hasLength(10000));
      expect(find.textContaining('/ 10 000'), findsNothing);
    },
  );
}
