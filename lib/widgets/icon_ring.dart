import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Круглая «конусная» градиентная обводка вокруг иконки: кольцо с
/// sweep-градиентом (переливается по кругу), мягко прилегает к иконке и
/// подсвечивается лёгким свечением. Не меняет layout по-крупному —
/// оборачивает иконку с небольшим отступом.
class IconRing extends StatelessWidget {
  const IconRing({
    super.key,
    required this.child,
    required this.colors,
    this.size = 32,
    this.thickness = 2.5,
    this.inset = 4,
    this.glow = true,
  });

  /// Дитя (иконка в круге), обычно 32×32.
  final Widget child;

  /// Цвета для sweep-градиента (переливание по кругу).
  final List<Color> colors;

  /// Размер самого контента (иконки).
  final double size;

  /// Толщина кольца.
  final double thickness;

  /// Зазор между иконкой и кольцом.
  final double inset;

  /// Подсвечивать ли кольцо мягким свечением.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final boxSize = size + inset * 2;
    return SizedBox(
      width: boxSize,
      height: boxSize,
      child: CustomPaint(
        painter: _RingPainter(
          colors: colors,
          thickness: thickness,
          glow: glow,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.colors,
    required this.thickness,
    required this.glow,
  });

  final List<Color> colors;
  final double thickness;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = cx - thickness / 2;

    // Мягкое свечение под кольцом (если включено).
    if (glow && colors.isNotEmpty) {
      final glowPaint = Paint()
        ..color = colors.first.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(Offset(cx, cy), radius, glowPaint);
    }

    // Конусный (sweep) градиент переливается по кругу — красивый эффект
    // «перелив» по дуге. ui.Gradient.sweep принимает Offset center.
    final shader = ui.Gradient.sweep(
      Offset(cx, cy),
      <Color>[...colors, colors.first],
    );

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..shader = shader;
    canvas.drawCircle(Offset(cx, cy), radius, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.colors != colors || old.thickness != thickness;
}
