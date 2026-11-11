import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/habit.dart';
import 'package:agysha/screens/habits_screen.dart';
import 'package:agysha/services/habit_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';

/// Глобальная физика приложения (main.dart) — BouncingScrollPhysics.
class _Bouncing extends MaterialScrollBehavior {
  const _Bouncing();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics();
}

/// Регресс на «в самом низу дёргает или вовсе стопорится»: автоскролл у
/// кромки считает шаг как `скорость × dt`. Пока палец стоит в середине
/// списка, `t == 0` и функция выходит раньше, чем двигала метку времени —
/// поэтому в первый кадр у кромки накопленный `dt` (всё время простоя) давал
/// один гигантский шаг: список скачком улетал к `maxScrollExtent`.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_as');
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
    final svc = HabitService();
    await svc.load();
    for (final id in svc.habits.map((Habit h) => h.id).toList()) {
      await svc.remove(id);
    }
    for (var i = 0; i < 30; i++) {
      await svc.add(
        Habit(
          id: 'h$i',
          name: 'Привычка $i',
          iconCodePoint: 57690,
          activeDays: const [1, 2, 3, 4, 5, 6, 7],
        ),
      );
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

  testWidgets('вход в кромочную зону не даёт скачка автоскролла', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          scrollBehavior: _Bouncing(),
          home: Scaffold(body: HabitsScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    final pos = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(pos.maxScrollExtent, greaterThan(0));

    final start = tester.getCenter(
      find.byType(ReorderableDelayedDragStartListener).first,
    );
    final g = await tester.startGesture(start);
    // Ждём long-press (drag-ручка стартует по удержанию).
    await tester.pump(const Duration(milliseconds: 700));
    // Уводим прокси в середину экрана и держим там: тикер автоскролла
    // крутится каждый кадр, но t == 0 (вне обеих кромочных зон).
    await g.moveTo(Offset(start.dx, 500));
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final beforeEdge = pos.pixels;
    // Резко уводим палец к нижней кромке. Старый код здесь брал накопленный
    // dt (~2.4 с) и прыгал к самому низу одним кадром.
    await g.moveTo(Offset(start.dx, 880));
    final steps = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      steps.add(pos.pixels);
    }
    await g.up();

    var maxJump = 0.0;
    var prev = beforeEdge;
    for (final p in steps) {
      if ((p - prev).abs() > maxJump) maxJump = (p - prev).abs();
      prev = p;
    }
    expect(tester.takeException(), isNull);
    // Со старым кодом первый же кадр у кромки улетал к maxScrollExtent
    // (десятки-сотни px). Теперь шаг кромки — это `скорость × кадр`.
    expect(
      maxJump,
      lessThan(20.0),
      reason: 'автоскролл у кромки не должен прыгать кадром',
    );
  });
}
