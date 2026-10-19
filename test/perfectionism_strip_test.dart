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
import 'package:keramika/services/settings_service.dart';

/// Полоса перфекционизма — «сцена» с летящей стаей. Проверяем два видимых
/// свойства, о которых просил пользователь:
///
/// 1. Птицы начинают и заканчивают ВНУТРИ окна — у кромок прозрачность
///    падает до нуля, поэтому [ClipRRect] не сечёт птицу пополам.
/// 2. Верхняя плашка полноэкранного вида перекрывает ВСЮ ширину (бока
///    «допилены»), а не оставляет щели по краям.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 1));
    tmpDir = await Directory.systemTemp.createTemp('keramika_perf_test');
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
    // Настройку пишем в setUp, а НЕ в теле testWidgets: внутри FakeAsync
    // реальный файловый ввод-вывод не завершается и тест висит.
    await SettingsService.savePerfectionism(true);
    final svc = HabitService();
    await svc.debugClear();
    await svc.load();
    await svc.add(
      Habit(
        id: 'h1',
        name: 'Пить воду',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
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

  test('кромки стаи гаснут: птицы входят и уходят внутри окна', () {
    expect(perfFlockEdgeStops.first, 0.0);
    expect(perfFlockEdgeStops.last, 1.0);
    // Между кромками есть сплошной участок — птица не «тает» всю дорогу,
    // гаснет только у самого края.
    expect(perfFlockEdgeStops[1], lessThan(0.2));
    expect(perfFlockEdgeStops[2], greaterThan(0.8));
  });

  testWidgets('полоса перфекционизма рисует стаю на своей подложке', (
    tester,
  ) async {
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

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('perf_birds')), findsOneWidget);
  });

  testWidgets('верхняя плашка полноэкранного вида перекрывает всю ширину', (
    tester,
  ) async {
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

    // Открываем полноэкранный вид тапом по первой карточке полосы.
    // pumpAndSettle здесь НЕЛЬЗЯ: стая анимируется бесконечно (repeat) и
    // ожидание «всех кадров» никогда не закончится. Проходим переход
    // фиксированным отрезком — его длительность 280 мс.
    await tester.tap(find.byType(InkWell).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final bar = find.byKey(const ValueKey('perf_top_bar'));
    expect(bar, findsOneWidget);
    final size = tester.getSize(bar);
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(
      size.width,
      closeTo(screen.width, 0.5),
      reason: 'шапка обязана доходить до краёв, иначе по бокам щели',
    );
  });
}
