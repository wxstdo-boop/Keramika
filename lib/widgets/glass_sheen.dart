import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Бегущий блик по «стеклу» капсулы/карточки: световая полоса входит слева,
/// проходит по диагонали и уходит справа, затем цикл повторяется.
///
/// Цикл построен на косинусе, а не на линейном 0→1 со сбросом: фаза
/// разгоняется и тормозит сама, поэтому на стыке витков нет «прыжка» —
/// анимация выглядит как непрерывное дыхание стекла, а не как мигалка.
///
/// Дёшево для слабого GPU (Adreno 610): перерисовывается только градиент
/// внутри уже существующего ClipRRect (маленькая площадь), без blur и без
/// saveLayer — поэтому блик можно оставлять включённым на статичном экране.
class GlassSheen extends StatefulWidget {
  const GlassSheen({
    super.key,
    this.period = const Duration(milliseconds: 4600),
    this.intensity = 0.20,
    this.bandWidth = 0.34,
    this.tilt = 0.7,
    this.tint = Colors.white,
  });

  /// Полный цикл прохождения блика.
  final Duration period;

  /// Максимальная плотность блика в центре полосы.
  final double intensity;

  /// Ширина световой полосы как доля ширины виджета.
  final double bandWidth;

  /// Наклон полосы (в долях от вертикали кадра).
  final double tilt;

  final Color tint;

  @override
  State<GlassSheen> createState() => _GlassSheenState();
}

class _GlassSheenState extends State<GlassSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            // 0.5 - 0.5·cos(2πt): гладкий старт и финиш внутри каждого
            // витка, значение всегда возвращается к началу без скачка.
            final phase = 0.5 - 0.5 * math.cos(_ctrl.value * 2 * math.pi);
            // Полоса входит за левым краем (x = -1) и уходит за правый
            // (x = +1) — на краях её просто не видно.
            final center = -1.0 + phase * 2.0;
            final half = widget.bandWidth;
            final a = widget.tint.withValues(alpha: 0.0);
            final b = widget.tint.withValues(alpha: widget.intensity);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(center - half, -widget.tilt),
                  end: Alignment(center + half, widget.tilt),
                  colors: [a, b, b, a],
                  stops: const [0.0, 0.42, 0.58, 1.0],
                ),
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

/// Мягкое «дыхание»: контент медленно дрейфует по вертикали туда-обратно.
/// Используется там, где статичная плашка выглядела мёртвой (пустой чат
/// Ады, подсказки). Кривая — easeInOut через синус, поэтому нет ни рывка
/// в крайних точках, ни «пружинки».
class GentleFloat extends StatefulWidget {
  const GentleFloat({
    super.key,
    required this.child,
    this.amplitude = 5,
    this.period = const Duration(milliseconds: 3600),
  });

  final Widget child;
  final double amplitude;
  final Duration period;

  @override
  State<GentleFloat> createState() => _GentleFloatState();
}

class _GentleFloatState extends State<GentleFloat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.period)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        child: widget.child,
        builder: (context, child) => Transform.translate(
          // forward+reverse с easeInOutCubic: на развороте скорость
          // стремится к нулю — движение почти не заметно как «щелчок».
          offset: Offset(
            0,
            -widget.amplitude * Curves.easeInOutCubic.transform(_ctrl.value),
          ),
          child: child,
        ),
      ),
    );
  }
}
