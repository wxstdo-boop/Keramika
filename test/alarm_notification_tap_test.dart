import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/screens/wake_task_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';

/// Регресс: тап по уведомлению будильника, когда приложение УЖЕ запущено,
/// обязан открыть экран задачи (полноэкранный звонок).
///
/// Раньше это молча не работало: канал `alarm_payload` был `late final` и
/// присваивался в `initChannels()`, которую никто не вызывал. Первое же
/// `setMethodCallHandler` в `_startApp()` падало с LateInitializationError,
/// обработчик `onNewAlarmPayload` не вставал — и тап по уведомлению не
/// открывал WakeTaskScreen. Здесь мы монтируем приложение (как при живом
/// запуске), шлём нативный payload `onNewAlarmPayload` и проверяем, что
/// экран задачи действительно появился.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const payloadChannel = MethodChannel('com.wetcorp.agysha/alarm_payload');

  setUp(() async {
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    // path_provider: документы приложения пишем в /tmp (реальная ФС —
    // вызывающий тест оборачивает работу в tester.runAsync).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getApplicationDocumentsDirectory' ? '/tmp' : null,
        );
    // Нативный планировщик отвечает «ок».
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wetcorp.agysha/alarm_scheduler'),
          (call) async => true,
        );
    await AlarmService().load();
    for (final a in AlarmService().alarms.toList()) {
      await AlarmService().remove(a.id);
    }
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(payloadChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.wetcorp.agysha/alarm_scheduler'),
          null,
        );
  });

  testWidgets('onNewAlarmPayload открывает экран задачи', (tester) async {
    const alarmId = 'alarm-tap-1';
    // Сидим будильник ДО монтирования. Реальный файловый I/O здесь нельзя:
    // тело testWidgets крутится в fake-async зоне (см. AGENTS.md), поэтому
    // запись делаем через runAsync.
    await tester.runAsync(() async {
      await AlarmService().load();
      await AlarmService().add(
        Alarm(id: alarmId, time: const TimeOfDay(hour: 7, minute: 30)),
      );
    });

    // Монтируем приложение: initState вешает обработчик канала.
    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'en'));
    await tester.pump();

    // Нативная сторона шлёт payload (onNewIntent при живом приложении).
    // runAsync нужен, потому что обработчик читает будильники с диска —
    // реальный I/O в fake-async зоне не завершается. `tester.pump` внутри
    // runAsync запрещён (дедлок), поэтому здесь только ждём реальное время,
    // а кадры прокручиваем СНАРУЖИ.
    await tester.runAsync(() async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.wetcorp.agysha/alarm_payload',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onNewAlarmPayload', 'alarm:$alarmId'),
            ),
            (_) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      find.byType(WakeTaskScreen),
      findsOneWidget,
      reason: 'тап по уведомлению будильника должен открыть экран задачи',
    );
  });

  testWidgets('payload неизвестного будильника не открывает экран', (
    tester,
  ) async {
    await tester.pumpWidget(const AgyshaApp(initialLanguageCode: 'en'));
    await tester.pump();

    await tester.runAsync(() async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'com.wetcorp.agysha/alarm_payload',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('onNewAlarmPayload', 'alarm:no-such-alarm'),
            ),
            (_) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(WakeTaskScreen), findsNothing);
  });
}
