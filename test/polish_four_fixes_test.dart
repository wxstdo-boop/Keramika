import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/screens/add_habit_screen.dart';
import 'package:keramika/screens/add_task_screen.dart';
import 'package:keramika/screens/habits_screen.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';

/// Регрессы на четыре правки плавности/вида.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_four_fixes');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    // Сидирование — ВНЕ FakeAsync-зоны testWidgets: реальный файловый I/O
    // сервисов внутри теста завис бы навсегда.
    final svc = HabitService();
    await svc.load();
    for (final id in svc.habits.map((Habit h) => h.id).toList()) {
      await svc.remove(id);
    }
    await svc.add(
      Habit(
        id: 'bad1',
        name: 'Не грызть ногти',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        type: 'bad',
        doneToday: true,
        lastDoneDate: DateTime.now(),
      ),
    );
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

  /// Правая подпись срока не должна съезжать при смене «Сегодня» → «Завтра»:
  /// правый край закреплён, меняется только левый.
  testWidgets('подпись срока держит правый край при смене дня', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: AddTaskScreen()),
      ),
    );
    await tester.pump();

    final label = find.byKey(const ValueKey('due_label'));

    await tester.tap(find.text('Сегодня').first);
    await tester.pumpAndSettle();
    final todayRight = tester.getRect(label).right;

    await tester.tap(find.text('Завтра').first);
    await tester.pumpAndSettle();
    final tomorrowRight = tester.getRect(label).right;

    expect(
      tomorrowRight,
      closeTo(todayRight, 0.5),
      reason: 'правый край подписи закреплён — при смене дня не «дёргает вправо»',
    );
  });

  /// Чипы срока не меняют ширину при выборе: постоянный вес шрифта.
  testWidgets('выбор чипа срока не двигает соседей', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: AddTaskScreen()),
      ),
    );
    await tester.pump();

    final before = tester.getRect(find.text('Через неделю')).left;
    await tester.tap(find.text('Сегодня').first);
    await tester.pumpAndSettle();
    final after = tester.getRect(find.text('Через неделю')).left;

    expect(
      after,
      closeTo(before, 0.5),
      reason: 'вес чипа постоянный — соседи по Wrap не сдвигаются',
    );
  });

  /// Заметка при смене типа привычки существует в ОДНОМ экземпляре: раньше
  /// AnimatedSwitcher на 280 мс держал оба поддерева — читалось как лаг.
  testWidgets('заметка в форме привычки не дублируется при смене типа', (
    WidgetTester tester,
  ) async {
    // Шире узкого экрана: в форме есть не связанный с этой задачей ряд
    // кнопок дней, который на 411dp не помещается.
    tester.view.physicalSize = const Size(520, 1000) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: AddHabitScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final reveal = find.byKey(const ValueKey('notes_reveal'));
    expect(find.text('Заметки'), findsOneWidget);
    expect(tester.getSize(reveal).height, greaterThan(1.0));

    await tester.tap(find.text('Вредная'));
    // Пока анимация идёт — поле заметок всё равно ОДНО: раньше
    // AnimatedSwitcher держал две копии (два TextField с тикером) — лаг.
    await tester.pump(const Duration(milliseconds: 140));
    expect(
      find.text('Заметки'),
      findsOneWidget,
      reason: 'в переходе нет двух копий поля заметок — нет лага',
    );
    await tester.pumpAndSettle();

    // Блок заметок схлопнут (heightFactor → 0).
    expect(tester.getSize(reveal).height, lessThan(1.0));
  });

  /// Бейдж «Сегодня очищено» на тёмной теме — плотная капсула (errorContainer),
  /// а не мутная полупрозрачная плашка.
  testWidgets('бейдж «Сегодня очищено» читается на тёмной теме', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF8E6DB8),
              brightness: Brightness.dark,
            ),
          ),
          home: const Scaffold(body: HabitsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final badge = find.text('Сегодня очищено');
    expect(badge, findsOneWidget);

    final container = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: badge,
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    final deco = container.decoration! as BoxDecoration;
    final cs = ColorScheme.fromSeed(
      seedColor: const Color(0xFF8E6DB8),
      brightness: Brightness.dark,
    );
    expect(
      deco.color,
      cs.errorContainer,
      reason: 'тёмная тема — плотная капсула, а не полупрозрачный градиент',
    );
    expect(deco.gradient, isNull);
  });
}
