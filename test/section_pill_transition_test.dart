import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/alarm.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/screens/home_screen.dart';
import 'package:keramika/services/alarm_service.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/task_service.dart';
import 'package:keramika/widgets/animated_fab_row.dart';
import 'package:keramika/widgets/section_pill.dart';
import 'package:keramika/widgets/icons/keramika_icons.dart';

/// Таблетка разделов теперь ВСЕГДА полная: она не срезается по скроллу.
/// Раньше ClipRect+heightFactor оставлял на середине прокрутки половину
/// капсулы и белую полосу под ней — «белую шторку». Эти тесты фиксируют
/// новое поведение: высота таблетки не меняется, а разделы листаются под ней.
void main() {
  late Directory tmpDir;

  const double fullPill = 64;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    sectionPillSnapByPage.clear();
    sectionPillSnapTarget.value = null;
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'welcome_dismissed': true,
      'popup_warning_shown': true,
      'last_home_tab': 0,
    });
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_pill_transition');
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
    await AlarmService().load();
    for (final a in AlarmService().alarms.toList()) {
      await AlarmService().remove(a.id);
    }
    for (var i = 0; i < 20; i++) {
      await AlarmService().add(
        Alarm(id: 'a$i', time: TimeOfDay(hour: 6, minute: i % 60)),
      );
    }
    await HabitService().load();
    for (final h in HabitService().habits.toList()) {
      await HabitService().remove(h.id);
    }
    for (var i = 0; i < 10; i++) {
      await HabitService().add(
        Habit(
          id: 'h$i',
          name: 'Привычка $i',
          iconCodePoint: 57690,
          activeDays: const [1, 2, 3, 4, 5, 6, 7],
        ),
      );
    }
    await TaskService().load();
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

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
  }

  double pillHeight(WidgetTester tester) {
    final finder = find.byType(SectionPill);
    if (finder.evaluate().isEmpty) return 0;
    return tester.getSize(finder.first).height;
  }

  Future<void> swipePage(WidgetTester tester, {required bool left}) async {
    final g = await tester.startGesture(
      left ? const Offset(385, 62) : const Offset(26, 62),
    );
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(Offset(left ? -30 : 30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
  }

  testWidgets('прокрутка: таблетка остаётся полной, без белой шторки', (
    tester,
  ) async {
    await boot(tester);
    expect(pillHeight(tester), fullPill);

    await tester.drag(
      find.byType(HomeScreen),
      const Offset(0, -120),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      pillHeight(tester),
      fullPill,
      reason: 'таблетка не должна срезаться по скроллу',
    );
  });

  testWidgets('свайп между разделами: таблетка остаётся полной', (tester) async {
    await boot(tester);
    expect(pillHeight(tester), fullPill);

    await swipePage(tester, left: true);
    expect(sectionCurrentIndex.value, 1);
    expect(pillHeight(tester), fullPill);

    await swipePage(tester, left: false);
    expect(sectionCurrentIndex.value, 0);
    expect(pillHeight(tester), fullPill);
  });

  testWidgets('тап по разделу: переключает страницу, таблетка полная', (
    tester,
  ) async {
    await boot(tester);
    await swipePage(tester, left: true);
    expect(sectionCurrentIndex.value, 1);

    await tester.tap(find.byType(KkAlarmIcon).first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));

    expect(sectionCurrentIndex.value, 0);
    expect(pillHeight(tester), fullPill);
  });

  testWidgets('тяга таблетки ведёт экраны плавно: карусель догоняет палец, '
      'не прыгает 1:1, и доводится на отпускании', (tester) async {
    await boot(tester);
    expect(sectionRailPage.value, 0);

    final center = tester.getCenter(find.byType(SectionPill).first);
    final g = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 20));

    // Первый сдвиг лишь распознаёт жест (touch-slop) — камень ещё стоит.
    await g.moveBy(const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    // Осознанный сдвиг вправо: палец задаёт цель таблетки.
    await g.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final target = sectionDragPage.value;
    expect(target, isNotNull, reason: 'палец ведёт камень');
    expect(target!, greaterThan(0));

    // ОДИН кадр спустя карусель ещё НЕ на цели: экран догоняет палец
    // пружиной (плавно), а не телепортируется 1:1.
    await tester.pump(const Duration(milliseconds: 16));
    final justAfter = sectionRailPage.value;
    expect(
      justAfter,
      lessThan(target),
      reason: 'экран не должен прыгать на цель в первом же кадре',
    );

    // Отпускаем: пружина доводит раздел до ближайшего.
    await g.up();
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final settled = sectionRailPage.value;
    expect(
      (settled - settled.round()).abs(),
      lessThan(0.05),
      reason: 'после отпускания карусель успокаивается на целом разделе',
    );
    expect(sectionCurrentIndex.value, settled.round());
  });
}
