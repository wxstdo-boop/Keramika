import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Значок Agysha — «зайчик». СВОЙ векторный глиф, а не шрифтовая иконка:
/// системные `Icons.cruelty_free`/`Icons.system_update_alt` в мелком размере
/// читались чужеродно, а стрелка сливалась в пятно.
///
/// Силуэт: голова с двумя длинными ушами. Внешний контур — ОДИН замкнутый
/// путь из кубических кривых (мягкие «лепестки» ушей переходят в щёки без
/// стыков), внутренние уши — вложенные акценты. Геометрия нормирована (0…1),
/// поэтому одинаково чётко ложится и на 18 px таблетки, и на 22 px медальона
/// окна: кривые, а не пиксельная сетка, — на любом масштабе остаётся глиф.
///
/// Painter СТАТИЧЕН и никогда не перерисовывается сам: любое движение —
/// это `Transform` над готовым слоем (`RepaintBoundary`), поэтому кадры
/// анимации не растеризуют глиф заново (именно это и «лагало» раньше).
class AgyshaBunny extends StatelessWidget {
  const AgyshaBunny({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
  });

  final double size;
  final Color color;

  /// Тон внутренних ушей. По умолчанию — тот же цвет с мягкой альфой:
  /// «вырез» читается и на светлом, и на тёмном фоне, без второго цвета.
  final Color? innerColor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      isComplex: true,
      willChange: false,
      painter: _BunnyPainter(
        color,
        innerColor ?? color.withValues(alpha: 0.34),
      ),
    ),
  );
}

class _BunnyPainter extends CustomPainter {
  _BunnyPainter(this.color, this.inner);

  final Color color;
  final Color inner;

  /// Нормированная точка 0…1 → точка в окне с полем `pad` по краям.
  static Offset _p(double x, double y, double s, double ox, double oy) =>
      Offset(ox + x * s, oy + y * s);

  @override
  void paint(Canvas canvas, Size size) {
    // Поле по краям: глиф не должен касаться границ окна (иначе на 18 px
    // уши «прилипают» к краю плашки).
    final s = math.min(size.width, size.height) * 0.90;
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    Offset p(double x, double y) => _p(x, y, s, ox, oy);

    // Внешний контур: обходим по часовой стрелке от подбородка.
    final body = Path()
      ..moveTo(p(0.50, 0.93).dx, p(0.50, 0.93).dy)
      // левая щека снизу вверх
      ..cubicTo(
        p(0.31, 0.93).dx,
        p(0.31, 0.93).dy,
        p(0.22, 0.85).dx,
        p(0.22, 0.85).dy,
        p(0.22, 0.73).dx,
        p(0.22, 0.73).dy,
      )
      // к основанию левого уха
      ..cubicTo(
        p(0.22, 0.63).dx,
        p(0.22, 0.63).dy,
        p(0.25, 0.57).dx,
        p(0.25, 0.57).dy,
        p(0.29, 0.50).dx,
        p(0.29, 0.50).dy,
      )
      // наружная кромка левого уха вверх
      ..cubicTo(
        p(0.23, 0.36).dx,
        p(0.23, 0.36).dy,
        p(0.21, 0.22).dx,
        p(0.21, 0.22).dy,
        p(0.28, 0.13).dx,
        p(0.28, 0.13).dy,
      )
      // скругление кончика
      ..cubicTo(
        p(0.30, 0.08).dx,
        p(0.30, 0.08).dy,
        p(0.37, 0.09).dx,
        p(0.37, 0.09).dy,
        p(0.38, 0.15).dx,
        p(0.38, 0.15).dy,
      )
      // внутренняя кромка левого уха вниз, в ложбинку
      ..cubicTo(
        p(0.42, 0.25).dx,
        p(0.42, 0.25).dy,
        p(0.44, 0.37).dx,
        p(0.44, 0.37).dy,
        p(0.46, 0.47).dx,
        p(0.46, 0.47).dy,
      )
      // ложбинка между ушами
      ..lineTo(p(0.54, 0.47).dx, p(0.54, 0.47).dy)
      // внутренняя кромка правого уха вверх
      ..cubicTo(
        p(0.56, 0.37).dx,
        p(0.56, 0.37).dy,
        p(0.58, 0.25).dx,
        p(0.58, 0.25).dy,
        p(0.62, 0.15).dx,
        p(0.62, 0.15).dy,
      )
      // скругление кончика
      ..cubicTo(
        p(0.63, 0.09).dx,
        p(0.63, 0.09).dy,
        p(0.70, 0.08).dx,
        p(0.70, 0.08).dy,
        p(0.72, 0.13).dx,
        p(0.72, 0.13).dy,
      )
      // наружная кромка правого уха вниз
      ..cubicTo(
        p(0.79, 0.22).dx,
        p(0.79, 0.22).dy,
        p(0.77, 0.36).dx,
        p(0.77, 0.36).dy,
        p(0.71, 0.50).dx,
        p(0.71, 0.50).dy,
      )
      // к правой щеке
      ..cubicTo(
        p(0.75, 0.57).dx,
        p(0.75, 0.57).dy,
        p(0.78, 0.63).dx,
        p(0.78, 0.63).dy,
        p(0.78, 0.73).dx,
        p(0.78, 0.73).dy,
      )
      // правая щека к подбородку
      ..cubicTo(
        p(0.78, 0.85).dx,
        p(0.78, 0.85).dy,
        p(0.69, 0.93).dx,
        p(0.69, 0.93).dy,
        p(0.50, 0.93).dx,
        p(0.50, 0.93).dy,
      )
      ..close();

    canvas.drawPath(body, Paint()..color = color);

    // Внутреннее ухо: вытянутый «лепесток», чуть светлее силуэта. Рисуем
    // поверх — получается «вырез», читающийся и на светлом, и на тёмном.
    void innerEar(double dx, double tilt) {
      final path = Path()
        ..moveTo(p(0.335 + dx, 0.45).dx, p(0.335 + dx, 0.45).dy)
        ..cubicTo(
          p(0.305 + dx, 0.35).dx,
          p(0.305 + dx, 0.35).dy,
          p(0.315 + dx + tilt, 0.24).dx,
          p(0.315 + dx + tilt, 0.24).dy,
          p(0.335 + dx + tilt, 0.20).dx,
          p(0.335 + dx + tilt, 0.20).dy,
        )
        ..cubicTo(
          p(0.355 + dx + tilt, 0.17).dx,
          p(0.355 + dx + tilt, 0.17).dy,
          p(0.372 + dx + tilt, 0.22).dx,
          p(0.372 + dx + tilt, 0.22).dy,
          p(0.368 + dx + tilt, 0.28).dx,
          p(0.368 + dx + tilt, 0.28).dy,
        )
        ..cubicTo(
          p(0.362 + dx, 0.36).dx,
          p(0.362 + dx, 0.36).dy,
          p(0.350 + dx, 0.42).dx,
          p(0.350 + dx, 0.42).dy,
          p(0.343 + dx, 0.46).dx,
          p(0.343 + dx, 0.46).dy,
        )
        ..close();
      canvas.drawPath(path, Paint()..color = inner);
    }

    innerEar(0, -0.012);
    // Правое ухо — зеркало левого: та же форма, отражённая по x = 0.5.
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);
    innerEar(0, -0.012);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BunnyPainter old) =>
      old.color != color || old.inner != inner;
}
