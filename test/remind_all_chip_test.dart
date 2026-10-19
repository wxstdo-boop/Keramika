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

/// Значок «Вспомнить всё» — часть кластера действий привычки.
///
/// Раньше это был «голый» значок, прижатый к левому верхнему углу блока:
/// рядом с подложенными кнопками раскрытия и карандаша он читался чужим и
/// висел выше остальных. Теперь у него та же полупрозрачная подложка, что и
/// у соседей, а по вертикали он встаёт по центру блока.
void main() {
  late Directory tmpDir;

  Future<void> boot({required String? reminder}) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 1));
    tmpDir = await Directory.systemTemp.createTemp('keramika_remind_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
        );
    final svc = HabitService();
    await svc.debugClear();
    await svc.load();
    await svc.add(
      Habit(
        id: 'h1',
        name: 'Пить воду',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        reminderTime: reminder,
      ),
    );
  }

  Future<void> shutdown() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> pumpScreen(WidgetTester tester) async {
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
  }

  group('с напоминанием', () {
    setUp(() => boot(reminder: '09:00'));
    tearDown(shutdown);

    testWidgets('«Вспомнить всё» — кружок с подложкой, а не голый значок', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(tester.takeException(), isNull);

      final chip = find.byKey(const ValueKey('remind_all_chip'));
      expect(chip, findsOneWidget);

      final size = tester.getSize(chip);
      expect(size.width, size.height, reason: 'подложка должна быть круглой');
      expect(size.width, greaterThan(0));

      final box = tester.widget<Container>(chip).decoration! as BoxDecoration;
      expect(box.shape, BoxShape.circle);
      expect(
        box.color!.a,
        lessThan(1.0),
        reason: 'подложка полупрозрачная, как у соседних кнопок',
      );
    });
  });

  group('без напоминания', () {
    setUp(() => boot(reminder: null));
    tearDown(shutdown);

    testWidgets('кружка нет', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('remind_all_chip')), findsNothing);
    });
  });
}
