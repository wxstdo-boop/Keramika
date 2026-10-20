import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/task.dart';
import 'package:keramika/screens/tasks_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/task_service.dart';

/// Задачи делятся на две полки — «Активные» и «Выполненные» — ровно тогда,
/// когда появляется хотя бы одна выполненная (как Полезные/Вредные в
/// привычках). И галка НЕ снимается обратно: повторный тап по выполненной
/// задаче ничего не меняет.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 3));
    tmpDir = await Directory.systemTemp.createTemp('keramika_task_shelves');
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
    // Сидирование — вне FakeAsync-зоны testWidgets, иначе реальный файловый
    // I/O сервиса зависнет навсегда.
    final svc = TaskService();
    await svc.load();
    for (final t in svc.tasks.toList()) {
      await svc.remove(t.id);
    }
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

  /// Реальный файловый I/O внутри fake-async зоны testWidgets не проходит,
  /// поэтому и запись, и загрузку выполняем через [WidgetTester.runAsync].
  Future<void> seedAndPump(
    WidgetTester tester,
    List<Task> tasks, {
    ThemeData? theme,
  }) async {
    await tester.runAsync(() async {
      final svc = TaskService();
      for (final t in tasks) {
        await svc.add(t);
      }
    });
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(theme: theme, home: const TasksScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Относительная яркость цвета (WCAG 2.1).
  double luminance(Color c) {
    double ch(double v) {
      v = v / 255.0;
      return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * ch(c.r * 255) + 0.7152 * ch(c.g * 255) + 0.0722 * ch(c.b * 255);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Текст задачи рендерится через RichText (AnimatedStrikeText), поэтому
  /// find.text его не видит — ищем саму карточку по ключу.
  Finder card(String id) => find.byKey(ValueKey('card__$id'));

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('без выполненных задач полок нет — один список', (tester) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме'),
    ]);

    expect(find.text('Активные'), findsNothing);
    expect(find.text('Выполненные'), findsNothing);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
  });

  testWidgets('с выполненной задачей список делится на две полки', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме', done: true),
    ]);

    expect(find.text('Активные'), findsOneWidget);
    expect(find.text('Выполненные'), findsOneWidget);
    expect(card('a1'), findsOneWidget);
    expect(card('a2'), findsOneWidget);
  });

  testWidgets('отметка задачи переносит её на полку «Выполненные»', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко'),
      Task(id: 'a2', title: 'Позвонить маме', done: true),
    ]);

    expect(find.byIcon(Icons.check), findsOneWidget);

    await tapAndSettle(
      tester,
      find.byKey(const ValueKey('task_toggle_a1')),
    );

    expect(
      TaskService().tasks.firstWhere((t) => t.id == 'a1').done,
      isTrue,
      reason: 'тап отмечает задачу выполненной',
    );
    // Обе задачи теперь на полке «Выполненные»: две галки.
    expect(find.byIcon(Icons.check), findsNWidgets(2));
  });

  testWidgets('повторный тап по выполненной задаче НЕ снимает галку', (
    tester,
  ) async {
    await seedAndPump(tester, [
      Task(id: 'a1', title: 'Купить молоко', done: true),
    ]);

    await tapAndSettle(
      tester,
      find.byKey(const ValueKey('task_toggle_a1')),
    );

    expect(
      TaskService().tasks.firstWhere((t) => t.id == 'a1').done,
      isTrue,
      reason: 'галку снять нельзя — задача остаётся выполненной',
    );
  });

  /// «Всё читается»: заголовки полок должны быть контрастны фону в обеих
  /// темах — приглушённый цвет «Выполненных» на тёмном фоне сливался бы.
  for (final dark in [false, true]) {
    testWidgets(
      'заголовки полок читаются на ${dark ? 'тёмной' : 'светлой'} теме',
      (tester) async {
        final base = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8E6DB8),
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
        );
        await seedAndPump(
          tester,
          [
            Task(id: 'a1', title: 'Купить молоко'),
            Task(id: 'a2', title: 'Позвонить маме', done: true),
          ],
          theme: base,
        );

        final bg = base.scaffoldBackgroundColor;
        for (final label in ['Активные', 'Выполненные']) {
          final text = tester.widget<Text>(find.text(label));
          final color = text.style!.color!;
          expect(
            contrast(color, bg),
            greaterThanOrEqualTo(4.5),
            reason: '«$label» должен читаться на фоне (WCAG AA)',
          );
        }
      },
    );
  }
}
