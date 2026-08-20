import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Плавная отдача карточек: при наведении (desktop/web) и при ЗАЖАТИИ
/// (touch) карточка мягко увеличивается до [hoverScale], при отпускании —
/// так же плавно возвращается. Это та самая «отдача», которая была
/// в приложении раньше и которую просили вернуть.
///
/// ВАЖНО про drag: внутри drag-proxy (ReorderableListView) карточка
/// монтируется заново — [SmoothHover.dragProxyCount] в этот момент > 0,
/// поэтому прокси-копия стартует БЕЗ эффекта (подъём и так даёт сам
/// прокси, двойной масштаб двигал бы текст). Живая карточка в списке
/// при старте перетаскивания слушает счётчик и сбрасывает нажатие, чтобы
/// не «залипала» увеличенной после драга.
class SmoothHover extends StatefulWidget {
  final Widget child;
  final double hoverScale;
  final Duration duration;
  final Curve curve;

  const SmoothHover({
    super.key,
    required this.child,
    // 1.012 вместо 1.02: «вздутие» остаётся ощутимым, но карточка почти
    // не наезжает на соседнюю — раньше на слабом GPU при 2% масштабе
    // значок/край карточки «двоился» с соседней.
    this.hoverScale = 1.012,
    this.duration = const Duration(milliseconds: 180),
    this.curve = Curves.easeOutCubic,
  });

  /// Счётчик активных drag-proxy (см. buildDragProxy). Увеличивается при
  /// монтировании прокси, снимается после кадра.
  static final ValueNotifier<int> dragProxyCount = ValueNotifier<int>(0);

  @override
  State<SmoothHover> createState() => _SmoothHoverState();
}

class _SmoothHoverState extends State<SmoothHover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  bool _inProxy = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 0.0,
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    if (SmoothHover.dragProxyCount.value > 0) {
      // Смонтированы внутри drag-proxy — эффект не нужен вовсе.
      _inProxy = true;
    } else {
      // Живая карточка: при старте перетаскивания (прокси монтируется)
      // сбрасываем зажатие, чтобы после драга карточка не висела
      // увеличенной.
      SmoothHover.dragProxyCount.addListener(_onProxyChanged);
    }
  }

  void _onProxyChanged() {
    if (SmoothHover.dragProxyCount.value > 0 && _ctrl.value > 0.5) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    SmoothHover.dragProxyCount.removeListener(_onProxyChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) => _ctrl.forward();
  void _onExit(PointerExitEvent _) => _ctrl.reverse();
  void _onDown(PointerDownEvent _) => _ctrl.forward();
  void _onUp(PointerUpEvent _) => _ctrl.reverse();
  void _onCancel(PointerCancelEvent _) => _ctrl.reverse();

  @override
  Widget build(BuildContext context) {
    final isTouch =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    if (!isTouch) {
      return MouseRegion(
        onEnter: _onEnter,
        onExit: _onExit,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final s = 1.0 + (widget.hoverScale - 1.0) * _scale.value;
            return Transform.scale(scale: s, child: child);
          },
          child: widget.child,
        ),
      );
    }
    if (_inProxy) {
      // Внутри drag-proxy: подъём даёт сам прокси — здесь без эффекта,
      // чтобы текст не «дышал» двойным масштабом.
      return widget.child;
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onDown,
      onPointerUp: _onUp,
      onPointerCancel: _onCancel,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          final s = 1.0 + (widget.hoverScale - 1.0) * _scale.value;
          return Transform.scale(scale: s, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
