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
      spans.add(
        TextSpan(
          text: bold,
          // БЕЗ изменения размера: жирный/курсив/код имеют РОВНО тот же
          // fontSize, что обычный текст (раньше множители 0.96/0.92 в
          // связке с кеглем темы ощущались как «markdown увеличивается»).
          style: baseStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    } else if (italic != null) {
      spans.add(
        TextSpan(
          text: italic,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    } else if (code != null) {
      spans.add(
        TextSpan(
          text: code,
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: baseStyle.color?.withValues(alpha: 0.12),
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: full, style: baseStyle));
    }
  }

  return TextSpan(style: baseStyle, children: spans.isNotEmpty ? spans : null);
}

/// Simple inline markdown renderer for non-selectable contexts.
Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(text: parseMarkdownSpans(text, baseStyle));
}
