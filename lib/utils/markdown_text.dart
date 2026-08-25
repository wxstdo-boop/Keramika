import 'package:flutter/material.dart';

/// Parses inline markdown into a list of [TextSpan]s.
/// Supports **bold**, *italic*, `code`.
TextSpan parseMarkdownSpans(String text, TextStyle baseStyle) {
  // SkParagraph может оставить хвостовую запятую/точку на новой строке
  // при узкой ширине (особенно Caveat и крупный системный масштаб). ZWSP
  // внутри слова переносит само слово, а не одинокий знак.
  final safeText = _protectPunctuationWrap(text);
  final spans = <InlineSpan>[];
  final regex = RegExp(r'(\*\*(.+?)\*\*|\*(.+?)\*|`(.+?)`|[^*`]+)');

  for (final match in regex.allMatches(safeText)) {
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
            // monospace на телефоне рендерится крупнее/шире основного
            // шрифта — пользователь видит «код увеличился». Оставляем
            // ТОТ ЖЕ шрифт и размер, только подкрашиваем фоном.
            backgroundColor: baseStyle.color?.withValues(alpha: 0.10),
          ),
        ),
      );
    } else {
      spans.add(TextSpan(text: full, style: baseStyle));
    }
  }

  return TextSpan(style: baseStyle, children: spans.isNotEmpty ? spans : null);
}

String _protectPunctuationWrap(String text) {
  if (text.isEmpty) return text;
  final units = text.codeUnits;
  final out = StringBuffer();
  var i = 0;
  while (i < units.length) {
    final c = units[i];
    if (_isLetterOrDigit(c)) {
      var end = i;
      while (end < units.length && _isLetterOrDigit(units[end])) end++;
      var p = end;
      while (p < units.length && _isTrailingPunctuation(units[p])) p++;
      final tailFollows = p > end &&
          (p == units.length || _isSpace(units[p]));
      if (tailFollows && end - i >= 3) {
        final split = end - 2;
        out.write(text.substring(i, split));
        out.write('\u200B');
        out.write(text.substring(split, end));
        out.write(text.substring(end, p));
        i = p;
        continue;
      }
      out.write(text.substring(i, end));
      i = end;
      continue;
    }
    // Не оставляем длинное тире одиноким в конце строки: nbsp после него
    // приклеивает тире к следующему слову. Это визуально тот же пробел.
    if ((c == 0x2014 || c == 0x2013) &&
        i > 0 && i + 1 < units.length &&
        _isSpace(units[i - 1]) && _isSpace(units[i + 1])) {
      out.writeCharCode(c);
      out.write('\u00A0');
      i += 2;
      continue;
    }
    out.writeCharCode(c);
    i++;
  }
  return out.toString();
}

bool _isTrailingPunctuation(int c) =>
    c == 0x2C || c == 0x2E || c == 0x3B || c == 0x3A || c == 0x21 ||
    c == 0x3F || c == 0xBB || c == 0x2026;

bool _isLetterOrDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x400 && c <= 0x45F) ||
    (c >= 0x410 && c <= 0x44F);

bool _isSpace(int c) => c == 0x20 || c == 0x09 || c == 0x0A || c == 0xA0;

/// Simple inline markdown renderer for non-selectable contexts.
Widget buildMarkdownText(String text, TextStyle baseStyle) {
  return RichText(text: parseMarkdownSpans(text, baseStyle));
}
