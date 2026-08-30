import 'package:flutter/material.dart';

/// Плавная отдача «вдавливания» для кнопок и значков: при зажатии элемент
/// мягко уменьшается до [pressedScale], при отпускании так же плавно
/// возвращается в исходный размер. То же поведение, что у значков в
/// таблетке разделов — вместо резкого «щелчка» или отсутствия отдачи.
///
/// Обёртка не перехватывает тапы: она только слушает нажатие/отпускание
/// пальца (Listener), а само действие остаётся у вложенной кнопки.
class PressScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final Duration duration;
  final Curve curve;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.985,
    this.duration = const Duration(milliseconds: 240),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent _) {
    if (!_ctrl.isAnimating) _ctrl.forward();
  }

  void _up(PointerUpEvent _) {
    if (_ctrl.value > 0) _ctrl.reverse();
  }

  void _cancel(PointerCancelEvent _) {
    if (_ctrl.value > 0) _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _cancel,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final s = 1.0 + (widget.pressedScale - 1.0) * _anim.value;
          return Transform.scale(scale: s, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
