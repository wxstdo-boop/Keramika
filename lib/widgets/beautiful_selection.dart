import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// Красивые ручки выделения текста: кружок в цвете темы с белой обводкой
/// («обводочка») и мягкой тенью — вместо дефолтных тонких полосок.
class BeautifulSelectionControls extends TextSelectionControls {
  BeautifulSelectionControls();

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.primary,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildToolbar(
    BuildContext context,
    Rect globalEditableRegion,
    double textLineHeight,
    Offset selectionMidpoint,
    List<TextSelectionPoint> endpoints,
    TextSelectionDelegate delegate,
    ValueListenable<ClipboardStatus>? clipboardStatus,
    Offset? lastSecondaryTapDownPosition,
  ) {
    // Раньше тут был shrink — при выделении ПЕРЕТАСКИВАНИЕМ ручек на телефоне
    // панель с «Копировать» не появлялась вовсе. Теперь строим настоящий
    // тулбар (Копировать / Поделиться / Выделить всё) — как и меню по
    // долгому нажатию (contextMenuBuilder), единый стиль.
    return buildChatSelectionMenu(context, delegate as EditableTextState);
  }

  @override
  Size getHandleSize(double textLineHeight) => const Size(24, 24);

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    return const Offset(12, 12);
  }
}

/// Тулбар выделения в чате: Копировать / Выделить всё.
/// Без «Поделиться», «Спросить Copilot» и прочих пунктов системного меню.
/// Адаптивный (Android/iOS), кнопки стандартные — вид остаётся системным,
/// а «красоту» дают ручки [BeautifulSelectionControls].
Widget buildChatSelectionMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        type: ContextMenuButtonType.copy,
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
          editableTextState.hideToolbar();
        },
      ),
      ContextMenuButtonItem(
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
      ),
    ],
  );
}
