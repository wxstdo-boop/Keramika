import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/habit.dart';
import 'package:agysha/models/task.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/services/score_service.dart';
import 'package:agysha/services/task_service.dart';

/// Тесты системы очков: копилка растёт от действий, не отбирается назад и
/// показывается в профиле разбором «за что начислено».
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 5));
    tmpDir = await Directory.systemTemp.createTemp('agysha_score');
    // Сервисы пишут на диск через `path_provider`: без мока канала плагин
    // бросает MissingPluginException (см. AGENTS.md).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    await ScoreService().reset();
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

  test('очки начисляются за действие и НЕ отбираются при отмене', () async {
    final score = ScoreService();
    expect(score.total, 0);

    await score.award(ScoreKind.task);
    expect(score.pointsOf(ScoreKind.task), ScoreWeight.task);
    expect(score.total, ScoreWeight.task);

    // Отмена галочки очков не снимает: достижения не отбираем. Отдельного
    // «отрицательного» вызова у сервиса просто нет — проверяем, что
    // повторное начисление только прибавляет.
    await score.award(ScoreKind.task);
    expect(score.pointsOf(ScoreKind.task), ScoreWeight.task * 2);
  });

  test('привычка приносит очки по длине стрика', () async {
    final habits = HabitService();
    await habits.load();
    await habits.add(
      Habit(id: 'h1', name: 'Зарядка', type: 'good'),
    );

    final habit = habits.habits.first;
    await habits.toggle(habit.id);
    // Первая отметка — стрик 1, значит ровно один вес за привычку.
    expect(
      ScoreService().pointsOf(ScoreKind.habit),
      ScoreWeight.habitPerStreak,
    );
  });

  test('выполненная задача даёт очки и активный день, отмена — нет', () async {
    final tasks = TaskService();
    await tasks.load();
    await tasks.add(Task(id: 't1', title: 'Полить цветы'));
    final task = tasks.tasks.first;

    await tasks.toggle(task.id);
    expect(ScoreService().pointsOf(ScoreKind.task), ScoreWeight.task);
    expect(ScoreService().pointsOf(ScoreKind.day), ScoreWeight.activeDay);

    // Сняли галочку — копилка прежняя.
    await tasks.toggle(task.id);
    expect(ScoreService().pointsOf(ScoreKind.task), ScoreWeight.task);
    expect(ScoreService().pointsOf(ScoreKind.day), ScoreWeight.activeDay);
  });

  test('активный день начисляется один раз в сутки', () async {
    final score = ScoreService();
    await score.markActiveDay();
    expect(score.pointsOf(ScoreKind.day), ScoreWeight.activeDay);
    await score.markActiveDay();
    await score.markActiveDay();
    expect(score.pointsOf(ScoreKind.day), ScoreWeight.activeDay);
  });

  test('итог рейтинга складывает копилку и текущую активность', () async {
    final profile = ProfileService();
    await profile.load();
    await ScoreService().award(ScoreKind.meal, 2);
    // Копилка уже не пуста, значит рейтинг её видит.
    expect(profile.localScore(), greaterThanOrEqualTo(ScoreWeight.meal * 2));
  });

  testWidgets('профиль показывает карточку очков с разбором', (tester) async {
    tester.view.physicalSize = const Size(411, 1400) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await ScoreService().award(ScoreKind.task, 3);
    await ScoreService().award(ScoreKind.ai, 2);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Твои очки'), findsOneWidget);
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Общение с Адой'), findsOneWidget);
    // Нулевые категории не показываем: список пустых строк читался бы
    // «сломанным».
    expect(find.text('Приёмы пищи'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
