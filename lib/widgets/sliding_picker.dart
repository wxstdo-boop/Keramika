import 'package:flutter/material.dart';

/// Скользящий выбор «по пунктам»: горизонтальная карусель с центральной
/// привязкой. Свайп влево/вправо плавно переключает пункты; текущий пункт
/// выделен и слегка увеличен, соседние чуть приглушены.
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

  @override
  void didUpdateWidget(covariant SlidingPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _selectedIndex;
    final page = _ctrl.hasClients ? _ctrl.page : null;
    if (!_settling && page != null && (page - target).abs() > 0.01) {
      _ctrl.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: PageView.builder(
        controller: _ctrl,
        itemCount: widget.items.length,
        onPageChanged: (i) {
          if (i >= 0 && i < widget.items.length) {
            _settling = true;
            widget.onChanged(widget.items[i]);
            _settling = false;
          }
        },
        itemBuilder: (context, i) {
          final item = widget.items[i];
          final selected = item == widget.selected;
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (context, child) {
              // Масштаб/прозрачность по мере приближения к центру.
              final pos = _ctrl.hasClients ? (_ctrl.page ?? 0) : 0.0;
              final delta = (i - pos).abs().clamp(0.0, 1.0);
              final scale = 1.0 - 0.12 * delta;
              final opacity = 1.0 - 0.35 * delta;
              return Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: widget.itemBuilder(context, item, selected),
          );
        },
      ),
    );
  }
}
