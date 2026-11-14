import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/screens/profile_screen.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/widgets/inline_keyboard.dart';

/// Тесты подборки музыки и кнопки в клавиатуре листа друга.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    tmpDir = await Directory.systemTemp.createTemp('agysha_music');
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

  test('в подборку влезает ровно 99 треков, 100-й не добавляется', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.clearTracks();
    for (var i = 0; i < ProfileService.maxTracks; i++) {
      final ok = await svc.addTrack(path: '/tmp/t$i.mp3', title: 'Трек $i');
      expect(ok, isTrue, reason: 'трек №${i + 1} должен добавляться');
    }
    expect(svc.tracks.length, ProfileService.maxTracks);
    expect(svc.canAddTrack, isFalse);

    final overflow = await svc.addTrack(path: '/tmp/x.mp3', title: 'Лишний');
    expect(overflow, isFalse);
    expect(svc.tracks.length, ProfileService.maxTracks);
  });

  test('трек можно убрать и переименовать', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.clearTracks();
    await svc.addTrack(path: '/tmp/a.mp3', title: 'Первый');
    final id = svc.tracks.first.id;

    await svc.renameTrack(id, 'Тебе нравится эта песня?');
    expect(svc.tracks.first.title, 'Тебе нравится эта песня?');

    await svc.removeTrack(id);
    expect(svc.tracks, isEmpty);
  });

  testWidgets('кнопка-действие живёт в клавиатуре и зовёт обработчик', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineKeyboard(
            onChar: (_) {},
            onBackspace: () {},
            onSpace: () {},
            actionLabel: 'Добавить',
            onAction: () => taps++,
          ),
        ),
      ),
    );
    expect(find.text('Добавить'), findsOneWidget);
    await tester.tap(find.text('Добавить'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('без actionLabel клавиатура не рисует лишней кнопки', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineKeyboard(
            onChar: (_) {},
            onBackspace: () {},
            onSpace: () {},
          ),
        ),
      ),
    );
    expect(find.text('Добавить'), findsNothing);
  });

  testWidgets('карточка музыки показывает пустое состояние и «Добавить»', (
    tester,
  ) async {
    final svc = ProfileService();
    await tester.runAsync(() async {
      await svc.load();
      await svc.clearTracks();
    });
    tester.view.physicalSize = const Size(411, 1400) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Добавить'), findsOneWidget);
    expect(find.text('Заменить'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
