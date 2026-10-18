import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/alarm.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/screens/home_screen.dart';
import 'package:keramika/services/alarm_service.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/task_service.dart';
import 'package:keramika/widgets/animated_fab_row.dart';
import 'package:keramika/widgets/section_pill.dart';

/// Таблетка разделов при переезде между экранами сворачивается и
/// возвращается СИНХРОННО с разделами, а не «висит» высотой уехавшего
/// раздела и не мигает скачком на финише.
///
/// Как было: высота таблетки жёстко переставлялась на высоту целевого
/// раздела — при пересечении половины пути (раздел становился активным)
/// или на отпускании пальца. Посреди свайпа таблетка оставалась «мёртвым
/// грузом» чужой высоты, а на финише прыгала. Теперь высоту ведёт
/// интерполяция по ДРОБНОЙ странице карусели: насколько разделы проехали —
/// настолько таблетка и свернулась.
///
/// Проверяем инварианты, а не абсолютную геометрию: плавность шага за кадр,
/// монотонность и то, что в середине переезда высота действительно
/// промежуточная (значит движением управляет интерполяция, а не поздняя
/// жёсткая запись).
void main() {
  late Directory tmpDir;

  const double fullPill = 64;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    sectionPillSnapByPage.clear();
    sectionPillSnapTarget.value = null;
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues(<String, Object>{
      'welcome_dismissed': true,
      'popup_warning_shown': true,
      'last_home_tab': 0,
    });
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_pill_transition');
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
    // Данные — вне FakeAsync-зоны testWidgets.
    await AlarmService().load();
    for (final a in AlarmService().alarms.toList()) {
      await AlarmService().remove(a.id);
    }
    for (var i = 0; i < 40; i++) {
      await AlarmService().add(
        Alarm(
          id: 'a$i',
          time: TimeOfDay(hour: 6, minute: i % 60),
        ),
      );
    }
    await HabitService().load();
    for (final h in HabitService().habits.toList()) {
      await HabitService().remove(h.id);
    }
    for (var i = 0; i < 20; i++) {
      await HabitService().add(
        Habit(
          id: 'h$i',
          name: 'Привычка $i',
          iconCodePoint: 57690,
          activeDays: const [1, 2, 3, 4, 5, 6, 7],
        ),
      );
    }
    await TaskService().load();
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

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Видимая (не срезанная) высота таблетки. 0 — таблетка срезана целиком
  /// (tEased <= 0.01 → SizedBox.shrink, в дереве её нет).
  double pillHeight(WidgetTester tester) {
    final clips = find
        .ancestor(of: find.byType(SectionPill), matching: find.byType(ClipRect))
        .evaluate()
        .toList();
    if (clips.isEmpty) return 0;
    final box = clips.first.renderObject as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    return box.size.height;
  }

  /// Прокрутить активный раздел вниз (часть протяжки съедает touch slop,
  /// поэтому офсет читаем из общего состояния, а не задаём константой).
  Future<double> scrollActive(WidgetTester tester, double dy) async {
    await tester.drag(
      find.byType(HomeScreen),
      Offset(0, dy),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    return sectionScrollOffset.value;
  }

  /// Свайп по самому PageView: выше карточек (иначе горизонтальный драг
  /// забирает SwipeToDelete карточки) и вне капсулы таблетки.
  Future<void> swipePage(WidgetTester tester, {required bool left}) async {
    final g = await tester.startGesture(
      left ? const Offset(385, 62) : const Offset(26, 62),
    );
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 12; i++) {
      await g.moveBy(Offset(left ? -30 : 30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
  }

  /// Высота таблетки по кадрам.
  Future<List<double>> record(WidgetTester tester, int frames) async {
    final out = <double>[];
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      out.add(pillHeight(tester));
    }
    return out;
  }

  /// Плавность ряда высот: шаг за кадр ограничен, движение — почти
  /// монотонное (ни одного кадра против общего направления больше полупикселя).
  void expectSmooth(List<double> frames, double direction, String tag) {
    expect(frames, isNotEmpty, reason: tag);
    var maxStep = 0.0;
    for (var i = 1; i < frames.length; i++) {
      final step = frames[i] - frames[i - 1];
      if (step.abs() > maxStep) maxStep = step.abs();
      expect(
        step * direction,
        greaterThan(-0.6),
        reason: '$tag: откат назад в ряду высот: $frames',
      );
    }
    expect(maxStep, lessThan(8.0), reason: '$tag: скачок за кадр: $frames');
  }

  /// Сколько кадров высота была ПРОМЕЖУТОЧНОЙ между состояниями разделов:
  /// именно это доказывает, что переезд ведёт интерполяция, а не поздняя
  /// жёсткая запись на половине пути/на финише.
  int intermediateFrames(List<double> frames, double a, double b) {
    final lo = (a < b ? a : b) + 0.5;
    final hi = (a > b ? a : b) - 0.5;
    return frames.where((h) => h > lo && h < hi).length;
  }

  testWidgets('свайп со свёрнутой таблетки: возвращается вместе с разделами', (
    tester,
  ) async {
    await boot(tester);
    expect(pillHeight(tester), fullPill);

    final source = await scrollActive(tester, -50);
    expect(source, greaterThan(0));
    expect(source, lessThan(fullPill));
    final sourcePill = pillHeight(tester);
    expect(
      sourcePill,
      closeTo(source > 28 ? 0 : fullPill - source, 0.6),
      reason: 'после остановки вертикального скролла таблетка доводится к краю',
    );

    final g = await tester.startGesture(const Offset(385, 62));
    await tester.pump(const Duration(milliseconds: 40));
    final during = <double>[];
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      during.add(pillHeight(tester));
    }
    await g.up();
    final settle = await record(tester, 40);

    expect(
      intermediateFrames(during, sourcePill, fullPill),
      greaterThanOrEqualTo(4),
      reason:
          'таблетка должна разворачиваться ПО ХОДУ свайпа, а не ждать '
          'финиша на старой высоте: $during',
    );
    expectSmooth(during, 1, 'свайп');
    expectSmooth(settle, 1, 'доводка');
    expect(sectionCurrentIndex.value, 1);
    expect(
      pillHeight(tester),
      closeTo(fullPill, 0.6),
      reason: 'на верхнем разделе таблетка видна целиком',
    );
  });

  testWidgets('свайп на свёрнутый экран: сворачивается вместе с разделами', (
    tester,
  ) async {
    await boot(tester);

    // Готовим второй раздел (привычки) прокрученным.
    await swipePage(tester, left: true);
    expect(sectionCurrentIndex.value, 1);
    final targetScroll = await scrollActive(tester, -50);
    expect(targetScroll, greaterThan(0));
    expect(targetScroll, lessThan(fullPill - 4));
    final targetPill = pillHeight(tester);
    expect(
      targetPill,
      closeTo(targetScroll > 28 ? 0 : fullPill - targetScroll, 0.6),
    );

    // Возвращаемся на первый раздел — таблетка разворачивается обратно.
    await swipePage(tester, left: false);
    expect(sectionCurrentIndex.value, 0);
    expect(pillHeight(tester), closeTo(fullPill, 0.6));

    // Свайп обратно на прокрученный раздел: таблетка должна свернуться
    // ПО ХОДУ переезда, а не пропасть скачком на половине пути.
    final g = await tester.startGesture(const Offset(385, 62));
    await tester.pump(const Duration(milliseconds: 40));
    final during = <double>[];
    for (var i = 0; i < 12; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      during.add(pillHeight(tester));
    }
    await g.up();
    final settle = await record(tester, 40);

    expect(
      intermediateFrames(during, fullPill, targetPill),
      greaterThanOrEqualTo(4),
      reason:
          'таблетка должна сворачиваться постепенно, без скачка на '
          'половине пути: $during',
    );
    expectSmooth(during, -1, 'свайп');
    expectSmooth(settle, -1, 'доводка');
    expect(
      pillHeight(tester),
      closeTo(targetPill, 0.6),
      reason: 'на прокрученном разделе таблетка срезана по его офсету',
    );
  });

  testWidgets('тап по разделу: таблетка разворачивается по ходу полёта', (
    tester,
  ) async {
    await boot(tester);
    await swipePage(tester, left: true);
    // Небольшая прокрутка: таблетку можно тапнуть, пока видна её
    // БОЛЬШАЯ половина (при tEased < 0.5 её накрывает IgnorePointer).
    final source = await scrollActive(tester, -35);
    expect(sectionCurrentIndex.value, 1);
    expect(source, greaterThan(0));
    expect(
      source,
      lessThan(kSectionPillSlotHeight * 0.5),
      reason: 'прокрутили слишком много — таблетка перестаёт принимать тапы',
    );
    final sourcePill = pillHeight(tester);
    expect(sourcePill, closeTo(fullPill, 0.6));

    // Тап по «Будильникам» (первый значок): полёт пружиной на верхний раздел.
    // Целимся в ЦЕНТР ВИДИМОЙ части: нижний край капсулы срезан клипом,
    // и туда тап физически не попадает.
    // Target the actual visible icon: the outer SectionPill includes the
    // centered side gutters, so deriving a tab hit point from its full rect
    // tapped outside the capsule on narrow devices.
    await tester.tap(find.byIcon(sectionIcons.first).first);
    final flight = await record(tester, 60);

    expect(sectionCurrentIndex.value, 0);
    if ((fullPill - sourcePill).abs() > 0.6) {
      expect(
        intermediateFrames(flight, sourcePill, fullPill),
        greaterThan(3),
        reason: 'разворот должен идти кадрами полёта, а не скачком: $flight',
      );
    }
    expect(pillHeight(tester), closeTo(fullPill, 0.6));
  });
}
