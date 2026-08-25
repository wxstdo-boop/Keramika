import 'package:flutter/material.dart';

/// Parses inline markdown into a list of [TextSpan]s.
/// Supports **bold**, *italic*, `code`.
///
/// After parsing, trailing punctuation is merged into the previous span
/// so that "word," stays as one unit — Skia won't break the comma onto
/// a new line because it's in the same span as the word.
TextSpan parseMarkdownSpans(String text, TextStyle baseStyle) {
  final raw = <InlineSpan>[];
  final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|[^*`]+)');

  for (final match in regex.allMatches(text)) {
    final full = match.group(0)!;
    final bold = match.group(2);
    final italic = match.group(3);
    final code = match.group(4);

    if (bold != null) {
      raw.add(TextSpan(
        text: bold,
        style: baseStyle.copyWith(fontWeight: FontWeight.w600),
      ));
    } else if (italic != null) {
      raw.add(TextSpan(
        text: italic,
        style: baseStyle.copyWith(fontStyle: FontStyle.italic),
      ));
    } else if (code != null) {
      raw.add(TextSpan(
        text: code,
        style: baseStyle.copyWith(
          backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
        ),
      ));
    } else {
      raw.add(TextSpan(text: full, style: baseStyle));
    }
  }

  // Merge trailing punctuation into the previous span.  Skia treats each
  // span as an independent break opportunity — if a comma ends up in its
  // own plain span (after a bold word, for instance), it can strand on
  // the next line.  Merging it into the previous span makes "word,"
  // break as a unit.
  final merged = _mergePunctuation(raw);
  return TextSpan(style: baseStyle, children: merged.isNotEmpty ? merged : null);
}

bool _isWordChar(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    (c >= 0x400 && c <= 0x45F) || // Cyrillic
    (c >= 0x410 && c <= 0x44F);

List<InlineSpan> _mergePunctuation(List<InlineSpan> spans) {
  if (spans.length < 2) return spans;
  final out = <InlineSpan>[];
  for (var i = 0; i < spans.length; i++) {
    final prev = out.isNotEmpty ? out.last : null;
    final cur = spans[i];
    final curText = (cur is TextSpan) ? (cur.text ?? '') : '';

    if (prev != null && curText.isNotEmpty) {
      final prevSpan = prev as TextSpan;
      final prevText = prevSpan.text ?? '';
      // Does current span start with trailing punctuation (possibly
      // preceded by a space: " ," or " —")?
      final m = RegExp(r'^( ?[,.!?;:»…]| ?—| ?–)').firstMatch(curText);
      if (m != null && prevText.isNotEmpty) {
        final tail = m.group(0)!;
        final lastChar =
            prevText.isNotEmpty ? prevText.codeUnitAt(prevText.length - 1) : -1;
        if (_isWordChar(lastChar)) {
          out[out.length - 1] = TextSpan(
            text: prevText + tail,
            style: prevSpan.style,
          );
          final rest = curText.substring(tail.length);
          if (rest.isNotEmpty) {
            out.add(TextSpan(text: rest, style: prevSpan.style));
          }
          continue;
        }
      }
    }
    out.add(cur);
  }
  return out;
}

/// Simple inline markdown renderer for non-selectable contexts.
Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(text: parseMarkdownSpans(text, baseStyle));
}