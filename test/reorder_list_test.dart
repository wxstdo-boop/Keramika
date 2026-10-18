import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/screens/habits_screen.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/widgets/animated_strike_text.dart';

/// Регрессионный тест: ReorderableListView падал с "Null check operator
/// used on a null value" в release-режиме, если элемент внутри списка
/// не имел key (обёртка SwipeToDelete потеряла его). Список с элементами
/// должен рендериться без исключения.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 1));
    tmpDir = await Directory.systemTemp.createTemp('keramika_reorder_test');
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
    // Сидирование выполняется в setUp — вне FakeAsync-зоны testWidgets,
    // иначе реальный файловый I/O сервисов зависнет навсегда.
    final svc = HabitService();
    await svc.debugClear();
    await svc.load();
    await svc.add(
      Habit(
        id: 'h1',
        name: 'Пить воду',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
    );
    await svc.add(
      Habit(
        id: 'h2',
        name: 'Зарядка',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
    );
    await svc.add(
      Habit(
        id: 'h3',
        name: 'Не грызть ногти',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        type: 'bad',
      ),
    );
    expect(svc.habits.map((habit) => habit.name), [
      'Пить воду',
      'Зарядка',
      'Не грызть ногти',
    ]);
    expect(await JsonFile.read('habits'), contains('Пить воду'));
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

  testWidgets('Habits list with items renders without exception', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const LocaleProvider(
        locale: Locale('ru'),
        child: MaterialApp(home: Scaffold(body: HabitsScreen())),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
    expect(HabitService().habits, hasLength(3));
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AnimatedStrikeText && widget.text == 'Пить воду',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is AnimatedStrikeText && widget.text == 'Зарядка',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AnimatedStrikeText && widget.text == 'Не грызть ногти',
      ),
      findsOneWidget,
    );
  });
}
