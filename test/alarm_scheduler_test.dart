import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/services/alarm_scheduler.dart';

/// Тесты моста постановки будильников в Android (`AlarmManager`).
///
/// Почему это важно покрыть: постановка будильника — единственное место,
/// где приложение говорит системе «разбуди меня в 7:30». Ошибка здесь не
/// видна в интерфейсе: будильник выглядит включённым, а не звенит. Хуже
/// всего — молчаливая ошибка в передаче аргументов (потерянный `id`,
/// неверный `fireTimestamp` или забытый `payload`), при которой будильник
/// срабатывает не в то время или без задания.
///
/// Нативный слой подменяем мок-каналом: проверяем, что Dart отдаёт
/// правильные имена и значения, и что сбой канала не роняет приложение —
/// методы обязаны возвращать «не получилось», а не бросать.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wetcorp.agysha/alarm_scheduler');
  const fullscreenChannel = MethodChannel(
    'com.wetcorp.agysha/fullscreen',
  );

  final calls = <MethodCall>[];

  void mockChannel({Object? result = true, bool throwOnCall = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (throwOnCall) throw PlatformException(code: 'FAIL');
          return result;
        });
  }

  setUp(() {
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, null);
  });

  // На тестовой платформе (не Android) планировщик молча выходит. Чтобы
  // проверить передачу аргументов, включаем Android-ветку.
  bool isAndroid() => defaultTargetPlatform == TargetPlatform.android;

  test('передаёт в AlarmManager все аргументы будильника', () async {
    mockChannel();
    final fireTime = DateTime(2026, 10, 21, 7, 30);

    final ok = await AlarmScheduler.scheduleAlarmClock(
      id: 42,
      title: 'Будильник',
      body: 'Встать',
      channelId: 'alarm_channel',
      channelName: 'Будильники',
      soundName: 'default',
      vibrate: true,
      fireTime: fireTime,
      hour: 7,
      minute: 30,
      repeatDays: '1,2,3,4,5',
      payload: '{"alarmId":42}',
      fullscreen: true,
    );

    if (!isAndroid()) {
      // Вне Android планирование не выполняется — это осознанное поведение.
      expect(ok, isFalse);
      return;
    }

    expect(ok, isTrue);
    expect(calls, hasLength(1));
    final call = calls.single;
    expect(call.method, 'scheduleAlarmClock');

    final args = Map<Object?, Object?>.from(call.arguments as Map);
    expect(args['id'], 42);
    expect(args['title'], 'Будильник');
    expect(args['body'], 'Встать');
    expect(args['channelId'], 'alarm_channel');
    expect(args['channelName'], 'Будильники');
    expect(args['soundName'], 'default');
    expect(args['vibrate'], isTrue);
    expect(args['fireTimestamp'], fireTime.millisecondsSinceEpoch);
    expect(args['hour'], 7);
    expect(args['minute'], 30);
    expect(args['repeatDays'], '1,2,3,4,5');
    expect(args['payload'], '{"alarmId":42}');
    expect(args['fullscreen'], isTrue);
  });

  test('отмена будильника передаёт его id', () async {
    mockChannel();

    await AlarmScheduler.cancelAlarmClock(7);

    if (!isAndroid()) return;
    expect(calls, hasLength(1));
    expect(calls.single.method, 'cancelAlarmClock');
    final args = Map<Object?, Object?>.from(calls.single.arguments as Map);
    expect(args['id'], 7);
  });

  test('сбой канала не роняет приложение, а возвращает «не получилось»', () async {
    mockChannel(throwOnCall: true);

    // Ни один из методов не должен бросать: вызывающая сторона не готова
    // к исключению из планировщика, и падение здесь уронило бы весь запуск.
    expect(
      await AlarmScheduler.scheduleAlarmClock(
        id: 1,
        title: 't',
        body: 'b',
        channelId: 'c',
        channelName: 'n',
        soundName: 's',
        vibrate: false,
        fireTime: DateTime(2026, 10, 21, 7, 30),
        hour: 7,
        minute: 30,
      ),
      isFalse,
    );
    expect(await AlarmScheduler.cancelAlarmClock(1), isFalse);
    expect(await AlarmScheduler.nextAlarmTime(), 0);
    expect(await AlarmScheduler.isAvailable(), isFalse);
    expect(await AlarmScheduler.isIgnoringBatteryOptimizations(), isFalse);
  });

  test('nextAlarmTime отдаёт время ближайшего будильника', () async {
    mockChannel(result: 1790000000000);

    final next = await AlarmScheduler.nextAlarmTime();

    if (!isAndroid()) {
      expect(next, 0);
      return;
    }
    expect(next, 1790000000000);
    expect(calls.single.method, 'nextAlarmTime');
  });

  test('запрос полноэкранного права не блокирует планирование', () async {
    // Канал может отсутствовать (старый билд) — тогда метод обязан вернуть
    // true, иначе будильник вообще не запланируется.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, (call) async {
          throw PlatformException(code: 'NOT_REGISTERED');
        });

    expect(await AlarmScheduler.requestFullScreenIntent(), isTrue);
  });

  test('право на полноэкранные уведомления запрашивается отдельным каналом', () async {
    final fullscreenCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(fullscreenChannel, (call) async {
          fullscreenCalls.add(call);
          return true;
        });

    final granted = await AlarmScheduler.requestFullScreenIntent();

    if (!isAndroid()) {
      expect(granted, isTrue);
      return;
    }
    expect(granted, isTrue);
    expect(fullscreenCalls, hasLength(1));
    expect(fullscreenCalls.single.method, 'requestUseFullScreenIntent');
  });

  group('одноразовые будильники', () {
    test('consumeFiredOneShots читает список прозвеневших', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'consumeFiredOneShots') {
              return <int>[11, 22, 33];
            }
            return true;
          });

      final fired = await AlarmScheduler.consumeFiredOneShots();

      if (!isAndroid()) {
        expect(fired, isEmpty);
        return;
      }
      expect(fired, [11, 22, 33]);
      expect(calls.single.method, 'consumeFiredOneShots');
    });

    test('пустой список и сбой канала не роняют вызов', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
      expect(await AlarmScheduler.consumeFiredOneShots(), isEmpty);

      mockChannel(throwOnCall: true);
      expect(await AlarmScheduler.consumeFiredOneShots(), isEmpty);
    });
  });

  group('остановка звонка удалённого будильника', () {
    // Канал alarm_payload (MainActivity): stopAlarmSoundFor глушит
    // AlarmForegroundService, если звонит именно этот будильник.
    const payloadChannel = MethodChannel('com.wetcorp.agysha/alarm_payload');
    final payloadCalls = <MethodCall>[];

    setUp(() {
      payloadCalls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(payloadChannel, (call) async {
            payloadCalls.add(call);
            return true;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(payloadChannel, null);
    });

    test('stopRingingAlarm шлёт id удалённого будильника нативно', () async {
      await AlarmScheduler.stopRingingAlarm(4242);

      if (!isAndroid()) {
        // Вне Android мост молча выходит (нет нативного сервиса звонка).
        expect(payloadCalls, isEmpty);
        return;
      }
      expect(payloadCalls.single.method, 'stopAlarmSoundFor');
      expect(payloadCalls.single.arguments, {'id': 4242});
    });

    test('сбой канала не роняет вызов', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(payloadChannel, (call) async {
            throw PlatformException(code: 'FAIL');
          });
      await expectLater(AlarmScheduler.stopRingingAlarm(1), completes);
    });
  });
}
