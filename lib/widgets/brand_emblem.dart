import 'package:flutter/material.dart';

/// Векторная эмблема Keramika — колба-ваза.
///
/// Рисуется CustomPaint'ом, а не берётся из `assets/keramika.png`: растровый
/// логотип на 20–26 px — это размытое пятно (PNG тянется вниз с потерей
/// деталей), а вектор остаётся бритвенно-чётким на любой плотности экрана.
/// Форма намеренно простая: горлышко, пузо, основание — читается как керамика
/// даже в 20 пикселей.
class BrandEmblem extends StatelessWidget {
  final double size;
  final Color color;

  const BrandEmblem({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _EmblemPainter(color: color),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  final Color color;

  _EmblemPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double x(double u) => u * s;
    double y(double v) => v * s;
    // Все точки заданы в единичном квадрате, поэтому пропорции вазы
    // не зависят от размера. Обход по часовой: горлышко → правый бок →
    // основание → левый бок.
    final body = Path()
      ..moveTo(x(0.355), y(0.205))
      ..lineTo(x(0.645), y(0.205))
      ..cubicTo(x(0.655), y(0.33), x(0.845), y(0.43), x(0.845), y(0.575))
      ..cubicTo(x(0.845), y(0.75), x(0.71), y(0.86), x(0.615), y(0.895))
      ..lineTo(x(0.385), y(0.895))
      ..cubicTo(x(0.29), y(0.86), x(0.155), y(0.75), x(0.155), y(0.575))
      ..cubicTo(x(0.155), y(0.43), x(0.345), y(0.33), x(0.355), y(0.205))
      ..close();

    canvas.drawPath(
      body,
      Paint()
        ..isAntiAlias = true
        // Объём: светлее слева-сверху, темнее справа-снизу.
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.30)!,
            color,
            Color.lerp(color, Colors.black, 0.34)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Offset.zero & size),
    );
    final mouth = Rect.fromLTWH(x(0.355), y(0.148), x(0.29), s * 0.115);
    // Горлышко: тёмный овал-отверстие, иначе ваза читается как клякса.
    canvas.drawOval(
      mouth,
      Paint()
        ..isAntiAlias = true
        ..color = Color.lerp(
          color,
          Colors.black,
          0.45,
        )!.withValues(alpha: 0.92),
    );
    // Ободок тонкой светлой линией — край ловит свет.
    canvas.drawOval(
      mouth,
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = (s * 0.048).clamp(0.8, 1.8)
        ..color = Color.lerp(color, Colors.white, 0.55)!,
    );
    // Глазурь: короткий блик по левой границе пуза.
    canvas.drawPath(
      Path()
        ..moveTo(x(0.275), y(0.455))
        ..cubicTo(x(0.215), y(0.53), x(0.215), y(0.64), x(0.26), y(0.72)),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = (s * 0.075).clamp(1.0, 2.6)
        ..color = Colors.white.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter oldDelegate) =>
      oldDelegate.color != color;
}
