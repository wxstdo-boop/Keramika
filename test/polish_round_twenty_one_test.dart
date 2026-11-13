import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Регресс-тест круга 21: профиль, клавиатура, окно события, «Метель»,
/// статистика и питание.
///
/// Каждая проверка закрывает конкретную жалобу владельца:
///  * у всех карточек профиля — мягкая отдача «вдавливанием»;
///  * кнопка «Добавить друга» вернулась отдельной кнопкой над клавиатурой;
///  * отдача клавиш встроенной клавиатуры медленнее и мягче;
///  * при переключении регистра буквы плавно поднимаются и опускаются;
///  * окно события входит дольше, содержимое догоняет плавно, каскад шапок
///    не стартует поверх входа;
///  * «Метель»: снежинки — полупрозрачные кругляши, сияние тише;
///  * статистика: нет наложенных чисел-«иероглифов», нет точки «сегодня»
///    поверх подписи даты, нет тридцати клип-слоёв на кадр;
///  * питание: свайп-удаление совпадает с карточкой по скруглению, знак
///    закрепа появляется без отскока, заголовок дня гаснет плавно.
void main() {
  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path не найден — тест не из корня');
    return f.readAsStringSync();
  }

  /// Код без строк-комментариев: проверки на подстроки не должны ловить сами
  /// пояснения, в которых эти подстроки упомянуты.
  String code(String path) => read(
    path,
  ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('профиль: карточки отзываются вдавливанием, музыка — нет', () {
    final src = code('lib/screens/profile_screen.dart');
    final card = src.substring(
      src.indexOf('class _Card extends StatelessWidget'),
    );
    expect(
      card.contains('PressScale('),
      isTrue,
      reason: 'карточка профиля обязана оборачиваться в PressScale',
    );
    expect(
      card.contains('pressedOpacity'),
      isTrue,
      reason: 'крупной карточке мало масштаба — нужна и просадка плотности',
    );
    expect(
      src.contains('pressable: false'),
      isTrue,
      reason: 'у карточки музыки свои жесты — общая отдача выключена',
    );
  });

  test('клавиатура: медленная отдача, плавный регистр, без кнопки-действия', () {
    final src = code('lib/widgets/inline_keyboard.dart');
    expect(
      src.contains('Duration(milliseconds: 190)') &&
          src.contains('Duration(milliseconds: 340)'),
      isTrue,
      reason: 'отдача клавиши должна быть медленнее прежних 90/180 мс',
    );
    expect(
      src.contains('class _CaseGlyph'),
      isTrue,
      reason: 'буква обязана менять регистр плавным подъёмом/спуском',
    );
    expect(
      src.contains('_caseAnim'),
      isTrue,
      reason: 'регистр ведёт общий контроллер, а не мгновенная подмена',
    );
  });

  test('окно события: длинный вход и отложенный каскад шапок', () {
    final src = code('lib/widgets/new_year_event_banner.dart');
    expect(
      src.contains('Duration(milliseconds: 700)'),
      isTrue,
      reason: 'вход окна удлинён — иначе содержимое читается дёрганым',
    );
    expect(
      src.contains('_seedHatsAfterEntrance'),
      isTrue,
      reason: 'каскад шапок не должен стартовать поверх входа',
    );
    expect(
      src.contains('begin: 0.975'),
      isTrue,
      reason: 'старт масштаба 0.94 давал резкий «наезд» карточки',
    );
  });

  test('«Метель»: снег-кругляши и тихое сияние', () {
    final src = code('lib/widgets/metel_overlay.dart');
    expect(
      src.contains('drawLine'),
      isFalse,
      reason: 'снежинки-штрихи читались грязными царапинами',
    );
    expect(
      src.contains('0xFFF4FBFF'),
      isTrue,
      reason: 'снежинка должна быть светлым кругляшом',
    );
    expect(
      src.contains('0xFF5C7C8C'),
      isFalse,
      reason: 'тёмный сине-серый тон делал снег похожим на мусор',
    );
    expect(
      src.contains('alpha: 0.11'),
      isTrue,
      reason: 'сияние приглушено до «идеала»',
    );
  });

  test('статистика: нет наложенных чисел, точки поверх даты и клип-слоёв', () {
    final src = code('lib/screens/stats_screen.dart');
    expect(
      src.contains('AnimatedSwitcher'),
      isFalse,
      reason: 'кроссфейд накладывал две цифры — это и был «иероглиф»',
    );
    expect(
      src.contains('chartBottom + 6'),
      isFalse,
      reason: 'точка «сегодня» лезла под подпись последнего дня',
    );
    expect(
      src.contains('clipRRect'),
      isFalse,
      reason: 'тридцать клип-слоёв на кадр роста — источник лага',
    );
  });

  test('питание: свайп под карточку, плавный закреп и заголовок дня', () {
    final src = code('lib/screens/nutrition_screen.dart');
    expect(
      src.contains('borderRadius: 20'),
      isTrue,
      reason: 'плашка удаления должна совпадать с карточкой по скруглению',
    );
    expect(
      src.contains('class _DayHeader'),
      isTrue,
      reason: 'заголовок дня обязан появляться и исчезать плавно',
    );
    expect(
      src.contains('switchInCurve: Curves.easeOutCubic'),
      isTrue,
      reason: 'значок закрепа без отскока — мягкий разгон',
    );
  });
}
