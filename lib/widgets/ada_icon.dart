import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/haptics.dart';

/// Значок Ады — «искры-светлячок» для шапки секции «Ада» в настройках.
///
/// Свой персонаж вместо общей иконки-компаса: четырёхлучевая искринка
/// в фирменном розовом градиенте (той же палитры, что был у старого
/// кружка) с маленькими глазками — «маленький дух» приложения, сосед
/// канарейки из уголка разработчика, только другое существо.
///
/// В покое почти неподвижна; при тапе плавно «мигает»: подскок,
/// лёгкое покачивание и вспышка свечения под звездой. Повторные тапы,
/// пока анимация жива, игнорируются — никаких пружинных судорог.
class AdaIcon extends StatefulWidget {
  /// Диаметр (ширина = высота = [size]).
  final double size;

  const AdaIcon({super.key, this.size = 34});

  @override
  State<AdaIcon> createState() => _AdaIconState();
}

class _AdaIconState extends State<AdaIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 540),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTap() {
    // Мультитап-защита: пока «мигание» не закончилось, тапы молчат.
    if (_ctrl.isAnimating) return;
    Haptics.light();
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            final t = _ctrl.value;
            final pulse = math.sin(math.pi * t);
            final scale = 1.0 + 0.14 * pulse;
            final wiggle = 0.15 * math.sin(2 * math.pi * t) * (1 - t);
            return Transform.rotate(
              angle: wiggle,
              child: Transform.scale(
                scale: scale,
                child: CustomPaint(
                  size: Size.square(widget.size),
                  painter: _AdaSparkPainter(glow: pulse),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Рисует искринку Ады: мягкое свечение, тело-звезда с вогнутыми бёдрами,
/// глазки с бликами. Всё — чистые заливки без размытий тел (кроме одного
/// подсвеча), чтобы дёшево рендерилось и на слабых Adreno.
class _AdaSparkPainter extends CustomPainter {
  /// 0..1 — фаза «микания»: управляет яркостью свечения.
  final double glow;

  const _AdaSparkPainter({required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Мягкое свечение под звездой (вспыхивает по время «мигания»).
    final glowPaint = Paint()
      ..color = const Color(0xFFE91E63).withValues(alpha: 0.10 + 0.16 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(Offset(c.dx, c.dy + r * 0.10), r * 0.92, glowPaint);

    // Тело-искринка: четыре луча, бёдра вогнуты к центру (quadratic).
    final waist = r * 0.24;
    final body = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + waist, c.dy - waist, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx + waist, c.dy + waist, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - waist, c.dy + waist, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx - waist, c.dy - waist, c.dx, c.dy - r)
      ..close();
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF9DBE), Color(0xFFE91E63)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(body, bodyPaint);

    // Лёгкий блик по верхнему лучу — «жидкость» керамической глазури.
    final sheen = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(c.dx - r * 0.16, c.dy - r * 0.52),
        width: r * 0.22,
        height: r * 0.5,
      ),
      sheen,
    );

    // Глазки: два тёмных овала с белыми бликами.
    final eyePaint = Paint()..color = const Color(0xFF4A1024);
    final eyeR = r * 0.10;
    final eyeY = c.dy - r * 0.02;
    final eyeDX = r * 0.30;
    Rect eyeRect(double dx) => Rect.fromCenter(
      center: Offset(c.dx + dx, eyeY),
      width: eyeR * 1.5,
      height: eyeR * 2.1,
    );
    canvas.drawOval(eyeRect(-eyeDX), eyePaint);
    canvas.drawOval(eyeRect(eyeDX), eyePaint);

    final hiPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    Offset hi(double dx) => Offset(c.dx + dx + eyeR * 0.28, eyeY - eyeR * 0.55);
    canvas.drawCircle(hi(-eyeDX), eyeR * 0.36, hiPaint);
    canvas.drawCircle(hi(eyeDX), eyeR * 0.36, hiPaint);
  }

  @override
  bool shouldRepaint(_AdaSparkPainter oldDelegate) => oldDelegate.glow != glow;
}
