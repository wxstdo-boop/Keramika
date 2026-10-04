import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Кольцо-цель: дуга, показывающая долю «сегодня / норма».
///
/// Рисуется одним кастомным пейнтером и одним твином, без blur, теней и
/// saveLayer: на Adreno 610 размытие стоило бы дороже всего виджета. Дуга
/// стартует с полудня и идёт по часовой стрелке. Перебор нормы помечается
/// вторым слоем поверх той же окружности, а не дугой снаружи, — иначе виджет
/// рос бы в размере при переборе.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.target,
    required this.color,
    required this.trackColor,
    required this.overColor,
    this.size = 96,
    this.thickness = 9,
    this.centerBuilder,
    this.duration = const Duration(milliseconds: 520),
  });

  /// Показанное значение — ккал за сегодня.
  final double value;

  /// Норма, против которой меряется доля.
  final double target;
  final Color color;
  final Color trackColor;

  /// Цвет, когда значения перешли норму.
  final Color overColor;
  final double size;
  final double thickness;

  /// Что лежит в дырке кольца. Строится от ПРОМЕЖУТОЧНОГО значения
  /// анимации, а не от исходного: тогда число внутри кольца крутится
  /// синхронно с дугой, а не перескакивает в тот же кадр.
  final Widget Function(BuildContext context, double shown)? centerBuilder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) => RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              fraction: target <= 0 ? 0 : shown / target,
              shown: shown,
              color: color,
              overColor: overColor,
              trackColor: trackColor,
              thickness: thickness,
            ),
            child: Center(child: centerBuilder?.call(context, shown)),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.shown,
    required this.color,
    required this.overColor,
    required this.trackColor,
    required this.thickness,
  });

  final double fraction;
  final double shown;
  final Color color;
  final Color overColor;
  final Color trackColor;
  final double thickness;

  Paint _stroke(double w, Color col) => Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..color = col;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = (math.min(size.width, size.height) - thickness) / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Дорожка — полная окружность БЕЗ скруглённых концов: на нуле от
    // скруглённой дуги остался бы штрих на полудне.
    canvas.drawCircle(
      c,
      r,
      _stroke(thickness, trackColor)..strokeCap = StrokeCap.butt,
    );
    final f = fraction.clamp(0.0, 1.0);
    if (f > 0.0005) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        f * math.pi * 2,
        false,
        _stroke(thickness, color),
      );
    }
    if (fraction > 1) {
      canvas.drawCircle(c, r, _stroke(thickness * 0.42, overColor));
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.shown != shown ||
      old.fraction != fraction ||
      old.color != color ||
      old.overColor != overColor ||
      old.trackColor != trackColor ||
      old.thickness != thickness;
}
