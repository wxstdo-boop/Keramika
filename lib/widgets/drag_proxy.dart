import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  // Если задан — прокси репортит свою глобальную Y-координату на каждом
  // кадре движения и сбрасывает её в null при размонтировании (конец
  // драга, включая отмену). Экран использует это, чтобы заголовки секций
  // мягко «расступались», когда карточка проходит сквозь них.
  ValueNotifier<double?>? trackY,
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
  final proxy = AnimatedBuilder(
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
  if (trackY == null) return proxy;
  return _ProxyPositionReporter(notifier: trackY, child: proxy);
}

/// Отслеживает глобальную позицию drag-прокси: репортит верхнюю
/// Y-координату в [notifier] на каждом кадре движения и сбрасывает её
/// в null при снятии прокси — драг кончился (drop ИЛИ отмена).
class _ProxyPositionReporter extends SingleChildRenderObjectWidget {
  final ValueNotifier<double?> notifier;

  const _ProxyPositionReporter({
    required this.notifier,
    required Widget child,
  }) : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProxyPositionReporter(notifier);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderProxyPositionReporter renderObject,
  ) {
    renderObject.notifier = notifier;
  }
}

class _RenderProxyPositionReporter extends RenderProxyBox {
  ValueNotifier<double?> notifier;
  double? _lastY;

  _RenderProxyPositionReporter(this.notifier);

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final y = localToGlobal(Offset.zero).dy;
    if (y == _lastY) return;
    _lastY = y;
    // Уведомляем вне фазы paint (post-frame): слушатели делают setState,
    // а во время перерисовки это было бы нарушением.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (notifier.value != y) notifier.value = y;
    });
  }

  @override
  void detach() {
    // Прокси снят — драг закончился. Возвращаем заголовки.
    if (notifier.value != null) notifier.value = null;
    super.detach();
  }
}
