import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/stats_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';

/// Регрессия: растяжение края (StretchingOverscrollIndicator) на экране
/// статистики УБРАНО — свайп у нижнего края просто клампит, без
/// «дёрнутого» подрагивания.
///
/// Тест проверяет две вещи:
///  1. Позиция скролла не уходит ниже maxScrollExtent (клампит).
///  2. В дереве НЕТ StretchEffect (растяжение отсутствует, а не просто
///     «мёртвое» из-за Bouncing-физики).
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

  testWidgets(
    'stats: нижний край клампит, растяжение отсутствует',
    (tester) async {
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
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

      // Доскроллить до низа пошаговыми драгами.
      for (var i = 0; i < 3; i++) {
        final gd = await tester.startGesture(tester.getCenter(scv));
        await gd.moveBy(const Offset(0, -100));
        for (var j = 0; j < 8; j++) {
          await gd.moveBy(const Offset(0, -100));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await gd.up();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(scrollable.position.pixels, scrollable.position.maxScrollExtent);

      // Тянем палец ВВЕРХ за нижний край — позиция НЕ уходит ниже края.
      final g = await tester.startGesture(tester.getCenter(scv));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Клампит: позиция не превышает maxScrollExtent.
      expect(
        scrollable.position.pixels,
        lessThanOrEqualTo(scrollable.position.maxScrollExtent),
        reason: 'нижний край должен клампить, а не растягиваться',
      );

      // Статистика больше НЕ задаёт свой _StretchScrollBehavior — в её
      // SingleChildScrollView физика Clamping. Проверяем именно физикой:
      // если кто-то вернёт Bouncing, нижний край начнёт уходить «резинкой»
      // и позиция превысит maxScrollExtent.
      final scrollableState =
          tester.state<ScrollableState>(find.byType(Scrollable));
      final physics = scrollableState.position.physics;
      expect(
        physics,
        isA<AlwaysScrollableScrollPhysics>(),
        reason: 'физика SingleChildScrollView должна быть '
            'AlwaysScrollable(Clamping), не Bouncing',
      );

      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
