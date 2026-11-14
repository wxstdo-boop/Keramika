import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/screens/add_alarm_screen.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/timer_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/press_scale.dart';

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 12));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_alarm_reorder_test');
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

    final service = AlarmService();
    await service.load();
    for (final a in service.alarms.toList()) {
      await service.remove(a.id);
    }
    await service.add(
      Alarm(id: 'a1', time: const TimeOfDay(hour: 7, minute: 0)),
    );
    await service.add(
      Alarm(id: 'a2', time: const TimeOfDay(hour: 8, minute: 0)),
    );

    final timers = TimerService();
    await timers.load();
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

  test('AlarmService.reorder корректно перемещает элементы в конец и начало', () async {
    final service = AlarmService();
    await service.load();

    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2']);

    // Добавляем третий для проверки перестановок
    final a3 = Alarm(id: 'a3', time: const TimeOfDay(hour: 9, minute: 0));
    await service.add(a3);
    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

    // Перемещение первого элемента в самый конец (длина 3)
    await service.reorder(0, 3);
    expect(service.alarms.map((a) => a.id).toList(), ['a2', 'a3', 'a1']);

    // Перемещение последнего обратно на первое место
    await service.reorder(2, 0);
    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

    // Недопустимые индексы не ломают список
    await service.reorder(-1, 2);
    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

    await service.reorder(0, -1);
    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);

    // Перемещение в ту же позицию не меняет ничего
    await service.reorder(1, 1);
    expect(service.alarms.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);
  });

  testWidgets('в AddAlarmScreen PressScale оборачивает Card времени и вибрации', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: AddAlarmScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Находим PressScale, у которого внутри лежит Card
    final pressScalesWithCard = find.descendant(
      of: find.byType(PressScale),
      matching: find.byType(Card),
    );

    // Должно быть как минимум 2 таких виджета (плитка времени и вибрация)
    expect(
      pressScalesWithCard,
      findsAtLeastNWidgets(2),
      reason: 'PressScale должен оборачивать саму Card (время и вибрация)',
    );
  });

  testWidgets('в AlarmsScreen только первый будильник содержит кнопку теста', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    // Ровно один значок теста будильника
    final testBell = find.byIcon(Icons.notifications_active_outlined);
    expect(
      testBell,
      findsOneWidget,
      reason: 'Кнопка теста должна отображаться ровно на первом будильнике',
    );
  });
}
