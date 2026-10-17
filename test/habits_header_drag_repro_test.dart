import 'dart:io';

import 'package:flutter/gestures.dart';
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

/// Воспроизведение наблюдения владельца: «карточки улетают, если начать
/// long-press-drag с ЗАГОЛОВКА секции (Полезные / Вредные)».
///
/// Тест ничего не чинит: он
///   1) рендерит HabitsScreen с 2 полезными + 2 вредными привычками
///      (режим секций включён) и проверяет finder-ами, что заголовки
///      и карточки реально отрисованы,
///   2) крутит настоящий long-press-drag из центра Text заголовка,
///   3) фиксирует порядок до/после (вердикт: стартует ли drag),
///   4) печатает геометрию: hit-боксы drag-ручек и расстояния от них
///      до полос заголовков — в десктопном окне 800x600 и в телефоне
///      411x891 с масштабированным шрифтом (MIUI).
void main() {
  late Directory tmpDir;

  Future<void> seed() async {
    final svc = HabitService();
    // HabitService — синглтон + то же хранилище на весь процесс теста:
    // без зачистки каждая следующая testWidgets-кейс догружал бы те же id
    // повторно (дубли ValueKey в списке → сыпятся assertion'ы семантики).
    // debugClear() тут не годится: он сбрасывает и флаг _loaded, а
    // HabitsScreen без него висит на заглушке «loading» (load() из initState
    // внутри FakeAsync-зоны не завершается — реальный файловый I/O), т.е.
    // список вообще не рендерится. Поэтому чистим remove()-ом ПОСЛЕ load().
    await svc.load();
    for (final id in svc.habits.map((Habit h) => h.id).toList()) {
      await svc.remove(id);
    }
    await svc.add(
      Habit(
        id: 'g1',
        name: 'Пить воду',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
    );
    await svc.add(
      Habit(
        id: 'g2',
        name: 'Зарядка',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
      ),
    );
    await svc.add(
      Habit(
        id: 'b1',
        name: 'Не грызть ногти',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        type: 'bad',
      ),
    );
    await svc.add(
      Habit(
        id: 'b2',
        name: 'Не пить кофе',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        type: 'bad',
      ),
    );
  }

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_header_drag');
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
    // Сидирование вне FakeAsync-зоны testWidgets (иначе реальный файловый
    // I/O сервисов зависает навсегда).
    await seed();
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

  /// Телефон 411x891 логических px + системный масштаб шрифта 1.15 (MIUI),
  /// чтобы геометрия была близка к реальной, а не к окну 800x600.
  Future<void> boot(
    WidgetTester tester, {
    Size? phoneSize,
    double textScale = 1.0,
  }) async {
    if (phoneSize != null) {
      tester.view.physicalSize = phoneSize * 3;
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: const Scaffold(body: HabitsScreen()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Глобальный Rect виджета (в координатах тестового окна).
  Rect globalRect(WidgetTester tester, Finder finder) {
    final box = tester.renderObject<RenderBox>(finder);
    return box.localToGlobal(Offset.zero) & box.size;
  }

  List<String> orderNow() =>
      HabitService().habits.map((Habit h) => h.id).toList();

  /// Hit-боксы drag-ручек (Listener у ReorderableDelayedDragStartListener)
  /// в порядке следования в списке.
  List<Rect> handlesOf(WidgetTester tester) {
    return tester
        .renderObjectList<RenderBox>(
          find.byType(ReorderableDelayedDragStartListener),
        )
        .map((RenderBox b) => b.localToGlobal(Offset.zero) & b.size)
        .toList();
  }

  /// Хит-тест произвольной точки: цепочка render-объектов, drag-ручки
  /// помечены их индексом в списке.
  String probe(WidgetTester tester, Offset at) {
    final result = tester.hitTestOnBinding(at);
    final boxes = tester
        .renderObjectList<RenderBox>(
          find.byType(ReorderableDelayedDragStartListener),
        )
        .toList();
    final names = <String>[];
    for (final HitTestEntry entry in result.path) {
      final target = entry.target;
      var idx = -1;
      for (var i = 0; i < boxes.length; i++) {
        if (identical(boxes[i], target)) idx = i;
      }
      names.add(idx >= 0 ? 'DRAG_HANDLE[$idx]' : '${target.runtimeType}');
    }
    return names.join(' < ');
  }

  int? handleIndexAt(List<Rect> handles, Offset p) {
    for (var i = 0; i < handles.length; i++) {
      if (handles[i].contains(p)) return i;
    }
    return null;
  }

  /// Печатает расстояние от полос заголовков до ближайших drag-ручек.
  void reportGeometry(WidgetTester tester, String tag) {
    final labelGood = globalRect(tester, find.text('Полезные'));
    final labelBad = globalRect(tester, find.text('Вредные'));
    final bandGood = globalRect(
      tester,
      find
          .ancestor(
            of: find.text('Полезные'),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final bandBad = globalRect(
      tester,
      find
          .ancestor(
            of: find.text('Вредные'),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final handles = handlesOf(tester);
    final cards = <String, Rect>{};
    for (final id in ['g1', 'g2', 'b1', 'b2']) {
      cards[id] = globalRect(tester, find.byKey(ValueKey('card_$id')));
    }
    debugPrint(
      '=== $tag (окно ${tester.view.physicalSize.width / tester.view.devicePixelRatio}x'
      '${tester.view.physicalSize.height / tester.view.devicePixelRatio} '
      'dpr=${tester.view.devicePixelRatio}) ===',
    );
    debugPrint('  label Полезные rect=$labelGood');
    debugPrint('  label Вредные   rect=$labelBad');
    debugPrint('  band  Полезные rect=$bandGood');
    debugPrint('  band  Вредные   rect=$bandBad');
    cards.forEach(
      (String k, Rect v) => debugPrint('  card $k rect=$v h=${v.height}'),
    );
    for (var i = 0; i < handles.length; i++) {
      debugPrint('  handle[$i] rect=${handles[i]} center=${handles[i].center}');
    }
    // Каждому заголовку — ближайшая ручка сверху и снизу + перекрытие по X.
    for (final h in <List<Rect>>[
      [labelBad, bandBad],
      [labelGood, bandGood],
    ]) {
      final label = h[0];
      final band = h[1];
      for (var i = 0; i < handles.length; i++) {
        final hr = handles[i];
        final above = hr.bottom <= band.top;
        final below = hr.top >= band.bottom;
        if (!above && !below) {
          debugPrint(
            '  ${label == labelBad ? "Вредные" : "Полезные"}: handle[$i] '
            'ПЕРЕКРЫВАЕТ полосу заголовка rect=$hr',
          );
          continue;
        }
        final gap = above ? band.top - hr.bottom : hr.top - band.bottom;
        final gapLabel = above ? label.top - hr.bottom : hr.top - label.bottom;
        final xOverlap = (hr.right < label.left || hr.left > label.right)
            ? 0.0
            : (hr.right < label.right ? hr.right : label.right) -
                  (hr.left > label.left ? hr.left : label.left);
        debugPrint(
          '  ${label == labelBad ? "Вредные" : "Полезные"}: handle[$i] '
          '${above ? "СВЕРХУ" : "СНИЗУ"} полосы заголовка: '
          'gapToBand=${gap.toStringAsFixed(1)} gapToLabel=${gapLabel.toStringAsFixed(1)} '
          'xOverlap=${xOverlap.toStringAsFixed(1)} (label x ${label.left}..${label.right}, '
          'handle x ${hr.left}..${hr.right})',
        );
      }
    }
  }

  testWidgets('A. заголовки и карточки отрисованы + геометрия', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    debugPrint('takeException: ${tester.takeException()}');

    // Имена привычек рисуются НЕ Text-ом, а RichText внутри
    // AnimatedStrikeText → обычный find.text их не видит (именно поэтому
    // падает reorder_list_test.dart:86).
    debugPrint(
      'find.text(Пить воду) = ${find.text("Пить воду").evaluate().length}; '
      'findRichText = '
      '${find.text("Пить воду", findRichText: true).evaluate().length}',
    );

    expect(find.text('Полезные'), findsOneWidget);
    expect(find.text('Вредные'), findsOneWidget);
    for (final n in [
      'Пить воду',
      'Зарядка',
      'Не грызть ногти',
      'Не пить кофе',
    ]) {
      expect(find.text(n, findRichText: true), findsOneWidget, reason: n);
    }
    expect(find.byType(ReorderableDelayedDragStartListener), findsNWidgets(4));
    reportGeometry(tester, 'GEOMETRY desktop');
  });

  testWidgets('B. жест из центра заголовка Вредные — вердикт', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    final before = orderNow();
    final label = globalRect(tester, find.text('Вредные'));
    debugPrint('B ORDER BEFORE: $before');
    debugPrint('B label rect=$label center=${label.center}');
    debugPrint('B hit-test @ center: ${probe(tester, label.center)}');

    await dragFrom(tester, label.center, dy: -120);

    final after = orderNow();
    debugPrint('B ORDER AFTER: $after');
    debugPrint('B REORDERED(bad header): ${before.join() != after.join()}');
    debugPrint('B takeException: ${tester.takeException()}');
  });

  testWidgets('C. жест из центра заголовка Полезные — вердикт', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    final before = orderNow();
    final label = globalRect(tester, find.text('Полезные'));
    debugPrint('C ORDER BEFORE: $before');
    debugPrint('C label rect=$label center=${label.center}');
    debugPrint('C hit-test @ center: ${probe(tester, label.center)}');

    await dragFrom(tester, label.center, dy: -120);

    final after = orderNow();
    debugPrint('C ORDER AFTER: $after');
    debugPrint('C REORDERED(good header): ${before.join() != after.join()}');
    debugPrint('C takeException: ${tester.takeException()}');
  });

  testWidgets('D. контроль: тот же жест с drag-ручки переставляет', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    final before = orderNow();
    final handles = handlesOf(tester);
    debugPrint('D ORDER BEFORE: $before');
    // g1 (handle[0]) тащим ВНИЗ на 80px — внутри своей секции.
    await dragFrom(tester, handles[0].center, dy: 80);
    final after = orderNow();
    debugPrint('D ORDER AFTER: $after');
    debugPrint('D REORDERED(handle): ${before.join() != after.join()}');
  });

  testWidgets('E. mis-aim: точка у самой полосы заголовка Вредные', (
    WidgetTester tester,
  ) async {
    await boot(tester);
    final label = globalRect(tester, find.text('Вредные'));
    final band = globalRect(
      tester,
      find
          .ancestor(
            of: find.text('Вредные'),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final handles = handlesOf(tester);
    final before = orderNow();
    debugPrint('E ORDER BEFORE: $before');
    debugPrint('E label=$label band=$band handles=$handles');

    // Вертикальный разрез вдоль x=36 (внутри подписи и внутри ручек).
    for (final dy in [-8.0, 0.0, 8.0, 16.0, 24.0, 32.0, 40.0, 48.0]) {
      for (final base in ['band', 'label']) {
        final top = base == 'band' ? band.top : label.top;
        final p = Offset(36, top - dy);
        debugPrint(
          'E probe $base-$dy p=$p rectHit='
          '${handleIndexAt(handles, p) ?? "none"} '
          'handleInPath=${probe(tester, p).contains("DRAG_HANDLE")}',
        );
      }
    }

    // Реальный жест: прицел в заголовок, но на 40px выше (палец «заехал»
    // на карточку выше) — это hit-box ручки g2.
    final g2Handle = handles[1];
    final miss = Offset(g2Handle.center.dx, g2Handle.center.dy);
    debugPrint(
      'E mis-aim point=$miss '
      '(на ${(label.top - g2Handle.bottom).toStringAsFixed(1)}px выше подписи)',
    );
    final before2 = orderNow();
    await dragFrom(tester, miss, dy: -80);
    final after2 = orderNow();
    debugPrint('E ORDER AFTER mis-aim: $after2');
    debugPrint('E REORDERED(mis-aim): ${before2.join() != after2.join()}');
    debugPrint('E takeException: ${tester.takeException()}');
  });

  testWidgets('F. телефон 411x891 + масштаб шрифта 1.15', (
    WidgetTester tester,
  ) async {
    await boot(tester, phoneSize: const Size(411, 891), textScale: 1.15);
    debugPrint('F takeException: ${tester.takeException()}');
    expect(find.text('Полезные'), findsOneWidget);
    expect(find.text('Вредные'), findsOneWidget);
    reportGeometry(tester, 'GEOMETRY phone');

    final before = orderNow();
    final label = globalRect(tester, find.text('Вредные'));
    debugPrint('F ORDER BEFORE: $before');
    debugPrint('F hit-test @ center(Вредные): ${probe(tester, label.center)}');
    await dragFrom(tester, label.center, dy: -120);
    final after = orderNow();
    debugPrint('F ORDER AFTER: $after');
    debugPrint(
      'F REORDERED(phone bad header): ${before.join() != after.join()}',
    );
  });
}

/// Настоящий long-press-drag: down → пауза дольше longPressTimeout (500 мс)
/// → движение на [dy] дробными шагами → up.
Future<void> dragFrom(
  WidgetTester tester,
  Offset start, {
  double dy = -120,
}) async {
  final g = await tester.startGesture(start);
  await tester.pump(const Duration(milliseconds: 600));
  final steps = 8;
  for (var k = 0; k < steps; k++) {
    await g.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await g.up();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 600));
}
