import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Значок Agysha — «зайчик». СВОЙ векторный глиф, а не шрифтовая иконка:
/// системные `Icons.cruelty_free`/`Icons.system_update_alt` в мелком размере
/// читались чужеродно, а стрелка сливалась в пятно.
///
/// Силуэт собран из ТРЁХ узнаваемых частей: два длинных уха, круглая голова и
/// лицо. Лицо (внутренние уши, глаза, нос) — не заливка поверх силуэта, а
/// ВЫРЕЗ: `BlendMode.clear` внутри `saveLayer`. На 18 px таблетки заливка
/// «поверх» сливалась с силуэтом в пятно, а вырез читается на любом фоне —
/// видно и уши, и глазки, и нос.
///
/// Геометрия нормирована (0…1), поэтому глиф одинаково чётко ложится и на
/// 18 px таблетки, и на 22 px медальона окна: кривые, а не пиксельная сетка.
///
/// Painter СТАТИЧЕН и никогда не перерисовывается сам: любое движение — это
/// `Transform` над готовым слоем (`RepaintBoundary`), поэтому кадры анимации
/// не растеризуют глиф заново (именно это и «лагало» раньше).
class AgyshaBunny extends StatelessWidget {
  const AgyshaBunny({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
  });

  final double size;
  final Color color;

  /// Тон внутренних ушей — единственная «заливка» в глифе: мягкий акцент
  /// внутри вырезанного уха. По умолчанию тот же цвет с прозрачностью.
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

/// Живой зайчик: статичный глиф [AgyshaBunny] внутри слоя, который оживляет
/// мягкий «подскок» — заяц чуть подпрыгивает и садится, слегка сплющиваясь на
/// отрыве и приземлении.
///
/// Почему так, а не покадровой перерисовкой: глиф рисуется ОДИН раз в
/// постоянный слой (`RepaintBoundary`), а кадры анимации лишь переносят готовый
/// растр через `Transform` — GPU двигает кэшированную картинку, кривые не
/// пересобираются. Именно на этом раньше «лагал» значок при вечном «дыхании».
///
/// Цикл замкнут: подъём и посадка идут по `sin(π·x)`, поэтому значение И
/// производная нулевые на обоих концах — стык витков без рывка. Движение
/// уважает «убрать анимации» ([MotionPrefs]): тогда зайчик просто стоит.
class AnimatedBunny extends StatefulWidget {
  const AnimatedBunny({
    super.key,
    required this.size,
    required this.color,
    this.innerColor,
    this.enter,
    this.period = const Duration(milliseconds: 3000),
    this.lift = 0.16,
  });

  final double size;
  final Color color;
  final Color? innerColor;

  /// Необязательный разовый вход: глиф «вырастает» и проявляется. Если null —
  /// зайчик появляется сразу, а оживляет его только вечный подскок.
  final Animation<double>? enter;

  /// Полный цикл «подскок + покой».
  final Duration period;

  /// Высота подскока как доля [size].
  final double lift;

  @override
  State<AnimatedBunny> createState() => _AnimatedBunnyState();
}

class _AnimatedBunnyState extends State<AnimatedBunny>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
  late final AnimationController _idle;

  @override
  void initState() {
    super.initState();
    _idle = ambientRepeat(
      AnimationController(vsync: this, duration: widget.period),
    );
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  /// Фаза «в воздухе»: доля цикла, которую заяц проводит в подскоке.
  static const double _air = 0.42;

  /// Подъём 0→1→0 внутри фазы подскока (и 0 в фазе покоя). Синус даёт нулевую
  /// скорость на обоих концах — нет рывка ни на отрыве, ни на посадке.
  static double _hop(double t) {
    if (t >= _air) return 0;
    return math.sin(math.pi * (t / _air));
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable?>[_idle, widget.enter]),
        builder: (context, child) {
          final t = _idle.value;
          final hop = _hop(t);
          // Мягкое «дыхание» на покое, чтобы заяц не замирал между прыжками.
          final breathe = 0.5 - 0.5 * math.cos(t * 2 * math.pi);

          final dy = -(hop * widget.lift + breathe * 0.03) * widget.size;
          final stretch = 1 + 0.14 * hop;
          final squash = 1 - 0.10 * hop;

          final enterV = widget.enter?.value ?? 1.0;
          return Opacity(
            opacity: enterV.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scaleX: enterV * squash,
                scaleY: enterV * stretch,
                child: child,
              ),
            ),
          );
        },
        child: RepaintBoundary(
          child: AgyshaBunny(
            size: widget.size,
            color: widget.color,
            innerColor: widget.innerColor,
          ),
        ),
      ),
    );
  }
}

class _BunnyPainter extends CustomPainter {
  _BunnyPainter(this.color, this.inner);

  final Color color;
  final Color inner;

  /// Нормированная точка 0…1 → точка в окне с полем по краям.
  static Offset _p(double x, double y, double s, double ox, double oy) =>
      Offset(ox + x * s, oy + y * s);

  /// Левое ухо: длинный лепесток от макушки к кончику. Правое — зеркало.
  /// Кромки почти параллельны, а кончик закруглён — ухо читается «ухом», а не
  /// случайным мазком; на 18 px таблетки это единственное, что различает зайца.
  static Path _ear(double s, double ox, double oy) {
    Offset p(double x, double y) => _p(x, y, s, ox, oy);
    return Path()
      ..moveTo(p(0.458, 0.520).dx, p(0.458, 0.520).dy)
      // внутренняя кромка вверх
      ..cubicTo(
        p(0.432, 0.392).dx,
        p(0.432, 0.392).dy,
        p(0.404, 0.238).dx,
        p(0.404, 0.238).dy,
        p(0.380, 0.120).dx,
        p(0.380, 0.120).dy,
      )
      // округлый кончик
      ..cubicTo(
        p(0.366, 0.060).dx,
        p(0.366, 0.060).dy,
        p(0.306, 0.046).dx,
        p(0.306, 0.046).dy,
        p(0.292, 0.104).dx,
        p(0.292, 0.104).dy,
      )
      // наружная кромка вниз
      ..cubicTo(
        p(0.264, 0.212).dx,
        p(0.264, 0.212).dy,
        p(0.244, 0.352).dx,
        p(0.244, 0.352).dy,
        p(0.250, 0.512).dx,
        p(0.250, 0.512).dy,
      )
      // основание уха, спрятанное в голове
      ..cubicTo(
        p(0.258, 0.568).dx,
        p(0.258, 0.568).dy,
        p(0.372, 0.578).dx,
        p(0.372, 0.578).dy,
        p(0.458, 0.520).dx,
        p(0.458, 0.520).dy,
      )
      ..close();
  }

  /// Внутреннее ухо: узкий лепесток, ложится в вырез по центру уха.
  static Path _innerEar(double s, double ox, double oy) {
    Offset p(double x, double y) => _p(x, y, s, ox, oy);
    return Path()
      ..moveTo(p(0.398, 0.404).dx, p(0.398, 0.404).dy)
      ..cubicTo(
        p(0.378, 0.320).dx,
        p(0.378, 0.320).dy,
        p(0.360, 0.222).dx,
        p(0.360, 0.222).dy,
        p(0.350, 0.150).dx,
        p(0.350, 0.150).dy,
      )
      ..cubicTo(
        p(0.344, 0.112).dx,
        p(0.344, 0.112).dy,
        p(0.318, 0.106).dx,
        p(0.318, 0.106).dy,
        p(0.310, 0.146).dx,
        p(0.310, 0.146).dy,
      )
      ..cubicTo(
        p(0.300, 0.224).dx,
        p(0.300, 0.224).dy,
        p(0.296, 0.320).dx,
        p(0.296, 0.320).dy,
        p(0.300, 0.404).dx,
        p(0.300, 0.404).dy,
      )
      ..cubicTo(
        p(0.316, 0.436).dx,
        p(0.316, 0.436).dy,
        p(0.372, 0.436).dx,
        p(0.372, 0.436).dy,
        p(0.398, 0.404).dx,
        p(0.398, 0.404).dy,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Поле по краям: глиф не должен касаться границ окна (иначе на 18 px уши
    // «прилипают» к краю плашки).
    final s = math.min(size.width, size.height) * 0.94;
    final ox = (size.width - s) / 2;
    final oy = (size.height - s) / 2;
    Offset p(double x, double y) => _p(x, y, s, ox, oy);

    final ear = _ear(s, ox, oy);
    // Голова: круг — крупнее прежнего овала. На мелком размере большой ровный
    // «пятак» читается лучше приплюснутого, а уши по бокам дают узнаваемый
    // силуэт зайца.
    final head = Path()
      ..addOval(Rect.fromCircle(center: p(0.5, 0.700), radius: s * 0.238));

    final silhouette = Path()
      ..addPath(ear, Offset.zero)
      ..addPath(_mirror(ear, size), Offset.zero)
      ..addPath(head, Offset.zero);

    // Лицо — ВЫРЕЗ: внутренние уши, глаза и нос. Так глиф читается и на
    // светлом, и на тёмном фоне, без второго цвета поверх силуэта.
    final cut = Path()
      ..addPath(_innerEar(s, ox, oy), Offset.zero)
      ..addPath(_mirror(_innerEar(s, ox, oy), size), Offset.zero)
      // Глаза крупнее прежних: на 18 px мелкая точка пропадала в растре.
      ..addOval(Rect.fromCircle(center: p(0.424, 0.662), radius: s * 0.058))
      ..addOval(Rect.fromCircle(center: p(0.576, 0.662), radius: s * 0.058))
      // Нос — мягкий треугольник с закруглёнными углами.
      ..moveTo(p(0.470, 0.772).dx, p(0.470, 0.772).dy)
      ..cubicTo(
        p(0.482, 0.758).dx,
        p(0.482, 0.758).dy,
        p(0.518, 0.758).dx,
        p(0.518, 0.758).dy,
        p(0.530, 0.772).dx,
        p(0.530, 0.772).dy,
      )
      ..cubicTo(
        p(0.520, 0.800).dx,
        p(0.520, 0.800).dy,
        p(0.512, 0.818).dx,
        p(0.512, 0.818).dy,
        p(0.500, 0.828).dx,
        p(0.500, 0.828).dy,
      )
      ..cubicTo(
        p(0.488, 0.818).dx,
        p(0.488, 0.818).dy,
        p(0.480, 0.800).dx,
        p(0.480, 0.800).dy,
        p(0.470, 0.772).dx,
        p(0.470, 0.772).dy,
      )
      ..close();

    // saveLayer нужен ровно ради `BlendMode.clear`: без слоя вырез стёр бы и
    // фон под глифом. Слой одноразовый — painter статичен.
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawPath(silhouette, Paint()..color = color);
    canvas.drawPath(
      cut,
      Paint()
        ..blendMode = BlendMode.clear
        ..isAntiAlias = true,
    );
    canvas.restore();

    // Внутреннее ухо — единственная заливка: тонкий акцент внутри выреза.
    canvas.saveLayer(bounds, Paint());
    canvas.clipPath(cut);
    canvas.drawPath(
      Path()
        ..addPath(_innerEar(s, ox, oy), Offset.zero)
        ..addPath(_mirror(_innerEar(s, ox, oy), size), Offset.zero),
      Paint()..color = inner,
    );
    canvas.restore();
  }

  /// Зеркало пути относительно вертикальной оси окна.
  static Path _mirror(Path path, Size size) {
    final m = Matrix4.identity()
      ..translateByDouble(size.width, 0.0, 0.0, 1.0)
      ..scaleByDouble(-1.0, 1.0, 1.0, 1.0);
    return path.transform(m.storage);
  }

  @override
  bool shouldRepaint(covariant _BunnyPainter old) =>
      old.color != color || old.inner != inner;
}
