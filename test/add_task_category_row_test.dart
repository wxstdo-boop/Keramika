import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/add_task_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/task_service.dart';

/// «+ Новая категория» стоит в ОДНОМ ряду с категориями и выровнена по их
/// центру: раньше кнопка не центрировалась и прилипала к верху строки —
/// читалось как «новая категория стоит выше остальных».
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 3));
    tmpDir = await Directory.systemTemp.createTemp('agysha_cat_row');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? tmpDir.path
              : null,
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

  testWidgets('«+ Новая категория» выровнена по центру ряда', (tester) async {
    await tester.runAsync(() async {
      final svc = TaskService();
      await svc.load();
      for (final c in svc.categories.toList()) {
        await svc.removeCategory(c);
      }
      await svc.addCategory('Работа');
    });
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: AddTaskScreen()),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Ряд категорий живёт ниже первого экрана — доскроллим до него.
    await tester.scrollUntilVisible(
      find.text('Работа'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 300));

    final cat = tester.getCenter(find.text('Работа'));
    final neu = tester.getCenter(find.text('Новая категория'));
    expect(
      (cat.dy - neu.dy).abs(),
      lessThan(1.0),
      reason: 'кнопка не должна выбиваться вверх из ряда',
    );
  });
}
