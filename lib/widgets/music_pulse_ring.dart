import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Толстая «хамелеон»-обводка вокруг кнопки проигрывания: цвет медленно
/// перетекает по кругу радуги, а яркость и толщина пульсируют в такт музыке.
///
/// Кольцо живёт ТОЛЬКО когда трек играет ([active]): на паузе оно гаснет до
/// прозрачного, поэтому кнопка не «светится впустую». Пульс — синус от
/// прогресса контроллера, замкнутый на стыке 1→0 (без рывка).
class MusicPulseRing extends StatefulWidget {
  final bool active;
  final Widget child;

  /// Толщина кольца в покое и на пике пульса, px.
  final double baseWidth;
  final double pulseWidth;

  const MusicPulseRing({
    super.key,
    required this.active,
    required this.child,
    this.baseWidth = 2.6,
    this.pulseWidth = 1.6,
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
    final reduce = MotionPrefs.shouldReduceMotion;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        // Пульс 0…1: два «удара» за цикл, оба конца замкнуты.
        final pulse = reduce ? 0.0 : (0.5 + 0.5 * math.sin(t * math.pi * 2));
        final hue = (t * 360) % 360;
        final base = HSLColor.fromAHSL(1, hue, 0.72, 0.58).toColor();
        final glow = base.withValues(alpha: widget.active ? 0.30 + 0.25 * pulse : 0.0);

        return AnimatedOpacity(
          // Кольцо живёт только пока трек играет: на паузе оно плавно гаснет
          // до нуля. Раньше гасли лишь свечение/тень, а сам радужный кант
          // оставался ярким — «светилось впустую» вопреки замыслу.
          opacity: widget.active ? 1.0 : 0.0,
          duration: MotionPrefs.shouldReduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: Container(
            // Толщина кольца ПОСТОЯННА: пульсируют только свечение и цвет.
            // Меняющаяся толщина двигала бы вёрстку строки каждый кадр — это
            // читалось бы как дрожь, а не как дыхание.
            padding: EdgeInsets.all(widget.baseWidth + widget.pulseWidth),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Градиент-«хамелеон»: два соседних тона по кругу радуги.
              gradient: SweepGradient(
                colors: [
                  HSLColor.fromAHSL(1, hue, 0.72, 0.58).toColor(),
                  HSLColor.fromAHSL(1, (hue + 60) % 360, 0.72, 0.60).toColor(),
                  HSLColor.fromAHSL(1, (hue + 180) % 360, 0.72, 0.56).toColor(),
                  HSLColor.fromAHSL(1, hue, 0.72, 0.58).toColor(),
                ],
              ),
              boxShadow: widget.active
                  ? [
                      BoxShadow(
                        color: glow,
                        blurRadius: 12 + 8 * pulse,
                        spreadRadius: 0.5 + 1.5 * pulse,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
