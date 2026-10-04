import 'package:flutter/material.dart';

/// Чистит текст перед рендером от невидимых символов, которые ломают
/// перенос строк:
///  — NBSP (U+00A0) склеивает слова и запрещает перенос: длинное слово
///    «сползает» на следующую строку, хотя на текущей куча места.
///  — ZWSP/BOM/word-joiner/soft-hyphen (попадают из ИИ/копипасты) дают
///    ложные точки переноса или «лишнюю ширину» перед пунктуацией.
String sanitizeTextForWrap(String text) {
  if (text.isEmpty) return text;
  final sb = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x00A0 || rune == 0x2007 || rune == 0x202F) {
      sb.write(' '); // NBSP -> обычный пробел (разрешает перенос)
    } else if (rune == 0xFEFF ||
        rune == 0x200B ||
        rune == 0x200C ||
        rune == 0x200D ||
        rune == 0x2060 ||
        rune == 0x00AD) {
      // невидимые служебные — выкидываем совсем
    } else {
      sb.writeCharCode(rune);
    }
  }
  return sb.toString();
}

/// Является ли rune эмодзи (основные диапазоны Unicode-эмодзи).
bool _isEmoji(int rune) {
  return (rune >= 0x1F300 &&
          rune <= 0x1FAFF) || // Misc/Emoticons/Transport/Supplemental
      (rune >= 0x2600 && rune <= 0x27BF) || // Misc Symbols / Dingbats
      (rune >= 0x1F1E6 && rune <= 0x1F1FF) || // Regional indicators (флаги)
      (rune >= 0x1F900 && rune <= 0x1F9FF) || // Supplemental Symbols
      (rune >= 0x1FA00 &&
          rune <= 0x1FAFF) || // Symbols & Pictographs Extended-A
      (rune >= 0x2300 && rune <= 0x23FF) || // Misc Technical
      (rune >= 0x2B00 && rune <= 0x2BFF) || // Misc Symbols & Arrows
      (rune >= 0x2900 && rune <= 0x297F) || // Supplemental Arrows-B
      rune == 0x200D || // ZWJ
      rune == 0x20E3 || // Combining Enclosing Keycap
      (rune >= 0xFE00 && rune <= 0xFE0F); // Variation Selectors
}

/// Является ли rune висячей пунктуацией, которую нельзя оставлять в
/// начале строки (запятая, точка, скобка и т.п.).
bool _isTrailingPunct(int rune) {
  return rune == 0x2C || // ,
      rune == 0x2E || // .
      rune == 0x21 || // !
      rune == 0x3F || // ?
      rune == 0x3A || // :
      rune == 0x3B || // ;
      rune == 0x2026 || // …
      rune == 0x00BB || // »
      rune == 0x0029 || // )
      rune == 0x005D || // ]
      rune == 0x007D || // }
      rune == 0x0022 || // "
      rune == 0x0027 || // '
      rune == 0x002D || // -
      rune == 0x2014 || // —
      rune == 0x2013; // –
}

/// Склеивает висячие символы (эмодзи, пунктуацию) с предыдущим словом
/// неразрывным пробелом, чтобы строка не начиналась с одинокого эмодзи/запятой.
/// Вызывать ПОСЛЕ [sanitizeTextForWrap] (та превращает NBSP в обычный пробел).
String joinTrailingSymbols(String text) {
  if (text.isEmpty) return text;
  final runes = text.runes.toList();
  final sb = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    final r = runes[i];
    // Обычный пробел перед эмодзи/пунктуацией → неразрывный (склеиваем).
    if (r == 0x20 && i + 1 < runes.length) {
      final next = runes[i + 1];
      if (_isEmoji(next) || _isTrailingPunct(next)) {
        sb.writeCharCode(0x00A0); // NBSP
        continue;
      }
    }
    sb.writeCharCode(r);
  }
  return sb.toString();
}

/// Возвращает спан для слова с хвостовой пунктуацией (например
/// "Steqtoq,"). Слово+пунктуация рендерятся ОДНИМ TextSpan — без единого
/// вставленного символа и БЕЗ точки переноса внутри слова. Перенос
/// возможен только на границах пробелов: если "Steqtoq," не влезает,
/// всё слово (вместе с запятой) целиком уходит на следующую строку —
/// запятая никогда не остаётся сиротой, слово не разбивается на два.
///
/// Раньше здесь слово делилось на два соседних TextSpan ("Steqto|q,") —
/// граница спанов была легальной точкой переноса, и на системном шрифте
/// слово «разъезжалось» на две строки. Ещё раньше вставлялся ZWSP
/// (U+200B), который на MiSans рендерился как видимый пробел внутри
/// слова — «пустые места».
TextSpan splitTrailingPunctuation(String value, TextStyle style) {
  return TextSpan(text: value, style: style);
}

/// Кусок разобранного текста: готовая строка + «род» оформления.
class _MdPiece {
  final String text;

  /// 0 — обычный, 1 — жирный, 2 — курсив, 3 — моноширинный «код».
  final int kind;
  const _MdPiece(this.text, this.kind);
}

/// Разбор текста в куски НЕ зависит от цвета, шрифта и масштаба — только от
/// самой строки. А [parseMarkdownSpans] вызывается на каждый КАДР анимации
/// зачёркивания (420 мс × 60 fps на каждый тап по галке), и там три
/// регулярки и два прохода по runes пересобирались заново ради смены одного
/// цвета. Держим разбор в маленьком кэше: пиксели от этого не меняются.
final Map<String, List<_MdPiece>> _mdCache = {};

/// Регулярки и проверки пунктуации компилируются один раз на запуск.
final RegExp _mdRegex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|[^*`]+)');
final RegExp _leadPunct = RegExp(r'^(?:[ 	]*[,.;!?…:»]+|[ 	]*[—–])');

List<_MdPiece> _parsePieces(String text) {
  final cached = _mdCache[text];
  if (cached != null) return cached;
  final pieces = <_MdPiece>[];
  for (final match in _mdRegex.allMatches(
    joinTrailingSymbols(sanitizeTextForWrap(text)),
  )) {
    final bold = match.group(2);
    final italic = match.group(3);
    final code = match.group(4);
    final kind = bold != null
        ? 1
        : italic != null
        ? 2
        : code != null
        ? 3
        : 0;
    var value = bold ?? italic ?? code ?? match.group(0)!;
    if (pieces.isNotEmpty && _leadPunct.hasMatch(value)) {
      final punctuation = _leadPunct.firstMatch(value)!.group(0)!;
      final previous = pieces.removeLast();
      pieces.add(_MdPiece('${previous.text}$punctuation', previous.kind));
      value = value.substring(punctuation.length);
      if (value.isEmpty) continue;
    }
    pieces.add(_MdPiece(value, kind));
  }
  if (_mdCache.length > 96) _mdCache.clear();
  _mdCache[text] = pieces;
  return pieces;
}

/// Inline markdown renderer. Punctuation is kept with the preceding word by
/// making it part of the same span; this also works across bold/italic/code
/// boundaries without inserting visible characters into copied text.
TextSpan parseMarkdownSpans(String text, TextStyle baseStyle) {
  final pieces = _parsePieces(text);
  final spans = <TextSpan>[
    for (final p in pieces)
      TextSpan(text: p.text, style: _styleForKind(p.kind, baseStyle)),
  ];
  return TextSpan(style: baseStyle, children: spans);
}

TextStyle _styleForKind(int kind, TextStyle baseStyle) => switch (kind) {
  1 => baseStyle.copyWith(fontWeight: FontWeight.w600),
  2 => baseStyle.copyWith(fontStyle: FontStyle.italic),
  3 => baseStyle.copyWith(
    backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
  ),
  _ => baseStyle,
};

Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(
    text: parseMarkdownSpans(text, baseStyle),
    softWrap: true,
    overflow: TextOverflow.clip,
  );
}
