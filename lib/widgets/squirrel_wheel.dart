import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// «Белка в колесе» / «Бегущий хомяк» — живой, контрастный и ультра-плавный значок
/// обновления: колесо со спицами и ступеньками плавно вращается на GPU, а пухлый
/// золотистый хомячок с выразительными щёчками и ушками бежит внутри него.
///
/// Чётко читается на любых темах (включая тёмную OLED/Cyberpunk) и при любых размерах
/// (от 18x18 в таблетке до 40x40 в окне обновления).
class SquirrelWheel extends StatefulWidget {
  const SquirrelWheel({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
    this.enter,
    this.period = const Duration(milliseconds: 2400),
  });

  /// Вписанный квадрат значка, px.
  final double size;

  /// Основной цвет (используется как ориентир акцента).
  final Color color;

  /// Цвет обода и спиц колеса.
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MotionPrefs.shouldReduceMotion;
    final entered = reduceMotion || widget.enter == null
        ? 1.0
        : widget.enter!.value.clamp(0.0, 1.0);

    // Высококонтрастные цвета для идеальной читаемости на тёмной и светлой темах
    final wheelRim = widget.innerColor ??
        (dark
            ? const Color(0xFFE2E8F0).withValues(alpha: 0.85)
            : const Color(0xFF334155).withValues(alpha: 0.80));
    final wheelSpokes = dark
        ? const Color(0xFF94A3B8).withValues(alpha: 0.55)
        : const Color(0xFF64748B).withValues(alpha: 0.45);
    final hubColor = dark ? const Color(0xFFF43F5E) : const Color(0xFFE11D48);

    final furColor = dark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final bellyColor = dark ? const Color(0xFFFFFBEB) : const Color(0xFFFEF3C7);
    final earColor = dark ? const Color(0xFFFDA4AF) : const Color(0xFFF43F5E);

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
                // 1. Вращающееся колесо (обод, перекладины-ступеньки и спицы)
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
                            rimColor: wheelRim,
                            spokeColor: wheelSpokes,
                            hubColor: hubColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Бегущий хомяк внутри колеса с задорным перебором лапок
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final scamper = reduceMotion
                          ? 0.0
                          : math.sin(_spin.value * 8 * math.pi);
                      final bobY = scamper * (widget.size * 0.035);
                      final tilt = scamper * 0.04;
                      return Transform.translate(
                        offset: Offset(0, bobY),
                        child: Transform.rotate(
                          angle: tilt,
                          child: RepaintBoundary(
                            child: CustomPaint(
                              size: Size(widget.size, widget.size),
                              isComplex: true,
                              willChange: false,
                              painter: _HamsterPainter(
                                furColor: furColor,
                                bellyColor: bellyColor,
                                earColor: earColor,
                                stepPhase: reduceMotion ? 0.0 : _spin.value,
                              ),
                            ),
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

/// Высококонтрастное колесо с наружным ободом, ступеньками и спицами турбины
class _WheelPainter extends CustomPainter {
  final Color rimColor;
  final Color spokeColor;
  final Color hubColor;

  static final Paint _rimPaint = Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true;

  static final Paint _spokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  static final Paint _hubPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  _WheelPainter({
    required this.rimColor,
    required this.spokeColor,
    required this.hubColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = s * 0.46;
    final innerR = s * 0.38;

    // Внешний яркий обод
    _rimPaint.color = rimColor;
    _rimPaint.strokeWidth = s * 0.065;
    canvas.drawCircle(center, outerR, _rimPaint);

    // Внутренний обод
    _rimPaint.color = spokeColor;
    _rimPaint.strokeWidth = s * 0.025;
    canvas.drawCircle(center, innerR, _rimPaint);

    // 4 изогнутые аэродинамические спицы турбины
    _spokePaint.color = spokeColor;
    _spokePaint.strokeWidth = s * 0.045;
    for (var i = 0; i < 4; i++) {
      final angle = i * (math.pi / 2);
      final pEnd = center + Offset(math.cos(angle), math.sin(angle)) * innerR;
      final pMid = center +
          Offset(
            math.cos(angle + 0.36) * (innerR * 0.55),
            math.sin(angle + 0.36) * (innerR * 0.55),
          );
      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..quadraticBezierTo(pMid.dx, pMid.dy, pEnd.dx, pEnd.dy);
      canvas.drawPath(path, _spokePaint);
    }

    // 8 радиальных перекладин-ступенек между ободами
    _spokePaint.strokeWidth = s * 0.035;
    for (var i = 0; i < 8; i++) {
      final a = i * (math.pi / 4);
      final p1 = center + Offset(math.cos(a), math.sin(a)) * innerR;
      final p2 = center + Offset(math.cos(a), math.sin(a)) * outerR;
      canvas.drawLine(p1, p2, _spokePaint);
    }

    // Центральная ступица (ось колеса)
    _hubPaint.color = hubColor;
    canvas.drawCircle(center, s * 0.075, _hubPaint);

    _hubPaint.color = Colors.white.withValues(alpha: 0.90);
    canvas.drawCircle(center, s * 0.025, _hubPaint);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.rimColor != rimColor ||
      old.spokeColor != spokeColor ||
      old.hubColor != hubColor;
}

/// Выверенный векторный силуэт бегущего хомячка: круглые пухлые щёчки,
/// торчащие ушки, маленькие лапки и блестящий глазик.
class _HamsterPainter extends CustomPainter {
  final Color furColor;
  final Color bellyColor;
  final Color earColor;
  final double stepPhase;

  static final Paint _fillPaint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  _HamsterPainter({
    required this.furColor,
    required this.bellyColor,
    required this.earColor,
    required this.stepPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;

    Offset pt(double x, double y) => Offset(ox + x * s, oy + y * s);

    // 1. Тело хомяка (пухлый, округлый силуэт с наклоном вперёд)
    _fillPaint.color = furColor;
    final bodyPath = Path()
      // Попа и хвостик
      ..moveTo(pt(0.32, 0.67).dx, pt(0.32, 0.67).dy)
      ..cubicTo(
        pt(0.24, 0.64).dx, pt(0.24, 0.64).dy,
        pt(0.24, 0.50).dx, pt(0.24, 0.50).dy,
        pt(0.33, 0.44).dx, pt(0.33, 0.44).dy,
      )
      // Округлая спинка
      ..cubicTo(
        pt(0.40, 0.38).dx, pt(0.40, 0.38).dy,
        pt(0.50, 0.38).dx, pt(0.50, 0.38).dy,
        pt(0.58, 0.41).dx, pt(0.58, 0.41).dy,
      )
      // Затылок к ушку
      ..lineTo(pt(0.60, 0.37).dx, pt(0.60, 0.37).dy)
      // Мордочка и носик
      ..cubicTo(
        pt(0.68, 0.39).dx, pt(0.68, 0.39).dy,
        pt(0.74, 0.44).dx, pt(0.74, 0.44).dy,
        pt(0.75, 0.49).dx, pt(0.75, 0.49).dy,
      )
      // Пухлая щёчка хомяка
      ..cubicTo(
        pt(0.74, 0.58).dx, pt(0.74, 0.58).dy,
        pt(0.67, 0.63).dx, pt(0.67, 0.63).dy,
        pt(0.60, 0.63).dx, pt(0.60, 0.63).dy,
      )
      // Животик
      ..cubicTo(
        pt(0.52, 0.66).dx, pt(0.52, 0.66).dy,
        pt(0.42, 0.68).dx, pt(0.42, 0.68).dy,
        pt(0.35, 0.68).dx, pt(0.35, 0.68).dy,
      )
      ..close();
    canvas.drawPath(bodyPath, _fillPaint);

    // 2. Светлое брюшко и щёчка (добавляет объем и контраст)
    _fillPaint.color = bellyColor;
    final bellyPath = Path()
      ..moveTo(pt(0.44, 0.66).dx, pt(0.44, 0.66).dy)
      ..cubicTo(
        pt(0.52, 0.64).dx, pt(0.52, 0.64).dy,
        pt(0.64, 0.61).dx, pt(0.64, 0.61).dy,
        pt(0.69, 0.54).dx, pt(0.69, 0.54).dy,
      )
      ..cubicTo(
        pt(0.65, 0.50).dx, pt(0.65, 0.50).dy,
        pt(0.56, 0.54).dx, pt(0.56, 0.54).dy,
        pt(0.48, 0.60).dx, pt(0.48, 0.60).dy,
      )
      ..close();
    canvas.drawPath(bellyPath, _fillPaint);

    // 3. Круглое ушко с розовой сердцевинкой
    _fillPaint.color = furColor;
    canvas.drawOval(
      Rect.fromCenter(center: pt(0.58, 0.36), width: s * 0.08, height: s * 0.11),
      _fillPaint,
    );
    _fillPaint.color = earColor;
    canvas.drawOval(
      Rect.fromCenter(center: pt(0.58, 0.36), width: s * 0.045, height: s * 0.07),
      _fillPaint,
    );

    // 4. Лапки в беге (передняя тянется вперед, задняя отталкивается)
    final legSwing = math.sin(stepPhase * 8 * math.pi);
    _fillPaint.color = earColor;
    // Передняя лапка
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pt(0.65 + 0.03 * legSwing, 0.66),
          width: s * 0.07,
          height: s * 0.04,
        ),
        Radius.circular(s * 0.02),
      ),
      _fillPaint,
    );
    // Задняя лапка
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: pt(0.33 - 0.03 * legSwing, 0.69),
          width: s * 0.08,
          height: s * 0.04,
        ),
        Radius.circular(s * 0.02),
      ),
      _fillPaint,
    );

    // 5. Выразительный сияющий глазик
    _fillPaint.color = const Color(0xFF1E1B18);
    canvas.drawCircle(pt(0.65, 0.44), s * 0.026, _fillPaint);
    _fillPaint.color = Colors.white;
    canvas.drawCircle(pt(0.642, 0.432), s * 0.010, _fillPaint);

    // 6. Крошечный розовый носик
    _fillPaint.color = earColor;
    canvas.drawCircle(pt(0.75, 0.48), s * 0.016, _fillPaint);
  }

  @override
  bool shouldRepaint(covariant _HamsterPainter old) =>
      old.furColor != furColor ||
      old.bellyColor != bellyColor ||
      old.earColor != earColor ||
      old.stepPhase != stepPhase;
}
