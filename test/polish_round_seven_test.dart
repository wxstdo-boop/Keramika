import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/theme/app_theme.dart';
import 'package:keramika/widgets/profile_avatar.dart';

/// Регрессы полировки седьмого круга:
///  * карточки снова читаются тенью (`elevation` > 0) — плоский кант на
///    светлой теме «сливал» их с фоном;
///  * размытие своей аватарки живёт ПОД клипом и квантуется по сигме —
///    край круга ровный, а фильтр не пересобирается каждый кадр скролла;
///  * кольцо аватарки по-прежнему поверх картинки.
void main() {
  late Directory tmpDir;
  late File imgFile;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('keramika_round_seven');
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

  testWidgets('карточки читаются тенью, а не плоским кантом', (tester) async {
    final theme = buildKeramikaTheme(
      ColorScheme.fromSeed(seedColor: const Color(0xFFB3261E)),
      isDark: false,
      isGrokStyle: false,
    );
    expect(
      theme.cardTheme.elevation,
      greaterThan(0),
      reason: 'без тени и с невидимым кантом карточки сливались с фоном',
    );
    expect(theme.cardTheme.shadowColor?.a, greaterThan(0));
  });

  testWidgets('размытие авы под клипом: ImageFiltered и RepaintBoundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(
              index: 0,
              size: 96,
              imagePath: imgFile.path,
              blur: 6,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ImageFiltered), findsOneWidget);
    // Слой размытия кэшируется: параллакс лишь сдвигает готовый слой.
    expect(
      find.ancestor(
        of: find.byType(ImageFiltered),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('кольцо авы по-прежнему поверх картинки', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProfileAvatar(
              index: 0,
              size: 96,
              imagePath: imgFile.path,
              blur: 4,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('avatar_ring')), findsOneWidget);
  });
}
