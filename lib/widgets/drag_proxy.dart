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
  // ПРОКСИ СТАТИЧЕН, АНИМИРУЕТСЯ ТОЛЬКО МАСШТАБ.
  //
  // Раньше тень, обводка и содержимое пересобирались и перерисовывались
  // КАЖДЫЙ кадр драга (Material.elevation + border + child в одном билдере
  // AnimatedBuilder). На слабом GPU размытая тень и обводка, перерисованные
  // 60 раз в секунду, и читались как «при драге подтормаживает».
  //
  // Теперь всё оформление прокси (тень, обводка, карточка) собрано ОДИН раз
  // в [RepaintBoundary] и передано как `child` — AnimatedBuilder на каждом
  // кадре лишь меняет матрицу Transform.scale. Смена матрицы — операция
  // композитора: готовый растр прокси просто переиспользуется, перерисовки
  // нет. Масштаб и скольжение на место идут в одном темпе (easeOut), как и
  // drop-анимация ReorderableListView.
  final proxy = AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final t = Curves.easeOut.transform(animation.value);
      final scale = 1.0 + 0.02 * t;
      return Transform.scale(scale: scale, child: child);
    },
    child: RepaintBoundary(
      child: Material(
        // Высота ФИКСИРОВАНА: анимация elevation заставляла движок
        // пересчитывать тень каждый кадр.
        elevation: 8,
        shadowColor: theme.colorScheme.primary.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(borderRadius),
        color: theme.colorScheme.surface,
        clipBehavior: Clip.none,
        child: Container(
          // Обводка-«кольцо» ПОВЕРХ карточки (не участвует в layout, поэтому
          // текст с мягким переносом не перетекает на другие строки).
          // Постоянная — её анимация стоила перерисовки на каждом кадре.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
              width: 2,
            ),
          ),
          child: child,
        ),
      ),
    ),
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

  /// Порог сообщения о сдвиге, px. Заголовки «расступаются» по Y прокси, и
  /// дёргать их на каждый пиксель незачем: слушатели (ValueListenableBuilder
  /// на каждом заголовке + AnimatedOpacity) пересобираются на КАЖДОМ
  /// уведомлении. Шаг в 4 px снимает большую часть пересборок при драге —
  /// именно это читалось как «драг привычек тормозит».
  static const double _step = 4.0;

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final y = localToGlobal(Offset.zero).dy;
    if (_lastY != null && (y - _lastY!).abs() < _step) return;
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
