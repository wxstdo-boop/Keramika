import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/stats_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';

/// Регрессия: экран статистики листается ТОЙ ЖЕ упругой физикой, что и
/// остальные списки приложения (BouncingScrollPhysics). Раньше здесь стоял
/// Clamping — край «не отдавал», и статистика выбивалась из общего поведения
/// (пользователь: «при скролле нет отдачи как на других экранах»).
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_stats_stretch');
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

  testWidgets('stats: физика упругая (Bouncing), как на остальных экранах', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const RealityCheckStatsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    final physics = scrollable.position.physics;

    // AlwaysScrollable поверх Bouncing: pull-to-refresh работает даже на
    // коротком контенте, а края отдают упруго.
    expect(
      physics,
      isA<AlwaysScrollableScrollPhysics>(),
      reason: 'физика должна быть AlwaysScrollable',
    );
    expect(
      physics.parent,
      isA<BouncingScrollPhysics>(),
      reason: 'родительская физика — Bouncing (упругая), не Clamping: '
          'статистика должна отдавать край как остальные экраны',
    );

    // Скролл вообще работает — драг меняет позицию.
    final scv = find.byType(SingleChildScrollView);
    final gd = await tester.startGesture(tester.getCenter(scv));
    for (var j = 0; j < 10; j++) {
      await gd.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gd.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stats: контент растягивается при протяжке за край', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const RealityCheckStatsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    final scv = find.byType(SingleChildScrollView);
    final sc = tester.state<ScrollableState>(find.byType(Scrollable));

    /// Вертикальный масштаб деформации растяжения (её Transform помечен
    /// ключом). В покое — 1.0, при протяжке — больше.
    double stretchScale() => tester
        .widget<Transform>(find.byKey(const ValueKey('stats_stretch')))
        .transform
        .storage[5];

    expect(stretchScale(), closeTo(1.0, 0.001), reason: 'в покое растяжения нет');

    // Тянем за НИЖНИЙ край: список уже внизу, движение уходит за границу.
    sc.position.jumpTo(sc.position.maxScrollExtent);
    await tester.pump();
    final down = await tester.startGesture(
      tester.getTopLeft(scv) + const Offset(12, 300),
    );
    for (var j = 0; j < 10; j++) {
      await down.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      stretchScale(),
      greaterThan(1.01),
      reason: 'при протяжке за нижний край контент должен растягиваться',
    );

    // Отпустили — упругая пружина возвращает всё в покой.
    await down.up();
    for (var j = 0; j < 240; j++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      stretchScale(),
      closeTo(1.0, 0.002),
      reason: 'после отпускания растяжение должно сойти на нет',
    );

    // То же самое за ВЕРХНИЙ край.
    sc.position.jumpTo(sc.position.minScrollExtent);
    await tester.pump();
    final up = await tester.startGesture(
      tester.getTopLeft(scv) + const Offset(12, 300),
    );
    for (var j = 0; j < 10; j++) {
      await up.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      stretchScale(),
      greaterThan(1.01),
      reason: 'при протяжке за верхний край контент должен растягиваться',
    );
    await up.up();
    for (var j = 0; j < 240; j++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(stretchScale(), closeTo(1.0, 0.002));
    expect(tester.takeException(), isNull);
  });
}
