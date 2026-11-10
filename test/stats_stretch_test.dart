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
}
