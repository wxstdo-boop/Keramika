import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// «Белка в колесе» — живой, стильный и ультра-плавный значок обновления:
/// колесо непрерывно и плавно вращается на GPU, а белочка бежит внутри него.
///
/// Архитектура без лагов:
/// - Колесо и силуэт белки кэшируются через [RepaintBoundary].
/// - Вращение колеса осуществляется через [Transform.rotate], исключая
///   покадровую пересборку векторных путей.
/// - Вектор белки отрисован единым сглаженным контуром, четко читаемым
///   как при компактном размере (18x18 в таблетке), так и в модальном окне (40x40).
/// - Учитывает системную настройку [MotionPrefs.shouldReduceMotion].
class SquirrelWheel extends StatefulWidget {
  const SquirrelWheel({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
    this.enter,
    this.period = const Duration(milliseconds: 2800),
  });

  /// Вписанный квадрат значка, px.
  final double size;

  /// Основной цвет белки и акцентов колеса.
  final Color color;

  /// Цвет обода и спиц колеса (по умолчанию полупрозрачный от [color]).
  final Color? innerColor;

  /// Разовый вход (плавное появление и масштабирование).
  final Animation<double>? enter;

  /// Период одного полного оборота колеса.
  final Duration period;

  @override
  State<SquirrelWheel> createState() => _SquirrelWheelState();
}

class _SquirrelWheelState extends State<SquirrelWheel>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = ambientRepeat(
      AnimationController(vsync: this, duration: widget.period),
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color;
    final inner = widget.innerColor ?? color.withValues(alpha: 0.45);
    final reduceMotion = MotionPrefs.shouldReduceMotion;
    final entered = reduceMotion || widget.enter == null
        ? 1.0
        : widget.enter!.value.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: Opacity(
        opacity: entered,
        child: Transform.scale(
          scale: 0.88 + 0.12 * entered,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Вращающееся колесо (задний слой)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => Transform.rotate(
                      angle: reduceMotion ? 0.0 : _spin.value * 2 * math.pi,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: Size(widget.size, widget.size),
                          isComplex: true,
                          willChange: false,
                          painter: _WheelPainter(
                            wheelColor: inner,
                            accentColor: color.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Бегущая белочка внутри колеса (с мягким легким покачиванием в такт)
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final bob = reduceMotion
                          ? 0.0
                          : math.sin(_spin.value * 4 * math.pi) * (widget.size * 0.025);
                      return Transform.translate(
                        offset: Offset(0, bob),
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: Size(widget.size, widget.size),
                            isComplex: true,
                            willChange: false,
                            painter: _SquirrelPainter(color: color),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Элегантное беговое колесо: внешний обод, внутренний трек и 4 спицы-турбины
class _WheelPainter extends CustomPainter {
  final Color wheelColor;
  final Color accentColor;

  _WheelPainter({
    required this.wheelColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = s * 0.46;
    final innerRadius = s * 0.40;

    // Внешний обод
    final outerPaint = Paint()
      ..color = wheelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.065
      ..isAntiAlias = true;
    canvas.drawCircle(center, outerRadius, outerPaint);

    // Внутренний тонкий обод
    final innerPaint = Paint()
      ..color = wheelColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.03
      ..isAntiAlias = true;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // 4 изогнутые аэродинамические спицы (симметрия 90° для плавности)
    final spokePaint = Paint()
      ..color = wheelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var i = 0; i < 4; i++) {
      final angle = i * (math.pi / 2);
      final pEnd = center + Offset(math.cos(angle), math.sin(angle)) * (innerRadius - s * 0.02);
      final pMid = center +
          Offset(
            math.cos(angle + 0.35) * (innerRadius * 0.55),
            math.sin(angle + 0.35) * (innerRadius * 0.55),
          );
      final spokePath = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(pMid.dx, pMid.dy, pEnd.dx, pEnd.dy);
      canvas.drawPath(spokePath, spokePaint);
    }

    // Центральная ступица (ось колеса)
    final hubPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(center, s * 0.075, hubPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.wheelColor != wheelColor || old.accentColor != accentColor;
}

/// Идеально выверенный векторный силуэт бегущей белочки в профиль
class _SquirrelPainter extends CustomPainter {
  final Color color;

  _SquirrelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;

    Offset pt(double x, double y) => Offset(ox + x * s, oy + y * s);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Пушистый хвост дугой вперед над спинкой
    final tailPath = Path()
      ..moveTo(pt(0.36, 0.60).dx, pt(0.36, 0.60).dy)
      ..cubicTo(
        pt(0.20, 0.58).dx, pt(0.20, 0.58).dy,
        pt(0.18, 0.36).dx, pt(0.18, 0.36).dy,
        pt(0.28, 0.26).dx, pt(0.28, 0.26).dy,
      )
      ..cubicTo(
        pt(0.35, 0.19).dx, pt(0.35, 0.19).dy,
        pt(0.48, 0.22).dx, pt(0.48, 0.22).dy,
        pt(0.48, 0.33).dx, pt(0.48, 0.33).dy,
      )
      ..cubicTo(
        pt(0.48, 0.42).dx, pt(0.48, 0.42).dy,
        pt(0.34, 0.38).dx, pt(0.34, 0.38).dy,
        pt(0.32, 0.46).dx, pt(0.32, 0.46).dy,
      )
      ..cubicTo(
        pt(0.30, 0.52).dx, pt(0.30, 0.52).dy,
        pt(0.36, 0.56).dx, pt(0.36, 0.56).dy,
        pt(0.40, 0.58).dx, pt(0.40, 0.58).dy,
      )
      ..close();
    canvas.drawPath(tailPath, fillPaint);

    // Тело бегущей белки (стремительный наклон вперед к бегу)
    final bodyPath = Path()
      ..moveTo(pt(0.36, 0.62).dx, pt(0.36, 0.62).dy)
      ..cubicTo(
        pt(0.42, 0.54).dx, pt(0.42, 0.54).dy,
        pt(0.52, 0.50).dx, pt(0.52, 0.50).dy,
        pt(0.60, 0.48).dx, pt(0.60, 0.48).dy,
      )
      // Голова с ушком
      ..cubicTo(
        pt(0.68, 0.44).dx, pt(0.68, 0.44).dy,
        pt(0.72, 0.36).dx, pt(0.72, 0.36).dy,
        pt(0.70, 0.32).dx, pt(0.70, 0.32).dy,
      )
      // Кончик ушка и мордочка вперед
      ..lineTo(pt(0.72, 0.38).dx, pt(0.72, 0.38).dy)
      ..cubicTo(
        pt(0.77, 0.44).dx, pt(0.77, 0.44).dy,
        pt(0.76, 0.52).dx, pt(0.76, 0.52).dy,
        pt(0.70, 0.55).dx, pt(0.70, 0.55).dy,
      )
      // Передняя лапка вытянута вперед в беге
      ..lineTo(pt(0.68, 0.65).dx, pt(0.68, 0.65).dy)
      ..lineTo(pt(0.64, 0.64).dx, pt(0.64, 0.64).dy)
      ..lineTo(pt(0.62, 0.58).dx, pt(0.62, 0.58).dy)
      // Животик
      ..cubicTo(
        pt(0.54, 0.63).dx, pt(0.54, 0.63).dy,
        pt(0.46, 0.66).dx, pt(0.46, 0.66).dy,
        pt(0.38, 0.67).dx, pt(0.38, 0.67).dy,
      )
      // Задняя лапка отталкивается от колеса
      ..lineTo(pt(0.35, 0.72).dx, pt(0.35, 0.72).dy)
      ..lineTo(pt(0.31, 0.70).dx, pt(0.31, 0.70).dy)
      ..lineTo(pt(0.34, 0.64).dx, pt(0.34, 0.64).dy)
      ..close();
    canvas.drawPath(bodyPath, fillPaint);

    // Маленький сияющий глазок
    final eyePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    canvas.drawCircle(pt(0.68, 0.46), s * 0.022, eyePaint);
  }

  @override
  bool shouldRepaint(covariant _SquirrelPainter old) => old.color != color;
}
