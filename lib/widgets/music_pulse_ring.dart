import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Тонкая «хамелеон»-обводка вокруг кнопки проигрывания: цвета медленно
/// перетекают в тон темы (primary ↔ tertiary), а яркость пульсирует в такт
/// музыке.
///
/// Кольцо живёт ТОЛЬКО когда трек играет ([active]): на паузе гаснет до
/// прозрачного. Сама кнопка (child) при этом НИКОГДА не гаснет — раньше
/// прозрачность вешалась на всю ячейку вместе с ребёнком, и на старте кнопка
/// «пропадала» (её закрывало погасшее кольцо). Теперь гашение касается только
/// декоративного слоя обводки.
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
    this.baseWidth = 1.7,
    this.pulseWidth = 0.7,
  });

  @override
  State<MusicPulseRing> createState() => _MusicPulseRingState();
}

class _MusicPulseRingState extends State<MusicPulseRing>
    with TickerProviderStateMixin {
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
    // Цвета — в тон темы, а не радуга: акцент primary → tertiary. Полный круг
    // радуги читался как «игрушечная гирлянда» и спорил с палитрой.
    final a = cs.primary;
    final b = cs.tertiary;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Кольцо — ОТДЕЛЬНЫЙ слой ПОД кнопкой: гаснет только оно, ребёнок
        // (кнопка) никогда не становится прозрачным и не «пропадает» на
        // старте.
        AnimatedOpacity(
          opacity: widget.active ? 1.0 : 0.0,
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: Curves.easeOut,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value;
              // Пульс 0…1: два «удара» за цикл, оба конца замкнуты.
              final pulse = reduce
                  ? 0.0
                  : (0.5 + 0.5 * math.sin(t * math.pi * 2));
              // Медленный поворот градиента: цвет «перетекает» по кругу, но в
              // пределах двух тонов темы.
              final turn = t * 2 * math.pi;
              final lead = Color.lerp(a, b, 0.5 + 0.5 * math.sin(turn))!;
              final tail = Color.lerp(b, a, 0.5 + 0.5 * math.cos(turn))!;
              return Container(
                // Толщина кольца постоянна: пульсируют только свечение и цвет.
                padding: EdgeInsets.all(widget.baseWidth + widget.pulseWidth),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: SweepGradient(
                    transform: GradientRotation(turn),
                    colors: [
                      lead.withValues(alpha: 0.85),
                      tail.withValues(alpha: 0.85),
                      lead.withValues(alpha: 0.85),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: a.withValues(alpha: 0.20 + 0.22 * pulse),
                      blurRadius: 10 + 7 * pulse,
                      spreadRadius: 0.2 + 1.1 * pulse,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }
}
