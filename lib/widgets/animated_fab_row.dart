import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';

import 'section_pill.dart' show sectionCurrentIndex, sectionRailPage;

/// Общая видимость главной таблетки разделов: при прокрутке вниз таблетка
/// вместе со своим белым фоном плавно сворачивается вверх (как кнопки
/// «плюс» и Ада), при долистывании до верха — возвращается.
/// Каждый из четырёх разделов сообщает сюда о своей прокрутке.
final ValueNotifier<bool> sectionPillVisible = ValueNotifier<bool>(true);

/// Target emitted when the active vertical list settles. Home animates the
/// pill to fully expanded/collapsed; null means follow the live scroll offset.
final ValueNotifier<double?> sectionPillSnapTarget = ValueNotifier<double?>(
  null,
);

/// Visual resting position per Home page. It changes only the pill overlay;
/// each page's actual list scroll offset stays intact.
final Map<int, double> sectionPillSnapByPage = <int, double>{};

/// Текущий скролл активного раздела (px от верха). Главная таблетка
/// «уезжает» ПРОПОРЦИОНАЛЬНО прокрутке — листается вместе с контентом,
/// как обычный элемент списка, без отдельной анимации-скачка.
final ValueNotifier<double> sectionScrollOffset = ValueNotifier<double>(0);

/// Последний известный офсет скролла КАЖДОГО раздела (по индексу страницы).
///
/// Список разделов запоминает позицию (keepAlive), но события скролла у
/// неактивной страницы не приходят. Без этой карты при возврате на раздел,
/// оставленный прокрученным, таблетка сбрасывалась в видимое состояние и
/// налезала на контент до первого скролла.
final Map<int, double> sectionOffsetByPage = <int, double>{};

/// Раздел сообщает РЕАЛЬНУЮ позицию своего списка — для таблетки разделов.
///
/// Офсет ВСЕГДА пишется в карту по разделам ([sectionOffsetByPage]): из неё
/// Home считает высоту таблетки для дробной страницы при переезде между
/// разделами.
///
/// В общий [sectionScrollOffset] пишем только когда карусель СТОИТ ровно на
/// этом разделе. Во время переезда (свайп, пружина тапа, тяга камня) высоту
/// ведёт Home интерполяцией между соседними разделами, и жёсткая запись
/// читалась как мигание: таблетка замирала на высоте старого раздела до
/// конца переезда, а на финише скачком переставлялась на новую.
void reportSectionPillOffset(int page, double offset) {
  sectionOffsetByPage[page] = offset;
  if (sectionCurrentIndex.value != page) return;
  // Страница карусели — дробная? Значит идёт переезд: высоту ведёт Home.
  final rail = sectionRailPage.value;
  if (rail.isFinite && (rail - rail.roundToDouble()).abs() > 0.002) return;
  if ((sectionScrollOffset.value - offset).abs() <= 0.5) return;
  sectionScrollOffset.value = offset;
}

/// Плавно прячет/возвращает ряд FAB-кнопок (плюс + Ада) при прокрутке.
///
/// [visible] — слушаемое состояние видимости: скрывается при скролле вниз,
/// возвращается при долистывании до верха. Анимация мягкая (slide + fade),
/// чтобы на слабых телефонах не было рывков.
class AnimatedFabRow extends StatefulWidget {
  final ValueListenable<bool> visible;
  final Widget child;
  const AnimatedFabRow({super.key, required this.visible, required this.child});

  @override
  State<AnimatedFabRow> createState() => _AnimatedFabRowState();
}

class _AnimatedFabRowState extends State<AnimatedFabRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    widget.visible.addListener(_syncVisibility);
    // FAB часто монтируется только после загрузки данных раздела. Явно
    // проигрываем вход и в этом случае, а не показываем его резким кадром.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedFabRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      oldWidget.visible.removeListener(_syncVisibility);
      widget.visible.addListener(_syncVisibility);
    }
    _syncVisibility();
  }

  void _syncVisibility() {
    if (!mounted) return;
    if (widget.visible.value) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    widget.visible.removeListener(_syncVisibility);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return IgnorePointer(
          ignoring: !widget.visible.value,
          child: Opacity(
            opacity: _controller.value,
            child: FractionalTranslation(
              translation: Offset(
                0,
                1.4 * (1 - Curves.easeOutCubic.transform(_controller.value)),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Универсальный слушатель скролла: прячет FAB, когда контент ушёл вниз
/// больше чем на [hideThreshold] пикселей, и возвращает при долистывании
/// до верха (offset <= [showThreshold]).
///
/// Офсет таблетки разделов этим слушателем НЕ пишется: его ведёт
/// персональный ScrollController каждого раздела (см. _syncPillOffset в
/// экранах). Раньше офсет писался из уведомлений скролла, и при пересоздании
/// списка (переключение категории, список↔пусто, свап AnimatedSwitcher)
/// свежий скроллер стоял на 0, а notifier держал старую большую позицию —
/// таблетка «застревала» скрытой при контенте наверху.
class FabScrollListener extends StatelessWidget {
  final ValueNotifier<bool> visible;
  final Widget child;
  final double hideThreshold;
  final double showThreshold;

  const FabScrollListener({
    super.key,
    required this.visible,
    required this.child,
    this.hideThreshold = 48,
    this.showThreshold = 8,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // ТОЛЬКО вертикальный скролл раздела прячет FAB: горизонтальные
        // карусели (плашки борьбы с перфекционизмом, категории задач)
        // не должны сворачивать кнопки.
        if (n.metrics.axis != Axis.vertical) return false;
        // Только внешний слушатель управляет общей таблеткой. Внутренний
        // слушатель раздела по-прежнему отвечает лишь за FAB.
        final controlsSectionPill = identical(visible, sectionPillVisible);
        if (controlsSectionPill && n is ScrollStartNotification) {
          sectionPillSnapByPage.remove(sectionCurrentIndex.value);
          sectionPillSnapTarget.value = null;
        } else if (controlsSectionPill && n is ScrollEndNotification) {
          // На коротком движении оставляем таблетку открытой; при заметной
          // прокрутке мягко убираем её до конца. Обратный скролл к началу
          // заканчивается ровно в раскрытом состоянии.
          sectionPillSnapTarget.value = n.metrics.pixels > 28 ? 64.0 : 0.0;
        }
        final pixels = n.metrics.pixels;
        if (pixels > hideThreshold && visible.value) {
          visible.value = false;
        } else if (pixels <= showThreshold && !visible.value) {
          visible.value = true;
        }
        return false;
      },
      child: child,
    );
  }
}
