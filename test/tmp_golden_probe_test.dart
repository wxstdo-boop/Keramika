import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/lock_screen.dart';
import 'package:keramika/services/prefs.dart';

/// ВРЕМЕННЫЙ инструмент: рендерит диалог выхода в каждой локали и кладёт PNG
/// (запуск с --update-goldens), чтобы глазами проверить вёрстку French-кнопок.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'app_pin': '1234'});
    await initPrefs();
  });

  for (final lang in ['ru', 'en', 'fr']) {
    testWidgets('golden $lang', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        LocaleProvider(
          locale: Locale(lang),
          child: const MaterialApp(home: LockScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));

      final wrap = tester.getRect(find.byType(Wrap).last);
      final cancelText = switch (lang) {
        'fr' => 'Annuler',
        'en' => 'Cancel',
        _ => 'Отмена',
      };
      final exitText = lang == 'fr' ? 'Quitter' : 'Выйти';
      final cancel = tester.getRect(find.text(cancelText));
      final exit = tester.getRect(find.text(exitText));
      debugPrint('[$lang] wrap=$wrap');
      debugPrint('[$lang] cancel=$cancel exit=$exit');
      expect(exit.right, lessThanOrEqualTo(wrap.right));
      expect(cancel.left, greaterThanOrEqualTo(wrap.left));
    });
  }
}
