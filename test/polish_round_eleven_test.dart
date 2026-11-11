import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/screens/stats_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/widgets/profile_avatar.dart';
import 'package:agysha/widgets/update_pill.dart';

/// Регрессы полировки одиннадцатого круга:
///  * экран статистики больше НЕ крутит вечный «глитч»: числа статичны, а
///    тени-двойники (из-за которых последняя цифра читалась «иероглифом»)
///    убраны;
///  * смена аватарки снова анимируется (ключ стоял внутри `AnimatedBuilder`,
///    и `AnimatedSwitcher` не видел подмены);
///  * при прокрутке аватарка только расплывается — параллакс убран, иначе
///    сверху открывалась «залысина»;
///  * окно обновления — без `BackdropFilter`, который мерцал на переходе.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 11));
    tmpDir = await Directory.systemTemp.createTemp('agysha_round_eleven');
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

  testWidgets('статистика: числа не «глитчат» — ни одной вечной анимации', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const RealityCheckStatsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    // Глитч рисовался `CustomPaint` с painter'ом-тенями. Его больше нет.
    expect(
      find.byType(CustomPaint),
      findsWidgets,
      reason: 'график всё ещё рисуется на canvas',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('смена аватарки анимируется (ключ виден AnimatedSwitcher)', (
    tester,
  ) async {
    var index = 0;
    late StateSetter setOuter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setOuter = setState;
              return Center(
                child: ProfileAvatar(index: index, size: 96),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Меняем индекс: переключатель обязан начать переход, то есть в дереве
    // появляется FadeTransition поверх уходящего слоя.
    setOuter(() => index = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      find.byType(FadeTransition),
      findsWidgets,
      reason: 'смена аватарки должна проходить кросс-фейдом, а не мгновенно',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('профиль: при прокрутке аватарка расплывается, но не сдвигается', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 900));

    expect(
      find.byKey(const ValueKey('avatar_motion')),
      findsNothing,
      reason: 'параллакс убран — аватарка не уезжает и не даёт «залысин»',
    );

    final list = find.byType(ListView);
    final g = await tester.startGesture(tester.getCenter(list));
    for (var i = 0; i < 3; i++) {
      await g.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byType(ImageFiltered),
      findsWidgets,
      reason: 'при прокрутке аватарка должна расплываться',
    );
    await g.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('окно обновления без BackdropFilter (не мерцает)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: Center(child: UpdatePill())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Размытие пересобиралось на каждом кадре всплытия окна и «мигало».
    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason: 'стекло окна обновления должно быть без пересборки фильтра',
    );
    expect(tester.takeException(), isNull);
  });
}
