import 'package:flutter/services.dart';

/// Заменяет ЛЮБОЕ тире или дефис на широкое тире (em dash U+2014)
/// при вводе в текстовые поля.
///
/// Клавиатура телефона по кнопке «-» подставляет разные знаки: дефис-минус,
/// типографский дефис, короткое тире, математический минус. Раньше в наборе
/// их было всего два, поэтому часть тире оставалась узкой.
///
/// Второе (и главное) — зона «составления» (composing). Пока она не пуста,
/// клавиатура считает, что набирает СВОЙ текст, и после нашей подмены может
/// вернуть узкий знак обратно: поле выглядело так, будто замена не работает.
/// Поэтому при подмене зона составления сбрасывается.
///
/// ВАЖНО. Форматер стоит в цепочке `inputFormatters`, а она применяется
/// только к вводу с клавиатуры. Вставка из контекстного меню и программная
/// запись в контроллер идут мимо него — поэтому та же нормализация
/// продублирована в `WideDashController` (см. `wide_dash_controller.dart`).
class WideDashFormatter extends TextInputFormatter {
  /// Все «узкие» тире: дефис-минус, типографский дефис, неразрывный дефис,
  /// figure dash, короткое тире, математический минус, презентационные формы
  /// и полноширинный дефис.
  static final RegExp _dash = RegExp(
    '[-\u2010\u2011\u2012\u2013\u2212\uFE58\uFE63\uFF0D]',
  );

  /// Есть ли в строке хоть один узкий знак, требующий замены.
  static bool hasDash(String text) => _dash.hasMatch(text);

  /// Является ли один символ тире (узким или уже широким).
  static bool isDash(String glyph) =>
      glyph == '\u2014' || _dash.hasMatch(glyph);

  /// Строка с широкими тире вместо узких.
  static String normalize(String text) =>
      hasDash(text) ? text.replaceAll(_dash, '\u2014') : text;

  /// То же для значения поля: длина строки не меняется (один знак → один
  /// знак), поэтому выделение и зона составления остаются корректными.
  static TextEditingValue normalizeValue(TextEditingValue value) {
    if (!hasDash(value.text)) return value;
    return TextEditingValue(
      text: normalize(value.text),
      selection: value.selection,
      composing: TextRange.empty,
    );
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return normalizeValue(newValue);
  }
}
