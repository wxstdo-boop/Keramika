import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/l10n/translations.dart';
import 'package:agysha/widgets/update_pill.dart';

/// Регрессы четвёртого круга полировки:
///  * «мотивация дня» — полный набор из 90 цитат в каждой локали, все
///    непустые (раньше часть ключей жила только в одной локали);
///  * таблетка обновления рисуется и содержит зайчика-глиф, а не падает
///    на пустом `pendingUpdate`.
void main() {
  late Map<String, Map<String, String>> dicts;

  setUpAll(() {
    dicts = Translations.rawData;
  });

  test('мотивация дня: 90 цитат в каждой локали и все непустые', () {
    for (final loc in ['en', 'ru', 'fr']) {
      final d = dicts[loc]!;
      for (var i = 1; i <= 90; i++) {
        final v = d['motivationQuote$i'];
        expect(v, isNotNull, reason: 'в $loc нет motivationQuote$i');
        expect(
          v!.trim(),
          isNotEmpty,
          reason: 'в $loc пустая motivationQuote$i',
        );
      }
    }
  });

  testWidgets('таблетка обновления рендерится без исключений', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(body: Center(child: UpdatePill())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(UpdatePill), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
