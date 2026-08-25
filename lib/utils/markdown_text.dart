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
        text: _protectWords(bold),
        style: baseStyle.copyWith(fontWeight: FontWeight.w600),
      ));
    } else if (italic != null) {
      spans.add(TextSpan(
        text: _protectWords(italic),
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (code != null) {
      spans.add(TextSpan(
        text: _protectWords(code),
        style: baseStyle.copyWith(
          backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
        ),
      ));
    } else {
      spans.add(TextSpan(text: _protectWords(full), style: baseStyle));
    }
  }

  return TextSpan(style: baseStyle, children: spans.isNotEmpty ? spans : null);
}

/// Replaces only spaces inside a lexical word/punctuation unit with NBSP.
/// This keeps words whole and also keeps `слово,` together, without inserting
/// characters inside a word (which would split Caveat words). Spaces between
/// different words stay ordinary and remain valid line-break points.
String _protectWords(String text) {
  if (text.isEmpty) return text;
  final chars = text.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    if (c == 0x20 && i > 0 && i + 1 < chars.length) {
      final prev = chars[i - 1];
      final next = chars[i + 1];
      // Space before punctuation: make the preceding punctuation unit
      // indivisible only when it is after a word. Normal word spaces remain.
      if (_isPunctuation(next) || _isPunctuation(prev)) {
        out.writeCharCode(0x00A0);
        continue;
      }
    }
    out.write(String.fromCharCode(c));
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
