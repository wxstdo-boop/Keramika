import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/widgets/music_pulse_ring.dart';
import 'package:agysha/widgets/profile_avatar.dart';

/// Регрессы полировки:
///  * своя аватарка при размытии (скролл) рисуется через [ImageFiltered] —
///    фильтр стоит ПОД клипом и вокруг самой картинки, поэтому край круга
///    остаётся ровным по всему периметру;
///  * кольцо своей аватарки рисуется ПОВЕРХ картинки и видно СРАЗУ, а не
///    только вместе с размытием;
///  * кольцо музыки — тонкая обводка (`stroke`), а не залитый круг;
///  * подпись музыки — статичный текст «Играет бодрый звук» без мигания
///    «Пауза/Играет».
void main() {
  late Directory tmpDir;
  late File imgFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('agysha_round_five');
    imgFile = File('${tmpDir.path}/ava.png');
    // Крошечный валидный PNG (1×1, прозрачный).
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

  testWidgets('своя ава при размытии идёт через ImageFiltered (без граней)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(index: 0, size: 96, imagePath: imgFile.path, blur: 6),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byType(ImageFiltered),
      findsOneWidget,
      reason: 'размытие рисуется под клипом — край круга остаётся ровным',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('без размытия ImageFiltered не добавляется', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(index: 0, size: 96, imagePath: imgFile.path),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ImageFiltered), findsNothing);
  });

  testWidgets('кольцо авы рисуется поверх и БЕЗ размытия', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(index: 0, size: 96, imagePath: imgFile.path),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Кольцо должно быть на месте с самого начала: раньше оно было фоном
    // клипа и появлялось только вместе с размытием.
    expect(find.byKey(const ValueKey('avatar_ring')), findsOneWidget);
  });

  testWidgets('кольцо музыки — тонкая обводка, а не залитый круг', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MusicPulseRing(
              active: true,
              child: Icon(Icons.play_arrow_rounded, size: 24),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Обводка рисуется CustomPaint'ом со `stroke`; залитого круга-«бублика»
    // под кнопкой (Container с SweepGradient) больше нет.
    final paint = find.descendant(
      of: find.byType(MusicPulseRing),
      matching: find.byType(CustomPaint),
    );
    expect(paint, findsWidgets);
    expect(find.byType(Container), findsNothing);
  });
}
