import 'package:flutter/material.dart';

/// Parses inline markdown into a list of [TextSpan]s.
/// Supports **bold**, *italic*, `code`.
TextSpan parseMarkdownSpans(String text, TextStyle baseStyle) {
  final spans = <InlineSpan>[];
  final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|[^*`]+)');

  for (final match in regex.allMatches(text)) {
    final full = match.group(0)!;
    final bold = match.group(2);
    final italic = match.group(3);
    final code = match.group(4);

    if (bold != null) {
      spans.add(TextSpan(
        text: _keepPunctuationWithWord(bold),
        style: baseStyle.copyWith(fontWeight: FontWeight.w600),
      ));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: _keepPunctuationWithWord(italic),
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (code != null) {
      spans.add(TextSpan(
        text: _keepPunctuationWithWord(code),
        style: baseStyle.copyWith(
          backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
        ),
      ));
    } else {
      spans.add(TextSpan(text: _keepPunctuationWithWord(full), style: baseStyle));
    }
  }

  return TextSpan(style: baseStyle, children: spans.isNotEmpty ? spans : null);
}

/// Replaces only spaces inside a lexical word/punctuation unit with NBSP.
/// This keeps words whole and also keeps `слово,` together, without inserting
/// characters inside a word (which would split Caveat words). Spaces between
/// different words stay ordinary and remain valid line-break points.
String _keepPunctuationWithWord(String text) {
  // Запятая/точка остаётся обычным символом, но пробелы перед знаками
  // превращаем в NBSP. Внутрь самого слова ничего не вставляем: Caveat
  // не получает искусственной точки переноса.
  if (text.isEmpty) return text;
  final chars = text.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (c == 0x20 && i + 1 < chars.length && _isPunctuation(chars[i + 1])) {
      out.writeCharCode(0x00A0);
    } else {
      out.write(String.fromCharCode(c));
    }
  }
  return out.toString();
}

bool _isPunctuation(int c) =>
    c == 0x2C || c == 0x2E || c == 0x3B || c == 0x3A || c == 0x21 ||
    c == 0x3F || c == 0xBB || c == 0x2026 || c == 0x2014 || c == 0x2013;

/// Simple inline markdown renderer for non-selectable contexts.
Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(text: parseMarkdownSpans(text, baseStyle));
}
