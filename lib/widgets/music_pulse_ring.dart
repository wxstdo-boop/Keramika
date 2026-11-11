import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Тонкая «хамелеон»-обводка вокруг кнопки проигрывания: цвета медленно
/// перетекают в тон темы (primary ↔ tertiary), а яркость пульсирует в такт
/// музыке.
///
/// Кольцо — именно ОБВОДКА ([PaintingStyle.stroke]), а не залитый круг:
/// прежний вариант рисовал залитый градиентный контейнер ПОД кнопкой, и
/// вокруг значка был виден плотный «бублик» с квадратом. Теперь по периметру
/// идёт только тонкая линия, а под пальцем нет ни заливки, ни отклика.
///
/// Кольцо живёт ТОЛЬКО когда трек играет ([active]): на паузе гаснет до
/// прозрачного. Сама кнопка (child) при этом НИКОГДА не гаснет.
class MusicPulseRing extends StatefulWidget {
  final bool active;
  final Widget child;

  /// Толщина кольца в покое и на пике пульса, px. Тонкое кольцо — акцент, а
  /// не «бублик» вокруг кнопки.
  final double baseWidth;
  final double pulseWidth;

  const MusicPulseRing({
    super.key,
    required this.active,
    required this.child,
    this.baseWidth = 1.2,
    this.pulseWidth = 0.5,
  });

  @override
  State<MusicPulseRing> createState() => _MusicPulseRingState();
}

class _MusicPulseRingState extends State<MusicPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active && !MotionPrefs.shouldReduceMotion) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant MusicPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !MotionPrefs.shouldReduceMotion) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MotionPrefs.shouldReduceMotion;
    // Цвета — в тон темы, а не радуга: акцент primary → tertiary.
    final a = cs.primary;
    final b = cs.tertiary;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Обводка — отдельный слой ПОД кнопкой, и он не ловит тапы.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.active ? 1.0 : 0.0,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOut,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  // Пульс 0…1: два «удара» за цикл, оба конца замкнуты.
                  final pulse = reduce
                      ? 0.0
                      : (0.5 + 0.5 * math.sin(t * math.pi * 2));
                  final turn = t * 2 * math.pi;
                  final lead = Color.lerp(a, b, 0.5 + 0.5 * math.sin(turn))!;
                  final tail = Color.lerp(b, a, 0.5 + 0.5 * math.cos(turn))!;
                  return CustomPaint(
                    painter: _RingPainter(
                      lead: lead,
                      tail: tail,
                      turn: turn,
                      stroke: widget.baseWidth + widget.pulseWidth * pulse,
                      glow: 0.06 + 0.10 * pulse,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Рисует по периметру ТОЛЬКО тонкую линию: [PaintingStyle.stroke], никакой
/// заливки. Свечение — мягкая копия линии с блюром, чтобы пульс читался, но
/// центр оставался пустым.
class _RingPainter extends CustomPainter {
  final Color lead;
  final Color tail;
  final double turn;
  final double stroke;
  final double glow;

  const _RingPainter({
    required this.lead,
    required this.tail,
    required this.turn,
    required this.stroke,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    if (r <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: r,
    );
    // Прозрачность запекаем в ЦВЕТА градиента, а не в `Paint.color`: при
    // заданном `shader` цвет кисти не применяется.
    Shader sweep(double alpha) => SweepGradient(
      transform: GradientRotation(turn),
      colors: [
        lead.withValues(alpha: alpha),
        tail.withValues(alpha: alpha),
        lead.withValues(alpha: alpha),
      ],
    ).createShader(rect);
    // Мягкое свечение: та же линия с блюром, низкой прозрачностью.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + glow * 10),
    );
    // Сама обводка — тонкая и чёткая.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(0.9),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.lead != lead ||
      old.tail != tail ||
      old.turn != turn ||
      old.stroke != stroke ||
      old.glow != glow;
}
