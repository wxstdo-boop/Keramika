import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/models/alarm.dart';
import 'package:agysha/models/app_timer.dart';
import 'package:agysha/screens/alarms_screen.dart';
import 'package:agysha/services/alarm_service.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/timer_service.dart';

/// Регресс на «рывки автоскролла» в списке будильников.
///
/// Раньше весь раздел будильников был под ОДНИМ `ListenableBuilder`, который
/// слушал ещё и `TimerService`. Тот тикает раз в секунду и на каждом тике
/// зовёт `notifyListeners()` — значит весь `Scaffold` (вместе с
/// `ReorderableListView`) пересобирался ежесекундно, в том числе прямо во
/// время драга. Кадр пересборки совпадал с кадром автоскролла и читался как
/// рывок. Теперь список подписан только на `AlarmService`, а секция таймеров
/// обновляется своим `ListenableBuilder`.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_alarm_rebuild');
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

    final alarms = AlarmService();
    await alarms.load();
    for (final id in alarms.alarms.map((Alarm a) => a.id).toList()) {
      await alarms.remove(id);
    }
    await alarms.add(
      Alarm(
        id: 'a1',
        time: TimeOfDay(hour: 7, minute: 0),
        repeatDays: const [1, 2, 3],
      ),
    );
    await alarms.add(
      Alarm(
        id: 'a2',
        time: TimeOfDay(hour: 8, minute: 30),
        repeatDays: const [1, 2, 3],
      ),
    );

    // Всё файловое I/O (load/add) выполняем ЗДЕСЬ: внутри testWidgets
    // (FakeAsync) реальный I/O не завершается и тест зависает.
    final timers = TimerService();
    await timers.load();
    for (final t in timers.timers.toList()) {
      await timers.remove(t.id);
    }
    await timers.add(AppTimer(id: 't1', totalSeconds: 600));
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

  testWidgets('тик таймера не пересобирает список будильников', (
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

    expect(find.byType(ReorderableListView), findsOneWidget);

    // Экземпляр виджета, который отдаёт родительский билдер. Если билдер
    // раздела не перезапускается, экземпляр остаётся тем же (identical).
    final before = tester.widget(find.byType(ReorderableListView));

    // Запускаем таймер: он тикает раз в секунду и зовёт notifyListeners().
    TimerService().startTimer('t1');
    // Прогоняем >2 секунд кадров — минимум два тика таймера.
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Гасим тикер, иначе flutter_test ругается на «Timer is still pending».
    TimerService().pauseTimer('t1');

    final after = tester.widget(find.byType(ReorderableListView));
    expect(tester.takeException(), isNull);
    expect(
      identical(before, after),
      isTrue,
      reason: 'тик таймера пересобирает список будильников (рывки драга)',
    );
  });
}
