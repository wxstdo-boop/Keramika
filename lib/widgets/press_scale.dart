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

  /// Сколько длится вдавливание.
  final Duration duration;

  /// Сколько длится возврат. Отдельно от [duration]: «уйти» под палец
  /// хочется быстро и послушно, а вернуться — заметно мягче, иначе отпускание
  /// читается как щелчок. `null` — тот же [duration], как было раньше.
  final Duration? releaseDuration;

  final Curve curve;

  /// Отключённое «вдавливание» (например, когда палец ушёл на перетаскивание
  /// родителя): нажатие не учитывается, элемент мягко возвращается в размер.
  final bool enabled;

  const PressScale({
    super.key,
    required this.child,
    this.pressedScale = 0.985,
    this.duration = const Duration(milliseconds: 280),
    this.releaseDuration,
    this.curve = Curves.easeOutCubic,
    this.enabled = true,
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
  void didUpdateWidget(covariant PressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _ctrl.value > 0) _ctrl.reverse();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Проверка `mounted` обязательна: при быстром смахивании элемент успевает
  // размонтироваться до pointer-up, и `reverse()` на уничтоженном
  // контроллере ронял диспетчер жестов (флин в пикере это ловил).
  void _down(PointerDownEvent _) {
    if (!mounted || !widget.enabled) return;
    // Длительность переключаем ДО старта: контроллер живёт один, и без этого
    // после первого же нажатия он запомнил бы длину отпускания.
    _ctrl.duration = widget.duration;
    _ctrl.forward();
  }

  void _up(PointerUpEvent _) {
    if (!mounted || _ctrl.value <= 0) return;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
  }

  void _cancel(PointerCancelEvent _) {
    if (!mounted || _ctrl.value <= 0) return;
    _ctrl.duration = widget.releaseDuration ?? widget.duration;
    _ctrl.reverse();
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
