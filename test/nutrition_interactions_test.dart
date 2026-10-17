import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/nutrition_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/nutrition_service.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/widgets/norm_sheet.dart';
import 'package:keramika/widgets/nutrition_trends.dart';
import 'package:keramika/widgets/number_pad.dart';
import 'package:keramika/widgets/rolling_counter.dart';

/// Ввод в питании: встроенная клавиатура, лист нормы и добавление приёма
/// пищи через экран. Тесты держат поведение, которое легко сломать при
/// «косметических» правках анимаций: цифры, потолок разрядов, автоповтор
/// стирания и шаг суточной нормы.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_nutrition_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
    // Файловый ввод-вывод живёт в обычной зоне setUp: внутри testWidgets
    // время фейковое, и настоящие Futures там сами не завершаются.
    await JsonFile.write('nutrition_meals', jsonEncode(<Object>[]));
    await NutritionService().load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  Widget wrap(Widget child) => MaterialApp(
    home: LocaleProvider(locale: const Locale('ru'), child: child),
  );

  testWidgets('клавиатура: ведущий ноль и потолок разрядов', (tester) async {
    final ctrl = TextEditingController();
    var limits = 0;
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: NumberPad(
            controller: ctrl,
            maxDigits: 3,
            onAppendLimit: () => limits++,
          ),
        ),
      ),
    );

    // Слот 9 — цифра «0»: в пустом поле она не должна остаться ведущей.
    await tester.tap(find.byKey(const Key('numberpad_9')));
    await tester.pump();
    expect(ctrl.text, '0');
    await tester.tap(find.byKey(const Key('numberpad_0'))); // «1»
    await tester.pump();
    expect(ctrl.text, '1', reason: 'ведущий ноль заменяется цифрой');
    await tester.tap(find.byKey(const Key('numberpad_9'))); // «0»
    await tester.tap(find.byKey(const Key('numberpad_2'))); // «3»
    await tester.pump();
    expect(ctrl.text, '103');

    // Четвёртая цифра не влезает и не молчит: счётчик упёрся в потолок.
    await tester.tap(find.byKey(const Key('numberpad_1'))); // «2»
    await tester.pump();
    expect(ctrl.text, '103');
    expect(limits, 1);

    // Очистка и стирание.
    await tester.tap(find.byKey(const Key('numberpad_10')));
    await tester.pump();
    expect(ctrl.text, isEmpty);
  });

  testWidgets('клавиатура: удержание «стереть» стирает подряд', (tester) async {
    final ctrl = TextEditingController(text: '12345');
    await tester.pumpWidget(
      wrap(Scaffold(body: NumberPad(controller: ctrl, maxDigits: 5))),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('numberpad_11'))),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(
      ctrl.text.length,
      lessThan(4),
      reason: 'после паузы автоповтор стирает несколько цифр',
    );
    final lengthWhileHolding = ctrl.text.length;
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      ctrl.text.length,
      lengthWhileHolding,
      reason: 'отпускание не стирает лишнюю цифру после автоповтора',
    );
  });

  testWidgets('лист нормы: пресет и ±50 двигают значение плавно', (
    tester,
  ) async {
    final svc = NutritionService();
    await svc.setNorm(2000);
    await tester.pumpWidget(wrap(Scaffold(body: NormSheet(service: svc))));
    await tester.pumpAndSettle();

    double shown() =>
        tester.widget<RollingCounter>(find.byType(RollingCounter)).value;

    expect(shown(), closeTo(2000, 1));

    await tester.tap(find.text('2500'));
    await tester.pumpAndSettle();
    expect(shown(), closeTo(2500, 1), reason: 'пресет ставит ровно 2500');

    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(shown(), closeTo(2550, 1), reason: 'шаг кнопки — 50 ккал');

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(shown(), closeTo(2500, 1));
  });

  testWidgets('узкий экран: лист нормы, клавиатура и тренды без переполнений', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final svc = NutritionService();
    await svc.setNorm(2000);
    final ctrl = TextEditingController(text: '12345');

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                NormSheet(service: svc),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: NumberPad(controller: ctrl, maxDigits: 5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('тренды: полное окно истории без переполнений', (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final svc = NutritionService();
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionTrends(
              days: svc.days,
              norm: 2000,
              todayCalories: 2600,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Окно после подарка 12-го дня — 60 дней: подписи дат обязаны
    // проредиться, а не наехать друг на друга.
    final now = DateTime.now();
    final long = List.generate(
      60,
      (i) => NutritionDay(
        date: now.subtract(Duration(days: 59 - i)),
        calories: (i * 37) % 2500,
        water: 0,
        meals: i.isEven ? 2 : 0,
        macros: const MealMacros(),
      ),
    );
    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: NutritionTrends(days: long, norm: 2000, todayCalories: 2400),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('экран: приём пищи добавляется набором на встроенной панели', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final svc = NutritionService();
    // Внутри `testWidgets` время фейковое, и настоящий файловый ввод-вывод
    // сам не завершается: первое чтение данных экрана отпускаем в реальный
    // цикл событий через runAsync, иначе кнопка добавления не появится.
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(const NutritionScreen()));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final name = find.byType(TextField).at(0);
    await tester.ensureVisible(name);
    await tester.enterText(name, 'Суп');
    await tester.pump();

    final calories = find.byType(TextField).at(1);
    await tester.ensureVisible(calories);
    await tester.tap(calories);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 5 0 0 — слоты 4, 9, 9.
    for (final slot in [4, 9, 9]) {
      final key = find.byKey(Key('numberpad_$slot'));
      await tester.ensureVisible(key);
      await tester.tap(key);
      await tester.pump();
    }
    expect(svc.todayCalories, 0, reason: 'цифры ещё не сохранены');
    expect(
      tester.widget<TextField>(calories).controller?.text,
      '500',
      reason: 'встроенная панель пишет в поле калорий',
    );

    final add = find.byKey(const ValueKey('add_meal_loaded'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    // Сохранение — настоящая запись файла: отпускаем её в реальный цикл.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();

    expect(svc.todayCalories, 500);
    expect(find.text('Суп'), findsWidgets);
  });
}
