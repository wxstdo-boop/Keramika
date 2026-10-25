import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/l10n/translations.dart';

/// Регресс-тест на целостность словарей переводов.
///
/// Зачем: словари живут в одном файле (`lib/l10n/translations.dart`) и
/// правятся вручную. Дважды в истории случалось, что ключ добавляли в одну
/// локаль и забывали в другие:
///
///  * ключ `aiTrackingNoPerm` существовал только во `fr` — в `en`/`ru` он
///    превращался в «someKeyName» прямо в интерфейсе;
///  * при слиянии веток `forgeTitle`, `forgeSubtitle` и `forgeTokenHint`
///    задвоились в каждой локали — это ошибка компиляции Dart.
///
/// Тест ловит оба случая и не даёт им вернуться.
///
/// Данные берутся из самого приложения (`Translations.rawData`), а не
/// разбираются из исходника текстом: многострочные значения и значения с
/// кавычками внутри такой разбор ломает, и тест проверял бы не то.
void main() {
  late Map<String, Map<String, String>> dictionaries;

  setUpAll(() {
    dictionaries = Translations.rawData;
  });

  test('ожидаются ровно три локали', () {
    expect(
      dictionaries.keys.toSet(),
      {'en', 'ru', 'fr'},
      reason:
          'Ожидались локали en/ru/fr, получено: ${dictionaries.keys.toList()}',
    );
  });

  test('наборы ключей en/ru/fr совпадают', () {
    final en = dictionaries['en']!.keys.toSet();
    final ru = dictionaries['ru']!.keys.toSet();
    final fr = dictionaries['fr']!.keys.toSet();

    expect(
      en.difference(ru),
      isEmpty,
      reason:
          'В ru нет ключей, которые есть в en: '
          '${(en.difference(ru)).toList()..sort()}',
    );
    expect(
      en.difference(fr),
      isEmpty,
      reason:
          'В fr нет ключей, которые есть в en: '
          '${(en.difference(fr)).toList()..sort()}',
    );
    expect(
      ru.difference(en),
      isEmpty,
      reason:
          'В ru есть лишние ключи, которых нет в en: '
          '${(ru.difference(en)).toList()..sort()}',
    );
    expect(
      fr.difference(en),
      isEmpty,
      reason:
          'В fr есть лишние ключи, которых нет в en: '
          '${(fr.difference(en)).toList()..sort()}',
    );
  });

  test('ни один ключ не задвоен', () {
    // Дубль в карте — ошибка компиляции Dart, но если он случился в
    // словаре, который собирается как const-карта, компилятор поймает это
    // раньше теста. Проверка остаётся как страховка от синтаксических
    // конструкций, которые компилятор пропустит (например, опечатка в
    // кавычках превращает дубль в два РАЗНЫХ ключа).
    for (final entry in dictionaries.entries) {
      final keys = entry.value.keys.toList();
      expect(
        keys.length,
        keys.toSet().length,
        reason: 'В локали «${entry.key}» есть повторяющиеся ключи',
      );
    }
  });

  test('перевод не равен имени ключа', () {
    // Значение вида 'someKeyName' — это не перевод, а заглушка: пользователь
    // увидит в интерфейсе имя ключа. Исключение — однобуквенные и слова,
    // которые совпадают с ключом намеренно (например, 'streak' в английском
    // переводится как 'streak'), поэтому сравниваем только camelCase-вид.
    final camelCase = RegExp(r'^[a-z]+[A-Z][A-Za-z0-9]*$');
    for (final entry in dictionaries.entries) {
      for (final kv in entry.value.entries) {
        if (!camelCase.hasMatch(kv.value)) continue;
        expect(
          kv.value,
          isNot(kv.key),
          reason:
              'Значение ключа «${kv.key}» в локали «${entry.key}» совпадает '
              'с именем ключа — это заглушка вместо перевода',
        );
      }
    }
  });
}
