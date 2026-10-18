import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/haptics.dart';

/// Канарейка для уголка разработчика. В покое стоит неподвижно; при тапе
/// плавно машет крылом и слегка «подпрыгивает» на лапках, после чего
/// возвращается в статику. Повторные тапы, пока анимация жива, просто
/// игнорируются — никаких «пружинных судорог» от шквала нажатий.
///
/// Нарисована своим [CustomPainter] — иконки Material «канарейки» нет,
/// а разработчик этого приложения как раз птичник (терапия, привычки,
/// канарейка в уголке — то есть «певчая» подсказка, что внутри скрытые
/// настройки).
class CanaryIcon extends StatefulWidget {
  /// Диаметр (ширина = высота = [size]).
  final double size;

  const CanaryIcon({super.key, this.size = 32});

  @override
  State<CanaryIcon> createState() => _CanaryIconState();
}

class _CanaryIconState extends State<CanaryIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flap() {
    // Защита от многократных тапов: пока машет — новый тап не перезапускает
    // анимацию (forward(from: 0) каждые 20 мс выглядел бы дребезгом).
    if (_ctrl.isAnimating) return;
    Haptics.select();
    _ctrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _flap,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) {
            return CustomPaint(
              size: Size.square(widget.size),
              painter: _CanaryPainter(flap: _ctrl.value),
            );
          },
        ),
      ),
    );
  }
}

/// Птичка разложена в квадрате 0..1 по фигурам-эллипсам и треугольникам:
/// тело, брюшко, голова, хвост двумя перьями, клюв, глаз с бликом и
/// крыло. Анимация — [flap] (0..1): крыло качается по синусу (3 взмаха
/// за прогон: sin(flap * 3π)), вся птичка приподнимается на «прыжке»
/// (midd кадр) и мягко опускается. По краям габарит с запасом 4%.
class _CanaryPainter extends CustomPainter {
  /// Прогресс анимации 0..1; 0 — статичная поза.
  final double flap;

  const _CanaryPainter({required this.flap});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = math.min(size.width, size.height);
    // Крыло машет тремя взмахами: 0 → статику, единица — полный прогон.
    final eased = Curves.easeInOutCubic.transform(flap.clamp(0.0, 1.0));
    final wingAngle = math.sin(eased * math.pi * 3) * 0.55; // рад
    // «Прыжок»: тело с головой приподнимаются на середине прогона.
    final hop = math.sin(eased * math.pi) * s * 0.05;

    final bodyYellow = const Color(0xFFFFD54F);
    final bellyYellow = const Color(0xFFFFE082);
    const wingYellow = Color(0xFFF5A623);
    const beakOrange = Color(0xFFEF8A2C);
    const eyeBrown = Color(0xFF3E2E1B);

    // Лапки: стоят на «земле» и не прыгают вместе с телом — так прыжок
    // читается как отрыв, а не как парение всей графики.
    final feetPaint = Paint()
      ..color = beakOrange.withValues(alpha: 0.9)
      ..strokeWidth = s * 0.032
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(s * 0.60, s * 0.84),
      Offset(s * 0.60, s * 0.93),
      feetPaint,
    );
    canvas.drawLine(
      Offset(s * 0.60, s * 0.93),
      Offset(s * 0.545, s * 0.965),
      feetPaint,
    );
    canvas.drawLine(
      Offset(s * 0.60, s * 0.93),
      Offset(s * 0.655, s * 0.965),
      feetPaint,
    );
    // Вторая лапка чуть сзади — глубина.
    canvas.drawLine(
      Offset(s * 0.76, s * 0.84),
      Offset(s * 0.76, s * 0.915),
      feetPaint,
    );
    canvas.drawLine(
      Offset(s * 0.76, s * 0.915),
      Offset(s * 0.72, s * 0.945),
      feetPaint,
    );

    // Перьевой хвост: два клина вверх-вправо от тела.
    final tailPaint = Paint()..color = wingYellow;
    final tail1 = Path()
      ..moveTo(s * 0.80, s * 0.50 - hop)
      ..lineTo(s * 1.00, s * 0.34 - hop)
      ..lineTo(s * 0.96, s * 0.52 - hop)
      ..close();
    final tail2 = Path()
      ..moveTo(s * 0.80, s * 0.56 - hop)
      ..lineTo(s * 1.02, s * 0.44 - hop)
      ..lineTo(s * 0.96, s * 0.60 - hop)
      ..close();
    canvas.drawPath(tail1, tailPaint);
    canvas.drawPath(tail2, tailPaint);

    // Тело: наклонный эллипс.
    canvas.save();
    canvas.translate(s * 0.62, s * 0.55 - hop);
    canvas.rotate(0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.56, height: s * 0.40),
      Paint()..color = bodyYellow,
    );
    canvas.restore();

    // Брюшко — светлее, чуть ниже и левее центра тела.
    canvas.save();
    canvas.translate(s * 0.58, s * 0.60 - hop);
    canvas.rotate(0.35);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: s * 0.34, height: s * 0.22),
      Paint()..color = bellyYellow,
    );
    canvas.restore();

    // Хохолок: три перышка дугой НАД головой. Система углов канвы: 270° —
    // вверх, поэтому дуга идёт от 240° (вверх-влево) через 300°
    // (вверх-вправо); штрих с круглыми срезами читается как перышки.
    final crestPaint = Paint()
      ..color = wingYellow
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.05;
    canvas.drawArc(
      Rect.fromLTWH(s * 0.34, s * 0.10 - hop, s * 0.18, s * 0.16),
      math.pi * 1.33,
      math.pi * 0.33,
      false,
      crestPaint,
    );

    // Голова: чуть светлее тела.
    canvas.drawCircle(
      Offset(s * 0.38, s * 0.30 - hop),
      s * 0.175,
      Paint()..color = const Color(0xFFFFD965),
    );

    // Клюв: треугольник влево.
    final beak = Path()
      ..moveTo(s * 0.225, s * 0.265 - hop)
      ..lineTo(s * 0.055, s * 0.30 - hop)
      ..lineTo(s * 0.225, s * 0.325 - hop)
      ..close();
    canvas.drawPath(beak, Paint()..color = beakOrange);

    // Глаз с бликом.
    canvas.drawCircle(
      Offset(s * 0.335, s * 0.285 - hop),
      s * 0.036,
      Paint()..color = eyeBrown,
    );
    canvas.drawCircle(
      Offset(s * 0.322, s * 0.272 - hop),
      s * 0.012,
      Paint()..color = Colors.white,
    );

    // Щёчка.
    canvas.drawCircle(
      Offset(s * 0.36, s * 0.345 - hop),
      s * 0.035,
      Paint()..color = bellyYellow,
    );

    // Крыло: качается вокруг точки крепления на левом краю тела.
    canvas.save();
    canvas.translate(s * 0.50, s * 0.52 - hop);
    canvas.rotate(wingAngle);
    canvas.drawOval(
      Rect.fromLTWH(s * 0.02, s * -0.045, s * 0.42, s * 0.20),
      Paint()..color = wingYellow,
    );
    // Контурная линия крыла — намёк на перья.
    final featherPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = s * 0.022
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(s * 0.10, s * -0.01),
      Offset(s * 0.34, s * -0.01),
      featherPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CanaryPainter oldDelegate) =>
      oldDelegate.flap != flap;
}
