// Генератор скриншотов для витрины (README / docs).
//
// Зачем отдельный прогон, а не ручной `adb screencap`: снимки должны быть
// воспроизводимы и без личных данных — один и тот же набор демо-записей,
// одна тема, один размер. Скрипт монтирует РЕАЛЬНЫЕ экраны приложения в
// настоящей теме (lib/theme/app_theme.dart), поэтому витрина не расходится
// с видом приложения.
//
// Запуск (нужен Flutter SDK и настоящие шрифты — см. AGENTS.md):
//   flutter test tool/screenshots/render_screenshots.dart
// PNG кладутся в docs/screenshots/.
//
// Файл лежит вне test/, поэтому обычный `flutter test` его не подхватывает.
//
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/alarm.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/models/task.dart';
import 'package:keramika/models/wake_task.dart';
import 'package:keramika/screens/home_screen.dart';
import 'package:keramika/screens/stats_screen.dart';
import 'package:keramika/services/alarm_service.dart';
import 'package:keramika/services/completion_log_service.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/task_service.dart';
import 'package:keramika/theme/app_theme.dart';

/// Демо-набор: осмысленные русские данные, без личных записей.
Future<void> _seed() async {
  final alarms = AlarmService();
  for (final a in alarms.alarms.toList()) {
    await alarms.remove(a.id);
  }
  await alarms.add(
    Alarm(
      id: 'demo1',
      time: const TimeOfDay(hour: 6, minute: 30),
      label: 'Утренний подъём',
      repeatDays: const [1, 2, 3, 4, 5],
      taskType: WakeUpTask.math,
    ),
  );
  await alarms.add(
    Alarm(
      id: 'demo2',
      time: const TimeOfDay(hour: 7, minute: 0),
      label: 'Суббота — пробежка',
      repeatDays: const [6],
      enabled: false,
    ),
  );
  await alarms.add(
    Alarm(
      id: 'demo3',
      time: const TimeOfDay(hour: 22, minute: 45),
      label: 'Отбой',
      repeatDays: const [0, 1, 2, 3, 4, 5, 6],
    ),
  );

  final habits = HabitService();
  for (final h in habits.habits.toList()) {
    await habits.remove(h.id);
  }
  const demoHabits = <List<Object>>[
    ['Чтение 20 минут', 14, 57856],
    ['Зарядка', 9, 58611],
    ['Стакан воды утром', 32, 57442],
    ['Дневник', 5, 57758],
    ['Прогулка 8000 шагов', 21, 58378],
  ];
  for (var i = 0; i < demoHabits.length; i++) {
    final d = demoHabits[i];
    await habits.add(
      Habit(
        id: 'demo-h$i',
        name: d[0] as String,
        streak: d[1] as int,
        iconCodePoint: d[2] as int,
        doneToday: i < 3,
        activeDays: const [0, 1, 2, 3, 4, 5, 6],
        pinned: i == 0,
      ),
    );
  }

  final tasks = TaskService();
  for (final t in tasks.tasks.toList()) {
    await tasks.remove(t.id);
  }
  await tasks.add(
    Task(
      id: 'demo-t1',
      title: 'Оплатить интернет',
      priority: 2,
      dueAt: DateTime.now(),
      iconCodePoint: 58830,
    ),
  );
  await tasks.add(
    Task(
      id: 'demo-t2',
      title: 'Купить продукты на неделю',
      priority: 1,
      category: 'Дом',
      iconCodePoint: 57413,
    ),
  );
  await tasks.add(
    Task(
      id: 'demo-t3',
      title: 'Позвонить в сервис',
      done: true,
      priority: 0,
      iconCodePoint: 57536,
    ),
  );
  await tasks.add(
    Task(
      id: 'demo-t4',
      title: 'Забрать посылку',
      priority: 0,
      estimateMinutes: 30,
      iconCodePoint: 57889,
    ),
  );
}

Future<void> _loadFonts() async {
  const robotoRoot =
      '/home/openhands/.pub-cache/hosted/pub.dev/shared_preferences-2.5.6/extension/devtools/build/assets/packages/devtools_app_shared/fonts/Roboto';
  const dejavuRoot = '/usr/share/fonts/truetype/dejavu';
  final useRoboto = Directory(robotoRoot).existsSync();
  final regular = useRoboto
      ? '$robotoRoot/Roboto-Regular.ttf'
      : '$dejavuRoot/DejaVuSans.ttf';
  final bold = useRoboto
      ? '$robotoRoot/Roboto-Bold.ttf'
      : '$dejavuRoot/DejaVuSans-Bold.ttf';

  // Один и тот же набор под несколькими именами: обычная тема берёт
  // системный Roboto, а WideDashController — 'RobotoDash'.
  for (final family in const ['Roboto', 'RobotoDash']) {
    final loader = FontLoader(family)
      ..addFont(
        File(regular).readAsBytes().then((b) => ByteData.view(b.buffer)),
      )
      ..addFont(File(bold).readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
  }
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'welcome_dismissed': true,
      'popup_warning_shown': true,
      'last_home_tab': 0,
    });
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_shots');
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
    await AlarmService().load();
    await HabitService().load();
    await TaskService().load();
    await CompletionLogService().load();
    await _seed();
  });

  tearDown(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> render(WidgetTester tester, String name, Widget child) async {
    final key = GlobalKey();
    // Точная светлая тема приложения по умолчанию (lib/main.dart), а не
    // fromSeed: витрина обязана совпадать с тем, что видит пользователь.
    const scheme = ColorScheme.light(
      primary: Color(0xFF6750A4),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFEADDFF),
      onPrimaryContainer: Color(0xFF21005D),
      secondary: Color(0xFF625B71),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE8DEF8),
      onSecondaryContainer: Color(0xFF1D192B),
      surface: Color(0xFFFEF7FF),
      onSurface: Color(0xFF1D1B20),
      onSurfaceVariant: Color(0xFF49454F),
      outline: Color(0xFF79747E),
      outlineVariant: Color(0xFFCAC4D0),
      surfaceContainerHighest: Color(0xFFE7E0EC),
    );
    final theme = buildKeramikaTheme(
      scheme,
      isDark: false,
      isGrokStyle: false,
    );
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: RepaintBoundary(key: key, child: child),
        ),
      ),
    );
    // Дискретные кадры вместо pumpAndSettle: в приложении есть вечные петли,
    // pumpAndSettle на них зависает.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));

    late final ui.Image image;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      image = await boundary.toImage(pixelRatio: 3.0);
    });
    final bytes = await tester.runAsync(() async {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('docs/screenshots/$name.png').writeAsBytesSync(bytes!);
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  // HomeScreen стартует в разделе из 'last_home_tab', поэтому индекс
  // ставим в настройках, а не в sectionCurrentIndex.
  testWidgets('будильники', (tester) async {
    await tester.runAsync(_loadFonts);
    phone(tester);
    await globalPrefs.setInt('last_home_tab', 0);
    await render(tester, 'alarms', const HomeScreen());
  });

  testWidgets('привычки', (tester) async {
    await tester.runAsync(_loadFonts);
    phone(tester);
    await globalPrefs.setInt('last_home_tab', 1);
    await render(tester, 'habits', const HomeScreen());
  });

  testWidgets('задачи', (tester) async {
    await tester.runAsync(_loadFonts);
    phone(tester);
    await globalPrefs.setInt('last_home_tab', 2);
    await render(tester, 'tasks', const HomeScreen());
  });

  testWidgets('статистика', (tester) async {
    await tester.runAsync(_loadFonts);
    phone(tester);
    await render(tester, 'stats', const RealityCheckStatsScreen());
  });
}
