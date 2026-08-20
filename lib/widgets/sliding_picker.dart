import 'dart:async';

import 'package:flutter/material.dart';

/// Скользящий выбор «по пунктам»: горизонтальная карусель с центральной
/// привязкой. Свайп влево/вправо плавно переключает пункты; текущий пункт
/// выделен и слегка увеличен, соседние чуть приглушены.
///
/// Применение пункта:
/// - тап по пункту — применяется СРАЗУ (явное намерение), карусель плавно
///   подъезжает к нему;
/// - свайп — применяется, когда карусель ДЕЙСТВИТЕЛЬНО встала:
///   * ScrollEndNotification от баллистики «прилипания» (dragDetails == null)
///     — карусель остановилась: применяем через 40 мс;
///   * ScrollEndNotification от отпускания пальца (dragDetails != null) —
///     дальше может поехать баллистика: применяем через 120 мс, НО любой
///     новый скролл-тик отменяет это применение и ждёт финальной остановки.
///   Так быстрый флип через несколько пунктов применяет только финальный,
///   а «доезжающая» карусель не применяет промежуточные.
class SlidingPicker<T> extends StatefulWidget {
  final List<T> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget Function(BuildContext context, T item, bool selected)
  itemBuilder;
  final double viewportFraction;
  final double height;

  const SlidingPicker({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.itemBuilder,
    this.viewportFraction = 0.6,
    this.height = 68,
  });

  @override
  State<SlidingPicker<T>> createState() => _SlidingPickerState<T>();
}

class _SlidingPickerState<T> extends State<SlidingPicker<T>> {
  late final PageController _ctrl = PageController(
    viewportFraction: widget.viewportFraction,
  );
  // Свайп пользователя уже движет карусель — не дёргаем контроллер в ответ.
  bool _settling = false;
  // Палец сейчас ведёт карусель (dragDetails != null): в этом случае
  // didUpdateWidget не «дёргает» контроллер к выбранному пункту — иначе
  // живое применение во время драга конфликтовало бы с пальцем.
  bool _userDragging = false;
  Timer? _applyTimer;

  int get _selectedIndex {
    final i = widget.items.indexOf(widget.selected);
    return i < 0 ? 0 : i;
  }

  @override
  void initState() {
    super.initState();
    // При открытии экрана карусель стартует на ВЫБРАННОМ пункте, а не на
    // первом — иначе обводка выбранного звука «сбрасывается» при перезаходе.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      final target = _selectedIndex;
      if (target > 0) {
        _settling = true;
        _ctrl.jumpToPage(target);
        _settling = false;
      }
    });
  }

  /// Тап по пункту: применяем сразу (пользователь явно выбрал), карусель
  /// плавно подъезжает к нему через didUpdateWidget.
  void _selectPage(int i) {
    _applyTimer?.cancel();
    _applyTimer = null;
    final item = widget.items[i];
    if (item == widget.selected) return;
    widget.onChanged(item);
  }

  /// Карусель закончила движение (отпускание пальца или конец баллистики).
  void _onScrollEnd({required bool ballisticEnd}) {
    _applyTimer?.cancel();
    _applyTimer = Timer(
      // Баллистика встала — применяем сразу; отпускание — совсем короткая
      // пауза (тики начинающейся баллистики всё равно отменят применение),
      // чтобы переключение не ощущалось «с задержкой фона».
      ballisticEnd
          ? const Duration(milliseconds: 0)
          : const Duration(milliseconds: 20),
      _applySettledPage,
    );
  }

  /// Карусель снова движется — отменяем отложенное применение: промежуточные
  /// позиции при флипе не должны применяться.
  void _cancelPendingApply() {
    _applyTimer?.cancel();
    _applyTimer = null;
  }

  /// Применяет пункт, на котором карусель стоит СЕЙЧАС (с дедупом).
  void _applySettledPage() {
    _applyTimer = null;
    if (!mounted || !_ctrl.hasClients) return;
    final page = _ctrl.page;
    if (page == null) return;
    final j = page.round().clamp(0, widget.items.length - 1);
    final item = widget.items[j];
    if (item == widget.selected) return;
    widget.onChanged(item);
  }

  /// Живое применение во время перетаскивания пальцем: пункт, к которому
  /// карусель привязана прямо сейчас (центр), применяется сразу же —
  /// список переключается без «задержки фона». Дедуп по widget.selected:
  /// onChanged срабатывает только при реальной смене пункта.
  void _applyLivePage() {
    _applyTimer?.cancel();
    _applyTimer = null;
    if (!mounted || !_ctrl.hasClients) return;
    final page = _ctrl.page;
    if (page == null) return;
    final j = page.round().clamp(0, widget.items.length - 1);
    final item = widget.items[j];
    if (item == widget.selected) return;
    widget.onChanged(item);
  }

  @override
  void didUpdateWidget(covariant SlidingPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _selectedIndex;
    final page = _ctrl.hasClients ? _ctrl.page : null;
    // Пока палец ведёт карусель — не дёргаем контроллер: применённый
    // (живой) пункт совпадёт с позицией карусели, когда палец отпустят.
    if (!_settling &&
        !_userDragging &&
        page != null &&
        (page - target).abs() > 0.01) {
      _ctrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _applyTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _userDragging = notification.dragDetails != null;
            _cancelPendingApply();
          } else if (notification is ScrollUpdateNotification) {
            if (notification.dragDetails != null) {
              // Палец ведёт карусель: применяем пункт, к которому она
              // привязана ПРЯМО СЕЙЧАС (середина перехода) — список задач
              // переключается сразу, без ожидания, пока карусель встанет.
              // Дедуп в _applyLivePage не даёт спамить onChanged на каждый
              // тик скролла — применяется только при смене пункта.
              _userDragging = true;
              _applyLivePage();
            } else {
              // Баллистика (флип) — промежуточные пункты не применяем,
              // только финальный, когда карусель остановится.
              _cancelPendingApply();
            }
          } else if (notification is ScrollEndNotification) {
            _userDragging = false;
            // dragDetails != null — ScrollEnd от отпускания пальца (дальше
            // может поехать баллистика); null — баллистика встала на место.
            _onScrollEnd(ballisticEnd: notification.dragDetails == null);
          }
          return false;
        },
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.items.length,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectPage(i),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  // Масштаб/прозрачность по мере приближения к центру.
                  final pos = _ctrl.hasClients ? (_ctrl.page ?? 0) : 0.0;
                  final delta = (i - pos).abs().clamp(0.0, 1.0);
                  final scale = 1.0 - 0.12 * delta;
                  final opacity = 1.0 - 0.35 * delta;
                  // ЖИВАЯ подсветка: пункт, к которому карусель привязана
                  // прямо сейчас (центр), подсвечивается СРАЗУ во время
                  // скролла — «фон» переключается без задержки, не дожидаясь
                  // фиксации выбора.
                  final liveSelected = (i - pos).abs() < 0.5;
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: widget.itemBuilder(context, item, liveSelected),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
