import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class _BunnyPainter extends CustomPainter {
  _BunnyPainter(this.color, this.inner);

  final Color color;
  final Color inner;

  /// Нормированная точка 0…1 → точка в окне с полем по краям.
  static Offset _p(double x, double y, double s, double ox, double oy) =>
      Offset(ox + x * s, oy + y * s);

  /// Левое ухо: длинный лепесток от макушки к кончику. Правое — зеркало.
  static Path _ear(double s, double ox, double oy) {
    Offset p(double x, double y) => _p(x, y, s, ox, oy);
    return Path()
      ..moveTo(p(0.455, 0.560).dx, p(0.455, 0.560).dy)
      // внутренняя кромка вверх
      ..cubicTo(
        p(0.415, 0.410).dx,
        p(0.415, 0.410).dy,
        p(0.362, 0.230).dx,
        p(0.362, 0.230).dy,
        p(0.352, 0.115).dx,
        p(0.352, 0.115).dy,
      )
      // кончик
      ..cubicTo(
        p(0.348, 0.058).dx,
        p(0.348, 0.058).dy,
        p(0.298, 0.048).dx,
        p(0.298, 0.048).dy,
        p(0.284, 0.095).dx,
        p(0.284, 0.095).dy,
      )
      // наружная кромка вниз
      ..cubicTo(
        p(0.264, 0.150).dx,
        p(0.264, 0.150).dy,
        p(0.244, 0.300).dx,
        p(0.244, 0.300).dy,
        p(0.246, 0.500).dx,
        p(0.246, 0.500).dy,
      )
      // основание уха, спрятанное в голове
      ..cubicTo(
        p(0.278, 0.578).dx,
        p(0.278, 0.578).dy,
        p(0.362, 0.582).dx,
        p(0.362, 0.582).dy,
        p(0.455, 0.560).dx,
        p(0.455, 0.560).dy,
      )
      ..close();
  }

  /// Внутреннее ухо: узкий лепесток, ложится в вырез по центру уха.
  static Path _innerEar(double s, double ox, double oy) {
    Offset p(double x, double y) => _p(x, y, s, ox, oy);
    return Path()
      ..moveTo(p(0.386, 0.430).dx, p(0.386, 0.430).dy)
      ..cubicTo(
        p(0.368, 0.350).dx,
        p(0.368, 0.350).dy,
        p(0.348, 0.255).dx,
        p(0.348, 0.255).dy,
        p(0.344, 0.180).dx,
        p(0.344, 0.180).dy,
      )
      ..cubicTo(
        p(0.340, 0.142).dx,
        p(0.340, 0.142).dy,
        p(0.318, 0.136).dx,
        p(0.318, 0.136).dy,
        p(0.310, 0.168).dx,
        p(0.310, 0.168).dy,
      )
      ..cubicTo(
        p(0.302, 0.220).dx,
        p(0.302, 0.220).dy,
        p(0.298, 0.320).dx,
        p(0.298, 0.320).dy,
        p(0.300, 0.418).dx,
        p(0.300, 0.418).dy,
      )
      ..cubicTo(
        p(0.318, 0.442).dx,
        p(0.318, 0.442).dy,
        p(0.362, 0.446).dx,
        p(0.362, 0.446).dy,
        p(0.386, 0.430).dx,
        p(0.386, 0.430).dy,
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
    // Голова: чуть сплюснутый овал, шире книзу — «щёчки».
    final head = Path()
      ..addOval(
        Rect.fromCenter(
          center: p(0.5, 0.712),
          width: s * 0.644,
          height: s * 0.488,
        ),
      );

    final silhouette = Path()
      ..addPath(ear, Offset.zero)
      ..addPath(_mirror(ear, size), Offset.zero)
      ..addPath(head, Offset.zero);

    // Лицо — ВЫРЕЗ: внутренние уши, глаза и нос. Так глиф читается и на
    // светлом, и на тёмном фоне, без второго цвета поверх силуэта.
    final cut = Path()
      ..addPath(_innerEar(s, ox, oy), Offset.zero)
      ..addPath(_mirror(_innerEar(s, ox, oy), size), Offset.zero)
      ..addOval(Rect.fromCircle(center: p(0.408, 0.668), radius: s * 0.050))
      ..addOval(Rect.fromCircle(center: p(0.592, 0.668), radius: s * 0.050))
      // Нос — мягкий треугольник с закруглёнными углами.
      ..moveTo(p(0.468, 0.762).dx, p(0.468, 0.762).dy)
      ..cubicTo(
        p(0.482, 0.750).dx,
        p(0.482, 0.750).dy,
        p(0.518, 0.750).dx,
        p(0.518, 0.750).dy,
        p(0.532, 0.762).dx,
        p(0.532, 0.762).dy,
      )
      ..cubicTo(
        p(0.520, 0.792).dx,
        p(0.520, 0.792).dy,
        p(0.512, 0.810).dx,
        p(0.512, 0.810).dy,
        p(0.500, 0.820).dx,
        p(0.500, 0.820).dy,
      )
      ..cubicTo(
        p(0.488, 0.810).dx,
        p(0.488, 0.810).dy,
        p(0.480, 0.792).dx,
        p(0.480, 0.792).dy,
        p(0.468, 0.762).dx,
        p(0.468, 0.762).dy,
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
