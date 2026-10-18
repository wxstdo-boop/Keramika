import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/lock_screen.dart';
import 'package:keramika/services/pin_service.dart';
import 'package:keramika/services/prefs.dart';

/// Диалог подтверждения выхода живёт поверх PIN-экрана, но его строки обязаны
/// приходить из [Translations] ровно как у кнопок: раньше текст был вшит
/// по-русски, и в en/fr-интерфейсе диалог оставался русским, хотя «Отмена» и
/// «Выйти» рядом с ним переводились.
///
/// Тест держит две вещи: (1) обе строки есть во всех трёх локалях,
/// (2) в интерфейс не просачивается имя ключа — `Translations` возвращает
/// ключ как есть, если перевода нет, и такая опечатка выглядела бы как
/// «exitConfirmTitle» прямо в диалоге.
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // ПИН есть → экран не разблокируется сам и рисует капсулу с «Выйти».
    SharedPreferences.setMockInitialValues({'app_pin': '1234'});
    await initPrefs();
    PinService.resetCacheForTesting();
  });

  /// Поднять PIN-экран в нужной локали и открыть стеклянный диалог выхода.
  Future<void> openExitDialog(WidgetTester tester, String lang) async {
    // Экран блокировки рассчитан на полный экран телефона: на дефолтной
    // поверхности 800×600 его колонка не влезает и падает в RenderFlex
    // overflow, что к диалогу отношения не имеет. Берём геометрию реального
    // аппарата (Redmi Note 12: 1080×2400 при DPR 2.75).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: Locale(lang),
        child: const MaterialApp(home: LockScreen()),
      ),
    );
    // initState читает наличие ПИНа асинхронно: первый кадр — спиннер.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    await tester.tap(find.byIcon(Icons.logout_rounded));
    // `pumpAndSettle` здесь нельзя: фон окна (DripBackdrop) и медальон
    // крутятся бесконечно, поэтому прокручиваем ровно переход маршрута.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
  }

  testWidgets('ru: строки диалога выхода приходят из переводов', (
    WidgetTester tester,
  ) async {
    await openExitDialog(tester, 'ru');

    expect(tester.takeException(), isNull);
    expect(
      find.text('Ты точно хочешь принять зелёную таблетку?'),
      findsOneWidget,
    );
    expect(find.text('Кнопка «Выйти» закроет приложение.'), findsOneWidget);
    expect(find.text('Выйти'), findsWidgets);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('exitConfirmTitle'), findsNothing);
    expect(find.text('exitConfirmBody'), findsNothing);
  });

  testWidgets('en: exit dialog is localized', (WidgetTester tester) async {
    await openExitDialog(tester, 'en');

    expect(tester.takeException(), isNull);
    expect(
      find.text('Are you sure you want to take the green pill?'),
      findsOneWidget,
    );
    expect(find.text('The “Exit” button closes the app.'), findsOneWidget);
    expect(find.text('Exit'), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('exitConfirmTitle'), findsNothing);
    expect(find.text('exitConfirmBody'), findsNothing);

    // Диалог закрывается без побочных ошибок.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fr: la boîte de dialogue de sortie est traduite', (
    WidgetTester tester,
  ) async {
    await openExitDialog(tester, 'fr');

    expect(tester.takeException(), isNull);
    expect(
      find.text('Veux-tu vraiment prendre la pilule verte ?'),
      findsOneWidget,
    );
    expect(
      find.text('Le bouton « Quitter » fermera l’application.'),
      findsOneWidget,
    );
    expect(find.text('Quitter'), findsWidgets);
    expect(find.text('Annuler'), findsOneWidget);
    expect(find.text('exitConfirmTitle'), findsNothing);
    expect(find.text('exitConfirmBody'), findsNothing);
  });
}
