import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// «Белка в колесе» — живой значок обновления (вместо прежнего зайчика):
/// колесо плавно и непрерывно вращается, белочка сидит в нём.
///
/// Почему дёшево и «плавное» (в отличие от старого прыгающего зайчика):
/// и белочка, и колесо рисуются ОДИН раз в постоянных слоях
/// (`RepaintBoundary`), а вращение — это `Transform.rotate` по готовому
/// растру: GPU двигает кэшированную картинку, кривые за кадр не
/// пересобираются. Никаких покадровых аллокаций и «дрожащего» дыхания.
///
/// Уважает «убрать анимации» ([MotionPrefs]): тогда колесо стоит, а белочка
/// и колесо остаются видимыми (вход принудительно завершён).
class SquirrelWheel extends StatefulWidget {
  const SquirrelWheel({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
    this.enter,
    this.period = const Duration(milliseconds: 3200),
  });

  /// Вписанный квадрат значка, px.
  final double size;

  /// Основной тон белки (полная заливка).
  final Color color;

  /// Тон колеса (задний, приглушённый). По умолчанию — тот же [color]
  /// с прозрачностью: белочка читается поверх, колесо — фоном.
  final Color? innerColor;

  /// Необязательный разовый вход (фэйд + «набухание»). Если `null` —
  /// значок виден сразу.
  final Animation<double>? enter;

  /// Время одного оборота колеса.
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
    // Вечное вращение: крутится, только если движение разрешено. При
    // «убрать анимации» колело стоит (frozen), но белочка остаётся видимой.
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
    final inner = widget.innerColor ?? color.withValues(alpha: 0.42);
    // При «убрать анимации» или без [enter] — значок виден сразу (иначе
    // остался бы невидимым на нулевом контроллере: тот же приём, что был
    // у зайчика).
    final entered =
        MotionPrefs.shouldReduceMotion || widget.enter == null
            ? 1.0
            : widget.enter!.value.clamp(0.0, 1.0);

    return RepaintBoundary(
      child: Opacity(
        opacity: entered,
        child: Transform.scale(
          scale: 0.86 + 0.14 * entered,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Колесо (за белкой): вращается Transform'ом готового растра.
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => Transform.rotate(
                      angle: _spin.value * 2 * math.pi,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          isComplex: true,
                          willChange: false,
                          painter: _WheelPainter(inner),
                        ),
                      ),
                    ),
                  ),
                ),
                // Белочка (по колесу): статичный слой, не перерисовывается.
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    willChange: false,
                    painter: _SquirrelPainter(color),
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

/// Колесо: обод + три спицы + ступица. Спиц три (симметрия 120°), поэтому
/// непрерывное вращение читается как «колесо крутится», а не «стало на место».
class _WheelPainter extends CustomPainter {
  _WheelPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final c = Offset(s / 2, s / 2);
    final r = s * 0.47;

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, ring);

    final spoke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    // Три спицы (120°): непрерывный поворот читается как вращение колеса.
    for (var i = 0; i < 3; i++) {
      final a = i * math.pi * 2 / 3;
      canvas.drawLine(
        c,
        c + Offset(math.cos(a), math.sin(a)) * (r - s * 0.03),
        spoke,
      );
    }

    final hub = Paint()
      ..color = color
      ..isAntiAlias = true;
    canvas.drawCircle(c, s * 0.085, hub);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.color != color;
}

/// Белочка в профиль (смотрит вправо): пушистый хвост-виток, туловище,
/// голова с ушком и лапка. Лицо — не заливка, а ВЫРЕЗ (`BlendMode.clear`),
/// поэтому значок читается и на светлом, и на тёмном фоне, и на колесе за ним.
class _SquirrelPainter extends CustomPainter {
  _SquirrelPainter(this.color);

  final Color color;

  /// Нормированная точка 0…1 → пиксели (центр окна = 0.5,0.5).
  static Offset _p(double x, double y, double s, double ox, double oy) =>
      Offset(ox + x * s, oy + y * s);

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height);
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    Offset p(double x, double y) => _p(x, y, s, ox, oy);

    // Пушистый хвост — виток (штрих с округлыми торцами), а не «штрих-царапина»:
    // читается именно хвостом белки.
    final tail = Path()
      ..moveTo(p(0.42, 0.58).dx, p(0.42, 0.58).dy)
      ..cubicTo(
        p(0.28, 0.56).dx,
        p(0.28, 0.56).dy,
        p(0.24, 0.44).dx,
        p(0.24, 0.44).dy,
        p(0.30, 0.34).dx,
        p(0.30, 0.34).dy,
      )
      ..cubicTo(
        p(0.35, 0.27).dx,
        p(0.35, 0.27).dy,
        p(0.45, 0.30).dx,
        p(0.45, 0.30).dy,
        p(0.46, 0.40).dx,
        p(0.46, 0.40).dy,
      );

    // Силуэт: хвост (штрих) + туловище + голова + ушко + лапка.
    canvas.drawPath(
      tail,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );

    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    // Туловище.
    canvas.drawCircle(p(0.50, 0.575), s * 0.155, fill);
    // Голова.
    canvas.drawCircle(p(0.60, 0.45), s * 0.120, fill);
    // Ушко.
    canvas.drawOval(
      Rect.fromCenter(
        center: p(0.655, 0.365),
        width: s * 0.055,
        height: s * 0.095,
      ),
      fill,
    );
    // Передняя лапка.
    canvas.drawCircle(p(0.49, 0.70), s * 0.045, fill);

    // Глаз — вырез (сквозь него видно колесо/фон, а не заливку).
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawCircle(
      p(0.628, 0.435),
      s * 0.026,
      Paint()..blendMode = BlendMode.clear..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SquirrelPainter old) => old.color != color;
}
