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

import 'package:agysha/models/alarm.dart';
import 'package:agysha/models/wake_task.dart';
import 'package:agysha/services/notification_service.dart';
import 'package:agysha/services/prefs.dart';

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

  const schedulerChannel = MethodChannel('com.wetcorp.agysha/alarm_scheduler');
  const fullscreenChannel = MethodChannel(
    'com.wetcorp.agysha/fullscreen',
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
  // Канал будильника (MainActivity): stopAlarmSoundFor глушит звонок
  // удалённого/выключенного будильника.
  const payloadChannel = MethodChannel('com.wetcorp.agysha/alarm_payload');

  final nativeCalls = <MethodCall>[];
  final pluginCalls = <MethodCall>[];
  final payloadCalls = <MethodCall>[];

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(payloadChannel, (call) async {
          payloadCalls.add(call);
          return true;
        });
  }

  setUp(() async {
    nativeCalls.clear();
    pluginCalls.clear();
    payloadCalls.clear();
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(payloadChannel, null);
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

  test('отмена будильника глушит звонок, если он звонит сейчас', () async {
    final service = NotificationService();

    await service.cancelAlarm('alarm-test-1');

    if (!isAndroid()) {
      // Вне Android нативный сервис звонка не запускается.
      expect(payloadCalls, isEmpty);
      return;
    }
    // Отмена AlarmManager и уведомления звонок не гасит — его крутит
    // AlarmForegroundService. Без stopAlarmSoundFor будильник продолжал бы
    // звенеть до 5-минутного таймаута («удалил, а он всё равно звенит»).
    final stop = payloadCalls.where((c) => c.method == 'stopAlarmSoundFor');
    expect(
      stop.isNotEmpty,
      isTrue,
      reason: 'отмена будильника должна глушить нативный звонок',
    );
    expect(
      stop.first.arguments,
      {'id': 'alarm-test-1'.hashCode},
      reason: 'глушится звонок именно этого будильника',
    );
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

  test('одноразовый будильник в запасном пути не повторяется ежедневно', () async {
    // Нативный AlarmManager недоступен → идём запасным путём плагина
    // (zonedSchedule). Именно здесь одноразовый будильник раньше получал
    // повтор «каждый день» и превращался в ежедневный.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(schedulerChannel, (call) async {
          nativeCalls.add(call);
          switch (call.method) {
            case 'isAlarmClockApiAvailable':
              return false;
            case 'canScheduleExactAlarms':
            case 'isIgnoringBatteryOptimizations':
              return true;
            case 'nextAlarmTime':
              return 0;
            default:
              return true;
          }
        });

    final service = NotificationService();
    await service.scheduleAlarm(makeAlarm(repeatDays: const []));

    if (!isAndroid()) return;
    final zoned = pluginCalls.where((c) => c.method == 'zonedSchedule').toList();
    expect(zoned, isNotEmpty, reason: 'Запасной путь не сработал');
    final args = Map<Object?, Object?>.from(zoned.first.arguments as Map);
    // Ключа повтора нет вовсе — будильник сработает ровно один раз.
    expect(args.containsKey('matchDateTimeComponents'), isFalse);
  });

  test('повторяющийся будильник в запасном пути повторяется по дням', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(schedulerChannel, (call) async {
          nativeCalls.add(call);
          switch (call.method) {
            case 'isAlarmClockApiAvailable':
              return false;
            case 'canScheduleExactAlarms':
            case 'isIgnoringBatteryOptimizations':
              return true;
            case 'nextAlarmTime':
              return 0;
            default:
              return true;
          }
        });

    final service = NotificationService();
    await service.scheduleAlarm(makeAlarm(repeatDays: const [1, 2, 3, 4, 5]));

    if (!isAndroid()) return;
    final zoned = pluginCalls.where((c) => c.method == 'zonedSchedule').toList();
    expect(zoned, isNotEmpty, reason: 'Запасной путь не сработал');
    final args = Map<Object?, Object?>.from(zoned.first.arguments as Map);
    // dayOfWeekAndTime — повтор по конкретным дням недели.
    expect(args['matchDateTimeComponents'], 1);
  });

  test('нативный путь гасит «хвост» запасного пути по тому же id', () async {
    // Если будильник когда-то был поставлен запасным путём (плагин), а потом
    // ставится нативно, старая запись в flutter_local_notifications должна
    // быть снята — иначе она прозвенит вместе с нативным («сработал дважды»).
    final service = NotificationService();
    await service.scheduleAlarm(makeAlarm());

    if (!isAndroid()) return;
    final cancels = pluginCalls.where((c) => c.method == 'cancel').toList();
    expect(
      cancels,
      isNotEmpty,
      reason: 'Нативная постановка не сняла запасную запись плагина',
    );
    final args = Map<Object?, Object?>.from(cancels.last.arguments as Map);
    expect(args['id'], 'alarm-test-1'.hashCode);
  });

  test('будильник ставится даже при выключенных уведомлениях', () async {
    final service = NotificationService();
    await service.setEnabled(false, requestPermission: false);
    final before = nativeCalls.length;

    final ok = await service.scheduleAlarm(makeAlarm());

    // РЕГРЕСС: раньше выключенный тумблер уведомлений (или снятое системой
    // разрешение после обновления APK) молча запрещал постановку будильника —
    // «включены, но не звонят». Звонок идёт через foreground-сервис по
    // AlarmManager и в уведомлениях не нуждается, поэтому будильник обязан
    // ставиться ВСЕГДА, а уведомление — лишь дополнительный слой.
    expect(ok, isTrue);
    expect(
      nativeCalls
          .skip(before)
          .where((c) => c.method == 'scheduleAlarmClock')
          .isNotEmpty,
      isTrue,
      reason: 'Будильник не поставлен, хотя звонок от уведомлений не зависит',
    );
  });
}
