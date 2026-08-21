import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/screens/habits_screen.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/prefs.dart';

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
    await svc.load();
    await svc.add(Habit(
      id: 'h1',
      name: 'Пить воду',
      iconCodePoint: 57690,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
    ));
    await svc.add(Habit(
      id: 'h2',
      name: 'Зарядка',
      iconCodePoint: 57690,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
    ));
    await svc.add(Habit(
      id: 'h3',
      name: 'Не грызть ногти',
      iconCodePoint: 57690,
      activeDays: const [1, 2, 3, 4, 5, 6, 7],
      type: 'bad',
    ));
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

  testWidgets('Habits list with items renders without exception',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const LocaleProvider(
        locale: Locale('ru'),
        child: MaterialApp(
          home: Scaffold(body: HabitsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Пить воду'), findsOneWidget);
    expect(find.text('Зарядка'), findsOneWidget);
    expect(find.text('Не грызть ногти'), findsOneWidget);
  });
}
