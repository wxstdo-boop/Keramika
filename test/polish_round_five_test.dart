import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/widgets/profile_avatar.dart';

/// Регрессы пятого круга полировки:
///  * своя аватарка при размытии (скролл) рисуется через [ImageFiltered] —
///    расфокус «заходит» за круг, а не обрезается клипом (не было видно
///    граней);
///  * аватарка не «пропадает» на входе: пока файл декодируется, показывается
///    сгенерированный вариант (frameBuilder);
///  * подпись музыки — статичный текст «Играет бодрый звук» без мигания
///    «Пауза/Играет».
void main() {
  late Directory tmpDir;
  late File imgFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('keramika_round_five');
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
      reason: 'размытие рисуется вокруг клипа — ореол выходит за круг',
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
}
