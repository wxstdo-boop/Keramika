import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/stats_screen.dart';
import 'package:keramika/widgets/inline_keyboard.dart';
import 'package:keramika/widgets/profile_avatar.dart';

/// Регрессы полировки восьмого круга:
///  * шапка графика в статистике не переполняется даже на узком экране —
///    раньше строка уезжала на 19 px и резала последнюю цифру суммы;
///  * кольцо своей аватарки на тёмной теме приглушено (раньше слепило);
///  * встроенная клавиатура повторяет «стереть» при удержании.
void main() {
  late Directory tmpDir;
  late File imgFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('keramika_round_eight');
    imgFile = File('${tmpDir.path}/ava.png');
    await imgFile.writeAsBytes(const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
      0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
      0x42, 0x60, 0x82,
    ]);
  });

  tearDown(() async {
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('статистика: шапка графика не переполняется на узком экране', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

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

    expect(
      tester.takeException(),
      isNull,
      reason: 'шапка «Последние 30 дней» больше не должна переполняться',
    );
  });

  testWidgets('обводка своей авы на тёмной теме приглушена', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(index: 0, size: 96, imagePath: imgFile.path),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final ring = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('avatar_ring')),
        matching: find.byType(DecoratedBox),
      ),
    );
    final border = (ring.decoration as BoxDecoration).border! as Border;
    expect(
      border.top.color.a,
      lessThan(0.5),
      reason: 'белое кольцо 0.82 на тёмной теме слепило',
    );
  });

  testWidgets('клавиатура: возврат повторяется при удержании', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineKeyboard(
            onChar: (_) {},
            onBackspace: () => count++,
            onSpace: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final backspace = find.byIcon(Icons.backspace_outlined).first;
    final g = await tester.startGesture(tester.getCenter(backspace));
    // Пережидаем задержку до первого повтора и несколько шагов повтора.
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump(const Duration(milliseconds: 300));
    await g.up();
    await tester.pump();

    expect(
      count,
      greaterThan(1),
      reason: 'удержание «стереть» должно повторять удаление',
    );
    expect(tester.takeException(), isNull);
  });
}
