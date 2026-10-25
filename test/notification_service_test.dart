import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
// Основной пакет плагина, а не `platform_interface`: класс
// `AndroidFlutterLocalNotificationsPlugin` экспортируется именно отсюда,
// а `FlutterLocalNotificationsPlatform` живёт в platform_interface, но
// реэкспортируется основным пакетом тоже.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/models/alarm.dart';
import 'package:keramika/models/wake_task.dart';
import 'package:keramika/services/notification_service.dart';
import 'package:keramika/services/prefs.dart';

/// Тесты NotificationService — слоя, который будит пользователя.
///
/// Главное, что здесь ломается незаметно: будильник может выглядеть
/// включённым в интерфейсе, но не звонить. Причины бывают тихими —
/// снятое право на уведомления, сбой канала, неинициализированный плагин.
/// Поэтому проверяем не «звонит ли», а то, что слой:
///  * не бросает исключения при сбоях (иначе роняет весь запуск);
///  * отменяет уведомления, которые поставил;
///  * уважает переключатель пользователя и сохраняет его в prefs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const schedulerChannel = MethodChannel('com.wetidom.keramika/alarm_scheduler');
  const fullscreenChannel = MethodChannel(
    'com.wetidom.keramika/fullscreen',
  );
  // Канал самого плагина уведомлений. В юнит-тестах плагин не
  // регистрируется (нет настоящего Android), а его платформа объявлена
  // `late` — без подстановки любое обращение к ней падает с
  // LateInitializationError ещё до вызова канала. Поэтому подменяем
  // платформу на Android-реализацию плагина и мокаем её канал: так
  // проверяется настоящий путь вызовов, а не подделка.
  const pluginChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );

  final nativeCalls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];

  void mockChannels({bool schedulerFails = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(schedulerChannel, (call) async {
          nativeCalls.add(call);
          if (schedulerFails) throw PlatformException(code: 'FAIL');
          switch (call.method) {
            case 'canScheduleExactAlarms':
            case 'isIgnoringBatteryOptimizations':
            case 'isAlarmClockApiAvailable':
              return true;
            case 'nextAlarmTime':
              return 0;
            default:
              return true;
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, (call) async => true);
  }

  setUp(() async {
    nativeCalls.clear();
    pluginCalls.clear();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    mockChannels();

    // Платформа плагина уведомлений: без неё любое обращение к
    // `resolvePlatformSpecificImplementation` падает с LateInitializationError
    // ещё до вызова канала.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();

    // Канал плагина: отвечает «успех» на любой вызов и запоминает их.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, (call) async {
          pluginCalls.add(call);
          switch (call.method) {
            case 'initialize':
              // Плагин ждёт `Future<bool>` от initialize: `null` здесь роняет
              // инициализацию с «type 'Null' is not a subtype of type
              // 'FutureOr<bool>'» ещё в setUp.
              return true;
            case 'areNotificationsEnabled':
              return true;
            case 'getNotificationAppLaunchDetails':
              return null;
            default:
              return null;
          }
        });

    final service = NotificationService();
    await service.init();
    // Синглтон живёт между тестами, а состояние переключателя — в его
    // полях. Возвращаем к «включено», чтобы тест не зависел от порядка.
    await service.setEnabled(true, requestPermission: false);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(schedulerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pluginChannel, null);
  });

  bool isAndroid() => defaultTargetPlatform == TargetPlatform.android;

  Alarm makeAlarm({
    int hour = 7,
    int minute = 30,
    String label = 'Будильник',
    List<int> repeatDays = const [],
    WakeUpTask taskType = WakeUpTask.none,
  }) {
    return Alarm(
      id: 'alarm-test-1',
      time: TimeOfDay(hour: hour, minute: minute),
      enabled: true,
      label: label,
      repeatDays: repeatDays,
      taskType: taskType,
    );
  }

  test('отмена будильника доходит до плагина уведомлений', () async {
    final service = NotificationService();

    await service.cancelAlarm('alarm-test-1');

    // Отмена по id идёт через плагин: `_plugin.cancel(id: ...)`.
    expect(
      pluginCalls.where((c) => c.method == 'cancel').isNotEmpty,
      isTrue,
      reason: 'Отмена будильника не дошла до плагина',
    );
  });

  test('отмена несуществующего будильника не бросает', () async {
    final service = NotificationService();

    // Отмена того, чего нет, — обычная ситуация (пользователь удалил
    // будильник, а уведомление осталось). Она не должна ронять приложение.
    await expectLater(service.cancelAlarm('missing-id'), completes);
  });

  test('сбой нативного канала не пробрасывается наружу', () async {
    mockChannels(schedulerFails: true);
    final service = NotificationService();

    // Любой вызов, касающийся нативного слоя, обязан пережить сбой.
    await expectLater(service.cancelAlarm('alarm-test-1'), completes);
    await expectLater(service.cancelAll(), completes);
  });

  test('выключенные уведомления отменяют всё, что было поставлено', () async {
    final service = NotificationService();
    await service.setEnabled(false, requestPermission: false);

    // После выключения будильников не должно остаться «зависших»
    // уведомлений, которые вдруг прозвонят посреди ночи.
    await service.cancelAll();

    expect(
      pluginCalls.where((c) => c.method == 'cancelAll').isNotEmpty,
      isTrue,
      reason: 'После выключения уведомлений ничего не отменено',
    );
  });

  test('переключатель уведомлений переживает перезапуск', () async {
    final service = NotificationService();
    expect(service.enabled, isTrue);

    await service.setEnabled(false, requestPermission: false);
    expect(service.enabled, isFalse);
    // Состояние лежит в prefs — после перезапуска приложения переключатель
    // должен остаться выключенным, а не включиться сам.
    expect(globalPrefs.getBool('notifications_enabled'), isFalse);

    await service.setEnabled(true, requestPermission: false);
    expect(service.enabled, isTrue);
    expect(globalPrefs.getBool('notifications_enabled'), isTrue);
  });

  test('повторяющийся будильник передаёт дни недели', () async {
    final service = NotificationService();
    final alarm = makeAlarm(repeatDays: const [1, 2, 3, 4, 5]);

    await expectLater(service.scheduleAlarm(alarm), completes);

    if (!isAndroid()) return;
    final schedule = nativeCalls
        .where((c) => c.method == 'scheduleAlarmClock')
        .toList();
    expect(schedule, isNotEmpty, reason: 'Будильник не поставлен нативно');
    final args = Map<Object?, Object?>.from(schedule.last.arguments as Map);
    expect(args['repeatDays'], '1,2,3,4,5');
    expect(args['payload'], 'alarm:alarm-test-1');
  });

  test('будильник с задачей пробуждения получает текст задачи', () async {
    final service = NotificationService();
    final alarm = makeAlarm(taskType: WakeUpTask.math);

    await expectLater(service.scheduleAlarm(alarm), completes);

    if (!isAndroid()) return;
    final schedule = nativeCalls
        .where((c) => c.method == 'scheduleAlarmClock')
        .toList();
    expect(schedule, isNotEmpty, reason: 'Будильник не поставлен нативно');
    final args = Map<Object?, Object?>.from(schedule.last.arguments as Map);
    expect(args['body'], contains('Задача'));
  });

  test('выключенный переключатель не даёт поставить будильник', () async {
    final service = NotificationService();
    await service.setEnabled(false, requestPermission: false);
    final before = nativeCalls.length;

    final ok = await service.scheduleAlarm(makeAlarm());

    // Будильник не должен ставиться в систему, пока пользователь выключил
    // уведомления: иначе он прозвонит ночью, когда всё выключено.
    expect(ok, isFalse);
    expect(
      nativeCalls
          .skip(before)
          .where((c) => c.method == 'scheduleAlarmClock')
          .isEmpty,
      isTrue,
      reason: 'Будильник поставлен, хотя уведомления выключены',
    );
  });
}
