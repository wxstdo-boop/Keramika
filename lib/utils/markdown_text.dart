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

/// Возвращает true, если спан заканчивается словом с хвостовой пунктуацией
/// (например "Steqtoq,"). В таком случае в слово вставляется ZWSP перед
/// последней буквой: "Steqto\u200Bq,". Если «слово,» не влезает, перенос
/// идёт ВНУТРИ слова, и запятая уходит на новую строку ВМЕСТЕ со слогом,
/// а не сиротой. В обычном случае (когда влезает) переноса нет вообще.
String glueTrailingPunctuation(String value) {
  final m = RegExp(r'^(.+?)([,.;!?…:»]+)$').firstMatch(value);
  if (m == null || m.group(1)!.isEmpty) return value;
  final word = m.group(1)!;
  final punct = m.group(2)!;
  // Последний символ слова — буква/цифра? (не ставить ZWSP после дефиса)
  final last = word.runes.last;
  final isLetter = (last >= 0x30 && last <= 0x39) || // digit
      (last >= 0x41 && last <= 0x5A) || // A-Z
      (last >= 0x61 && last <= 0x7A) || // a-z
      (last >= 0x400 && last <= 0x4FF); // cyrillic
  if (!isLetter) return value;
  final split = word.length - 1;
  // ZWSP между предпоследней и последней буквой — точка переноса,
  // которая срабатывает ТОЛЬКО когда слово+запятая не влезают.
  return '${word.substring(0, split)}\u200B${word.substring(split)}$punct';
}

/// Inline markdown renderer. Punctuation is kept with the preceding word by
/// making it part of the same span; this also works across bold/italic/code
/// boundaries without inserting visible characters into copied text.
TextSpan parseMarkdownSpans(String text, TextStyle baseStyle) {
  final spans = <TextSpan>[];
  final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|[^*`]+)');

  for (final match in regex.allMatches(sanitizeTextForWrap(text))) {
    final bold = match.group(2);
    final italic = match.group(3);
    final code = match.group(4);
    final style = bold != null
        ? baseStyle.copyWith(fontWeight: FontWeight.w600)
        : italic != null
            ? baseStyle.copyWith(fontStyle: FontStyle.italic)
            : code != null
                ? baseStyle.copyWith(
                    backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
                  )
                : baseStyle;
    final value = bold ?? italic ?? code ?? match.group(0)!;

    if (spans.isNotEmpty && _startsWithPunctuation(value)) {
      final previous = spans.removeLast();
      final punctuation = _takeLeadingPunctuation(value);
      spans.add(TextSpan(text: '${previous.text}$punctuation', style: previous.style));
      final rest = value.substring(punctuation.length);
      if (rest.isNotEmpty) spans.add(TextSpan(text: rest, style: style));
    } else {
      spans.add(TextSpan(text: glueTrailingPunctuation(value), style: style));
    }
  }

  return TextSpan(style: baseStyle, children: spans);
}

bool _startsWithPunctuation(String value) =>
    RegExp(r'^(?:[ \t]*[,.;!?…:»]+|[ \t]*[—–])').hasMatch(value);

String _takeLeadingPunctuation(String value) {
  final match = RegExp(r'^(?:[ \t]*[,.;!?…:»]+|[ \t]*[—–])').firstMatch(value);
  return match?.group(0) ?? '';
}

Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(
    text: parseMarkdownSpans(text, baseStyle),
    softWrap: true,
    overflow: TextOverflow.clip,
  );
}
