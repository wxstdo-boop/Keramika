import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Значок Agysha «зайчик» — СВОЙ векторный глиф, а не шрифтовая иконка.
///
/// Раньше на таблетке и в окне обновления стояли системные иконки
/// (`Icons.system_update_alt`, `Icons.cruelty_free`): они читались чужеродно,
/// а «стрелка обновления» в мелком размере сливалась в пятно. Здесь — простой
/// узнаваемый силуэт: голова с двумя длинными ушами. Геометрия описана
/// нормированно (0…1), поэтому одинаково чётко ложится и на 18 px таблетки,
/// и на 40 px медальона окна.
///
/// Painter статичен: он рисует силуэт один раз, а «дыхание» делает `Transform`
/// над готовым слоем (`RepaintBoundary`), поэтому кадры анимации не
/// растеризуют глиф заново.
class AgyshaBunny extends StatelessWidget {
  const AgyshaBunny({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      isComplex: true,
      willChange: false,
      painter: _BunnyPainter(color),
    ),
  );
}

class _BunnyPainter extends CustomPainter {
  _BunnyPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Силуэт занимает центр окна с небольшим запасом: «дыхание» смещает глиф
    // на считанные пиксели, и он не должен задевать край.
    final s = math.min(w, h) * 0.86;
    final ox = (w - s) / 2;
    final oy = (h - s) / 2;
    Offset p(double x, double y) => Offset(ox + x * s, oy + y * s);

    final ink = Paint()..color = color;

    // Ухо: вытянутый «лепесток» под наклоном. Замкнутый путь из двух
    // квадратичных дуг — силуэт мягкий, а не «палочка».
    void ear(double dx, double tilt, double len) {
      final base = p(0.50 + dx, 0.44);
      final tip = p(0.50 + dx + tilt, 0.44 - len);
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + (tip.dx - base.dx) * 0.12,
          base.dy + (tip.dy - base.dy) * 0.62,
          tip.dx,
          tip.dy,
        )
        ..quadraticBezierTo(
          base.dx + (tip.dx - base.dx) * 0.80,
          base.dy + (tip.dy - base.dy) * 0.92,
          base.dx,
          base.dy,
        )
        ..close();
      canvas.drawPath(path, ink);
    }

    ear(-0.12, -0.06, 0.30);
    ear(0.12, 0.06, 0.30);

    // Голова: круг, посаженный ниже ушей — читается «мордочка».
    canvas.drawCircle(p(0.5, 0.63), s * 0.29, ink);
  }

  @override
  bool shouldRepaint(covariant _BunnyPainter old) => old.color != color;
}
