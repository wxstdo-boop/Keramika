import 'package:flutter/material.dart';
import 'smooth_hover.dart';
import 'stagger_in.dart';

/// Красивый drag-proxy для ReorderableListView.
///
/// Главное правило: прокси рисует карточку РОВНО в тех же габаритах, что и
/// в списке — ни сужения, ни сдвига. Иначе текст с мягким переносом
/// (softWrap) ПЕРЕТЕКАЕТ на другие строки прямо во время драга (визуально
/// «строки меняют расположение»), а при отпускании карточка «прыгает»
/// обратно в исходную раскладку.
///
/// Обводка-«кольцо» рисуется через foregroundDecoration ПОВЕРХ карточки —
/// она не участвует в layout и не меняет ширину. Подъём — лёгкий scale
/// 1.02 с той же кривой easeOut, что у drop-анимации ReorderableListView,
/// поэтому при отпускании масштаб и скольжение на место движутся синхронно.
Widget buildDragProxy(
  Widget child,
  ThemeData theme,
  Animation<double> animation, {
  double borderRadius = 20,
}) {
  // Перетаскиваемый элемент монтируется в оверлее ЗАНОВО (новые State),
  // поэтому каскадная входная анимация (StaggerIn) проигрывалась бы ещё
  // раз прямо во время драга. Подавляем вход на время монтирования прокси
  // и снимаем флаг после кадра.
  StaggerIn.suppressEntrance = true;
  // Прокси-копия карточки стартует БЕЗ эффекта нажатия SmoothHover,
  // а живая карточка в списке сбрасывает своё зажатие (см. SmoothHover).
  SmoothHover.dragProxyCount.value++;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    StaggerIn.suppressEntrance = false;
    SmoothHover.dragProxyCount.value--;
  });
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final raw = animation.value;
      // easeOut совпадает с кривой drop-анимации позиции — масштаб и
      // скольжение движутся в одном темпе, без «двойного» движения.
      final t = Curves.easeOut.transform(raw);
      // Мягкий подъём: 1.0 → 1.02.
      final scale = 1.0 + 0.02 * t;
      return Transform.scale(
        scale: scale,
        child: Material(
          elevation: 2 + 8 * t,
          shadowColor: theme.colorScheme.primary.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(borderRadius),
          color: theme.colorScheme.surface,
          clipBehavior: Clip.none,
          child: Container(
            // Размер карточки не меняется: обводка рисуется поверх.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(
                  alpha: 0.15 + 0.55 * t,
                ),
                width: 1.5 + t,
              ),
            ),
            child: child,
          ),
        ),
      );
    },
  );
}
