import 'package:flutter_test/flutter_test.dart';

import 'package:agysha/utils/icon_map.dart';

/// Набор иконок привычек/задач: полный список и сетка выбора.
void main() {
  test('сетка выбора без дублей codePoint', () {
    final seen = <int>{};
    for (final icon in HabitTaskIconList.picker) {
      expect(
        seen.add(icon.codePoint),
        isTrue,
        reason: 'иконка ${icon.codePoint} повторяется в HabitTaskIconList.picker',
      );
    }
  });

  test('сетка выбора — подмножество полного набора', () {
    final all = HabitTaskIconList.all.map((i) => i.codePoint).toSet();
    for (final icon in HabitTaskIconList.picker) {
      expect(all.contains(icon.codePoint), isTrue);
    }
  });

  test('iconDataForCodePoint находит иконку из сетки выбора', () {
    for (final icon in HabitTaskIconList.picker) {
      expect(iconDataForCodePoint(icon.codePoint).codePoint, icon.codePoint);
    }
  });

  test('набор не меньше 450 иконок (базовые + 150 новых)', () {
    expect(HabitTaskIconList.picker.length, greaterThanOrEqualTo(450));
  });
}
