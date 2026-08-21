import 'package:flutter/material.dart';

import '../l10n/translations.dart';

/// Оборачивает выделенный фрагмент в markdown-маркеры курсива `*…*`
/// (или снимает их, если фрагмент уже в них) — без иконки, чисто текст.
/// В чате Ады такие фрагменты рендерятся настоящим курсивом через
/// parseMarkdownSpans.
void _toggleItalic(EditableTextState editableTextState) {
  final controller = editableTextState.widget.controller;
  final value = controller.value;
  final sel = value.selection;
  if (!sel.isValid || sel.isCollapsed) return;
  final text = value.text;
  final start = sel.start;
  final end = sel.end;
  if (start < 0 || end > text.length || end <= start) return;
  final selected = text.substring(start, end);
  // Уже в курсивных маркерах — снимаем их.
  if (selected.length >= 2 &&
      selected.startsWith('*') &&
      selected.endsWith('*')) {
    controller.value = TextEditingValue(
      text:
          text.substring(0, start) +
          selected.substring(1, selected.length - 1) +
          text.substring(end),
      selection: TextSelection(baseOffset: start, extentOffset: end - 2),
    );
  } else {
    controller.value = TextEditingValue(
      text:
          text.substring(0, start) + '*' + selected + '*' + text.substring(end),
      selection: TextSelection(baseOffset: start, extentOffset: end + 2),
    );
  }
}

/// Builds a minimal text selection context menu that only shows Copy, Paste,
/// Cut and Italic (Курсив). Use it as the [TextField.contextMenuBuilder] for
/// input fields.
Widget minimalContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final buttonItems = <ContextMenuButtonItem>[];

  if (editableTextState.copyEnabled) {
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () =>
            editableTextState.copySelection(SelectionChangedCause.toolbar),
        type: ContextMenuButtonType.copy,
      ),
    );
  }
  if (editableTextState.pasteEnabled) {
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () =>
            editableTextState.pasteText(SelectionChangedCause.toolbar),
        type: ContextMenuButtonType.paste,
      ),
    );
  }
  if (editableTextState.cutEnabled) {
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () =>
            editableTextState.cutSelection(SelectionChangedCause.toolbar),
        type: ContextMenuButtonType.cut,
      ),
    );
  }
  // Курсив: выделенный фрагмент оборачивается в *…* (в чате рендерится
  // настоящим курсивом). Без иконки — только текст.
  final sel = editableTextState.textEditingValue.selection;
  if (sel.isValid && !sel.isCollapsed) {
    buttonItems.add(
      ContextMenuButtonItem(
        label: Translations.t('italic', context, 'Курсив'),
        onPressed: () {
          _toggleItalic(editableTextState);
          editableTextState.hideToolbar();
        },
      ),
    );
  }

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: buttonItems,
  );
}
