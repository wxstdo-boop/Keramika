/// Painters and animation helpers extracted from lock_screen.dart
/// (a `part` of that library).
part of 'lock_screen.dart';

class _PinShapePainter extends CustomPainter {
  final int shape;
  /// 0 — пустая фигура (только контур), 1 — полностью залита.
  final double progress;
  final Color color;
  final Color ghost;
  _PinShapePainter({
    required this.shape,
    required this.progress,
    required this.color,
    required this.ghost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = size.width * 0.44;
    final path = _pathFor(shape, c, r);
    final pr = progress.clamp(0.0, 1.0);

    // Пустой контур: виден, пока фигура не залита; растворяется вместе
    // с наполнением, чтобы не «двойнить» линии.
    if (pr < 0.999) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = ghost.withValues(alpha: 0.6 * (1 - pr)),
      );
    }

    // Заливка: появляется со своей скоростью и лёгким «подъёмом».
    if (pr > 0.001) {
      final s = 0.92 + 0.08 * pr;
      canvas.save();
      canvas.translate(c, c);
      canvas.scale(s);
      canvas.translate(-c, -c);
      // Мягкий внешний ореол.
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.35 * pr)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // Основная заливка + тонкий верхний блик для объёма.
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: pr));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(c - r * 0.25, c - r * 0.35),
          width: r * 0.9,
          height: r * 0.45,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.14 * pr),
      );
      canvas.restore();
    }
  }

  Path _pathFor(int shape, double c, double r) {
    final p = Path();
    switch (shape) {
      case 0:
        // Ромб.
        p.moveTo(c, c - r);
        p.lineTo(c + r, c);
        p.lineTo(c, c + r);
        p.lineTo(c - r, c);
        p.close();
        break;
      case 1:
        // Шестиугольник.
        for (int i = 0; i < 6; i++) {
          final a = -math.pi / 2 + i * math.pi / 3;
          final x = c + r * math.cos(a);
          final y = c + r * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
        break;
      case 2:
        // Капля (острый кончик сверху, округлое дно).
        final tipY = c - r;
        final botY = c + r * 0.9;
        final w = r * 0.78;
        p.moveTo(c, tipY);
        p.cubicTo(c + w, c - r * 0.05, c + w, botY - r * 0.4, c, botY);
        p.cubicTo(c - w, botY - r * 0.4, c - w, c - r * 0.05, c, tipY);
        p.close();
        break;
      default:
        // Восьмиугольник.
        for (int i = 0; i < 8; i++) {
          final a = math.pi / 8 + i * math.pi / 4;
          final x = c + r * 0.92 * math.cos(a);
          final y = c + r * 0.92 * math.sin(a);
          if (i == 0) {
            p.moveTo(x, y);
          } else {
            p.lineTo(x, y);
          }
        }
        p.close();
    }
    return p;
  }

  @override
  bool shouldRepaint(_PinShapePainter old) =>
      old.shape != shape ||
      old.progress != progress ||
      old.color != color ||
      old.ghost != ghost;
}

/// Рисует стакан с плещущейся жидкостью по фазе [loop] (0..1).
class _GlassPainter extends CustomPainter {
  _GlassPainter({
    required this.loop,
    required this.color,
    required this.isDark,
  }) : super(repaint: loop);

  final Animation<double> loop;
  final Color color;
  final bool isDark;

  /// Наклон-маятник: ±7.4° — заметно, но силуэт стакана всё время читается.
  static const double _tiltAmp = 0.13;

  @override
  void paint(Canvas canvas, Size size) {
    final t = loop.value;
    final phase = _tau * t;
    final s = size.shortestSide;
    final cx = size.width / 2;

    // Лёгкая левитация: ±1.2% габарита; косинус на склейке витков совпадает.
    final bob = math.cos(phase) * s * 0.012;
    final cy = size.height / 2 + bob;

    final rimW = s * 0.60;
    final botW = s * 0.42;
    final gh = s * 0.62;
    final rimY = cy - gh / 2;
    final botY = cy + gh / 2;

    final theta = _tiltAmp * math.sin(phase);
    final pivot = Offset(cx, cy);
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);
    Offset rot(Offset p) {
      final dx = p.dx - pivot.dx;
      final dy = p.dy - pivot.dy;
      return Offset(
        pivot.dx + dx * cosT - dy * sinT,
        pivot.dy + dx * sinT + dy * cosT,
      );
    }

    // Наклонённый силуэт стакана (острые кромки сверху, скруглённое дно).
    final quad = <Offset>[
      rot(Offset(cx - rimW / 2, rimY)),
      rot(Offset(cx + rimW / 2, rimY)),
      rot(Offset(cx + botW / 2, botY)),
      rot(Offset(cx - botW / 2, botY)),
    ];
    final glass = _glassPath(quad, s * 0.055);

    // Стекло: лёгкая заливка в тон акцента — контур дорисуем поверх.
    canvas.drawPath(
      glass,
      Paint()..color = color.withValues(alpha: isDark ? 0.10 : 0.08),
    );

    // Жидкость: уровень на четверть периода позже наклона.
    final fill = 0.44 + 0.045 * math.sin(phase - math.pi / 2);
    final surfaceY = botY - gh * fill;
    final liquid = _clipBelow(quad, surfaceY);
    if (liquid.length >= 3) {
      final path = Path()..moveTo(liquid.first.dx, liquid.first.dy);
      for (final p in liquid.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();

      canvas.save();
      canvas.clipPath(glass);
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(
                color,
                Colors.white,
                0.18,
              )!.withValues(alpha: isDark ? 0.88 : 0.80),
              color.withValues(alpha: isDark ? 0.96 : 0.90),
            ],
          ).createShader(path.getBounds()),
      );
      // Кромка жидкости: в мировых координатах это ровная горизонталь —
      // качается стакан, а поверхность напитка остаётся спокойной.
      final edge = liquid
          .where((p) => (p.dy - surfaceY).abs() < 0.05)
          .toList();
      if (edge.length >= 2) {
        edge.sort((a, b) => a.dx.compareTo(b.dx));
        canvas.drawLine(
          edge.first,
          edge.last,
          Paint()
            ..color = Color.lerp(color, Colors.white, 0.45)!
                .withValues(alpha: isDark ? 0.55 : 0.45)
            ..strokeWidth = 1.1
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }

    // Контур поверх заливок — стенки не «замываются» жидкостью.
    canvas.drawPath(
      glass,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.95),
    );

    // Блик у левой стенки — объём «на просвет».
    canvas.drawLine(
      rot(Offset(cx - rimW * 0.30, rimY + gh * 0.16)),
      rot(Offset(cx - rimW * 0.20, botY - gh * 0.18)),
      Paint()
        ..color = Colors.white.withValues(alpha: isDark ? 0.34 : 0.62)
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Силуэт стакана: трапеция со скруглённым дном.
  static Path _glassPath(List<Offset> q, double r) {
    final tl = q[0], tr = q[1], br = q[2], bl = q[3];
    Offset toward(Offset from, Offset to, double d) {
      final v = to - from;
      return from + v / v.distance * d;
    }

    final brA = toward(br, tr, r);
    final brB = toward(br, bl, r);
    final blA = toward(bl, br, r);
    final blB = toward(bl, tl, r);
    return Path()
      ..moveTo(tl.dx, tl.dy)
      ..lineTo(tr.dx, tr.dy)
      ..lineTo(brA.dx, brA.dy)
      ..quadraticBezierTo(br.dx, br.dy, brB.dx, brB.dy)
      ..lineTo(blA.dx, blA.dy)
      ..quadraticBezierTo(bl.dx, bl.dy, blB.dx, blB.dy)
      ..close();
  }

  /// Отсечение выпуклого четырёхугольника полуплоскостью y ≥ [ys]
  /// (Сазерленд–Ходжман для одной плоскости).
  static List<Offset> _clipBelow(List<Offset> poly, double ys) {
    final out = <Offset>[];
    for (var i = 0; i < poly.length; i++) {
      final a = poly[i];
      final b = poly[(i + 1) % poly.length];
      final aIn = a.dy >= ys;
      final bIn = b.dy >= ys;
      if (aIn) out.add(a);
      if (aIn != bIn) {
        final k = (ys - a.dy) / (b.dy - a.dy);
        out.add(Offset(a.dx + (b.dx - a.dx) * k, ys));
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GlassPainter old) =>
      old.loop != loop || old.color != color || old.isDark != isDark;
}

const double _tau = math.pi * 2;

/// Пятно от нажатия: блин с рваным краем, стекающей вниз гранью и несколькими
/// брызгами-спутниками, которые вылетают чуть позже самого пятна.
class _SplatHighlightPainter extends CustomPainter {
  /// Яркость: 0 → 1 на подъёме, 1 → 0 на высыхании.
  final double t;

  /// Геометрия пятна (0 → 1 и чуть дальше): отдельно от яркости, чтобы
  /// высыхающее пятно расползалось, а не сжималось назад.
  final double spread;
  final Color color;
  final double seed;

  const _SplatHighlightPainter({
    required this.t,
    required this.spread,
    required this.color,
    required this.seed,
  });

  /// Единичное пятно (центр 0,0, радиус 1) на заданный seed.
  ///
  /// Геометрия `_blob` линейна по радиусу: точка = центр + r·f(угол, seed),
  /// поэтому путь достаточно построить ОДИН раз на seed, а дальше гонять его
  /// через `Path.transform` (один вызов вместо 45 moveTo/lineTo и 9 пар
  /// sin/cos на каждый кадр). Раньше пересборка шла ≈96 раз за одно зажатие
  /// клавиши, и вместе со свечением через MaskFilter это давало ощутимые
  /// просадки именно в момент нажатия — на слабом Adreno 610.
  ///
  /// Масштаб берём из path, а НЕ из CTM канваса: `MaskFilter.blur` задан в
  /// пикселях устройства, и трансформация канваса по-разному трактуется
  /// движками, а пиксельный результат обязан остаться прежним.
  static final Map<double, Path> _unitBlobs = {};

  static Path _unitBlob(double phase) {
    final cached = _unitBlobs[phase];
    if (cached != null) return cached;
    final path = Path();
    const n = 44;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final w =
          1 +
          0.14 * math.sin(a * 3 + phase) +
          0.09 * math.sin(a * 5 + phase * 1.7) +
          0.05 * math.sin(a * 9 + phase * 0.6);
      final drip = math.max(0.0, math.sin(a)) * 0.18;
      final x = math.cos(a) * w;
      final y = math.sin(a) * (w * 0.9 + drip);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    // Ключей реально 10 штук (по числу клавиш), потолок — на вырост.
    if (_unitBlobs.length > 32) _unitBlobs.clear();
    _unitBlobs[phase] = path;
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.004) return;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * (0.30 + 0.13 * spread);
    // Тот же контур, что и раньше: единичный путь, растянутый на r и
    // перенесённый в центр клавиши. Матрица записана столбцами напрямую
    // (X-базис, Y-базис, Z-базис, перенос) — так же, как делает Matrix4, но
    // без его deprecated-метода scale.
    final blob = _unitBlob(seed).transform(
      Float64List.fromList(<double>[
        r, 0, 0, 0, //
        0, r, 0, 0, //
        0, 0, 1, 0, //
        c.dx, c.dy, 0, 1, //
      ]),
    );
    // Сначала — свечение тем же цветом (эффект = цвет + свет, а не размер),
    // поверх него уже сам пигмент с рваным краем.
    canvas.drawPath(
      blob,
      Paint()
        ..color = color.withValues(alpha: 0.26 * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.34),
    );
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.62 * t),
          color.withValues(alpha: 0.44 * t),
          color.withValues(alpha: 0.16 * t),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r * 1.3));
    canvas.drawPath(blob, paint);

    // Брызги-спутники: стартуют с задержкой, поэтому нажатие читается как
    // удар капли, а не как появление лужи.
    for (var k = 0; k < 3; k++) {
      final tk = ((t - 0.22 - 0.14 * k) / 0.62).clamp(0.0, 1.0);
      if (tk <= 0) continue;
      final a = seed * 1.3 + k * 2.2;
      final d = r * (1.12 + 0.16 * k);
      final p = Offset(c.dx + math.cos(a) * d, c.dy + math.sin(a) * d * 0.82);
      canvas.drawCircle(
        p,
        size.width * (0.028 + 0.022 * k % 2) * tk,
        Paint()..color = color.withValues(alpha: 0.44 * tk),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SplatHighlightPainter old) =>
      old.t != t ||
      old.spread != spread ||
      old.color != color ||
      old.seed != seed;
}

/// Палитра подарочного скина «Метель»: северное сияние по белому снегу —
/// мята, ледяная лазурь и фиолет. Только для скина ПИН-скважины; обычные
/// темы остаются на акценте темы.
const List<Color> _kAurora = [
  Color(0xFF2FBF94),
  Color(0xFF4FB6E8),
  Color(0xFF7C6BE0),
];

/// Цвет сияния по позиции 0 → 1 по кругу (стык плавный: конец = начало).
Color _auroraAt(double x) {
  final p = (x % 1.0) * _kAurora.length;
  final i = p.floor() % _kAurora.length;
  final j = (i + 1) % _kAurora.length;
  return Color.lerp(_kAurora[i], _kAurora[j], p - p.floor())!;
}

/// Монотонная эмблема ПИН-экрана: ОДИН цвет темы, разнится только плотность.
///
/// Никаких градиентов, фасок, бликов, каустик и искр — вся «красивость»
/// держится на геометрии: корпус-кольцо, циферблат из двенадцати рисков и
/// указатель полудня. Скважина здесь не рисуется — она уехала в
/// [_MedallionMotionPainter] и проворачивается вместе со светом. Такой знак
/// читается и на 104 px, и на 24 px, и не рассыпается в кашу на слабом GPU.
class _MedallionPainter extends CustomPainter {
  final Color accent;
  final bool isDark;

  /// Скин «Метель» (подарок 12-го дня): корпус и риски циферблата горят
  /// северным сиянием вместо одного тона темы.
  final bool frost;

  _MedallionPainter({
    required this.accent,
    required this.isDark,
    this.frost = false,
  });

  /// Один тон, разная прозрачность — единственный «цветовой» приём здесь.
  Paint _ink(double a, {double? w}) => Paint()
    ..isAntiAlias = true
    ..color = accent.withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    double u(double v) => v * s;
    final c = Offset(s / 2, s / 2);
    final outer = u(0.44);

    // Подложка чуть плотнее фона — плашка есть, а «стекла» нет.
    canvas.drawCircle(
      c,
      outer,
      // Скобки обязательны: каскад `..` нельзя ставить прямо в ветке
      // тернарного оператора — анализатор читает его как каскад к ВСЕМУ
      // выражению `frost ? … : …` и ломается на `Expected an identifier`.
      frost
          ? (Paint()
              ..color = _kAurora[1].withValues(alpha: isDark ? 0.16 : 0.12))
          : _ink(isDark ? 0.15 : 0.10),
    );
    if (frost) {
      // Корпус сияющей лентой: SweepGradient по кругу — тот же один шейдер,
      // что и у обычного мазка кисти, размытия и масок нет.
      canvas.drawCircle(
        c,
        outer,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = u(0.024)
          ..shader = SweepGradient(
            colors: [..._kAurora, _kAurora.first],
          ).createShader(Rect.fromCircle(center: c, radius: outer)),
      );
    } else {
      // Корпус.
      canvas.drawCircle(c, outer, _ink(isDark ? 0.66 : 0.78, w: u(0.024)));
    }
    // Волосок внутренней окружности: разделяет корпус и циферблат.
    canvas.drawCircle(c, u(0.335), _ink(0.26, w: u(0.010)));

    _dial(canvas, u, c);
  }

  /// Циферблат: двенадцать рисков между корпусом и внутренней окружностью.
  /// Крупные (каждая третья) плотнее и шире, мелкие — только намёк. На
  /// полудне вместо риска указатель-треугольник: он задаёт «верх» знака.
  void _dial(Canvas canvas, double Function(double) u, Offset c) {
    Paint inkAt(double a, int i, {double? w}) =>
        frost ? _auroraPaint(a, i / 12, w: w) : _ink(a, w: w);
    for (var i = 0; i < 12; i++) {
      final a = i / 12 * math.pi * 2 - math.pi / 2;
      final dir = Offset(math.cos(a), math.sin(a));
      if (i == 0) {
        final perp = Offset(-dir.dy, dir.dx);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx + dir.dx * u(0.348), c.dy + dir.dy * u(0.348))
            ..lineTo(
              c.dx + dir.dx * u(0.410) + perp.dx * u(0.030),
              c.dy + dir.dy * u(0.410) + perp.dy * u(0.030),
            )
            ..lineTo(
              c.dx + dir.dx * u(0.410) - perp.dx * u(0.030),
              c.dy + dir.dy * u(0.410) - perp.dy * u(0.030),
            )
            ..close(),
          inkAt(0.95, i),
        );
        continue;
      }
      final major = i % 3 == 0;
      canvas.drawLine(
        c + dir * u(major ? 0.358 : 0.378),
        c + dir * u(0.410),
        inkAt(major ? 0.72 : 0.30, i, w: u(major ? 0.024 : 0.012))
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Краска риски в скине «Метель»: тон сияния на своей позиции по кругу.
  Paint _auroraPaint(double a, double pos, {double? w}) => Paint()
    ..isAntiAlias = true
    ..color = _auroraAt(pos).withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  bool shouldRepaint(covariant _MedallionPainter old) =>
      old.accent != accent || old.isDark != isDark || old.frost != frost;
}

/// Доля цикла, за которую скважина проворачивается туда и обратно;
/// остальное — короткий покой на нулевом угле.
const double _kTurnSpan = 0.86;

/// Прогресс поворота 0 → 1 smootherstep'ом: скорость равна нулю и на
/// старте, и в момент, когда полость доворачивается до упора, — поэтому
/// движение начинается и заканчивается без рывка.
double _turnEase(double t) {
  final x = (t / _kTurnSpan).clamp(0.0, 1.0);
  return x * x * x * (x * (x * 6 - 15) + 10);
}

/// Анимированный слой плашки: ореол вокруг корпуса, световой бегунок по его
/// кромке и чёрная скважина, которая вечно доворачивается вокруг своей оси.
///
/// Всё одним тоном и без saveLayer: ни blur, ни Shader-масок — только
/// RadialGradient-шейдер на ореоле, translate/rotate на скважине и обычные
/// дуги хвоста. На Adreno 610 размытие или маска стоили бы дороже всей плашки.
class _MedallionMotionPainter extends CustomPainter {
  final Color accent;
  final bool isDark;

  /// Прогресс цикла 0 → 1: задаёт и угол скважины, и угол бегунка, и ореол.
  final double t;

  /// Скин «Метель»: свет становится северным сиянием — ореол, бегунок и
  /// обводка скважины переливаются по палитре, вокруг корпуса кружат
  /// снежинки-искры. Геометрия и тайминг те же, что в обычном медальоне.
  final bool frost;

  _MedallionMotionPainter({
    required this.accent,
    required this.isDark,
    required this.t,
    this.frost = false,
  });

  /// Шаг хвоста и число штрихов — в долях полного оборота.
  static const double _step = 1 / 44;
  static const int _tail = 9;

  /// Краска мазка: тон темы или, в скине, сияние на позиции [pos] по кругу.
  Color _tone(double pos) => frost ? _auroraAt(pos) : accent;

  Paint _ink(double a, {double? w, double pos = 0}) => Paint()
    ..isAntiAlias = true
    ..color = _tone(pos).withValues(alpha: a)
    ..strokeWidth = w ?? 0
    ..style = w == null ? PaintingStyle.fill : PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = Offset(s / 2, s / 2);
    final tau = math.pi * 2;
    _halo(canvas, s, c, _medallionBreath(t));
    _runner(canvas, s, c, tau);
    _keyhole(canvas, s, c, _medallionTurn(t));
    if (frost) _sparks(canvas, s, c, tau);
  }

  /// Свечение — кольцо ВОКРУГ плашки, тем же тоном и без оттенков.
  void _halo(Canvas canvas, double s, Offset c, double k) {
    final rect = Rect.fromCircle(center: c, radius: s * 0.5);
    canvas.drawCircle(
      c,
      s * 0.5,
      frost
          ? (Paint()
              ..isAntiAlias = true
              ..shader = RadialGradient(
                colors: [
                  _tone(t).withValues(alpha: 0.0),
                  _tone(t).withValues(alpha: (isDark ? 0.46 : 0.38) * k),
                  _tone(t + 0.33).withValues(alpha: (isDark ? 0.34 : 0.28) * k),
                  _tone(t + 0.33).withValues(alpha: 0.0),
                ],
                stops: const [0.86, 0.945, 0.975, 1.0],
              ).createShader(rect))
          : (Paint()
              ..isAntiAlias = true
              ..shader = RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.0),
                  accent.withValues(alpha: (isDark ? 0.34 : 0.34) * k),
                  accent.withValues(alpha: 0.0),
                ],
                stops: const [0.86, 0.945, 1.0],
              ).createShader(rect)),
    );
  }

  /// Бегунок по кромке корпуса: голова и затухающий хвост из штрихов.
  /// Идёт ровно по кругу ВСЁ время цикла, поэтому пауза скважины не читается
  /// как «анимация встала».
  void _runner(Canvas canvas, double s, Offset c, double tau) {
    final rect = Rect.fromCircle(center: c, radius: s * 0.44);
    final glint = _medallionGlint(t);
    // −π/2: цикл стартует ровно на полудне, где у знака указатель.
    final lead = t * tau - math.pi / 2;
    final stroke = _ink(0, w: s * 0.026)..strokeCap = StrokeCap.round;
    for (var i = 0; i < _tail; i++) {
      final k = 1 - i / _tail;
      stroke.color = _tone(
        t - i * _step,
      ).withValues(alpha: 0.55 * glint * k * k);
      canvas.drawArc(
        rect,
        lead - (i + 1) * _step * tau,
        _step * tau * 0.88,
        false,
        stroke,
      );
    }
    final at = c + Offset(math.cos(lead), math.sin(lead)) * s * 0.44;
    canvas
      ..drawCircle(at, s * 0.050, _ink(0.16 * glint, pos: t))
      ..drawCircle(at, s * 0.032, _ink(0.30 * glint, pos: t))
      ..drawCircle(at, s * 0.016, _ink(0.80 * glint, pos: t));
  }

  /// Снежинки-искры скина: восемь точек на волосок вне корпуса, кружатся
  /// вместе с бегунком и разгораются на каждом довороте скважины.
  ///
  /// Радиус дышит вместе с ореолом: на разгорании искры расходятся от
  /// корпуса, на покое прижимаются к нему — поэтому плашка не выглядит
  /// застывшей между доворотами ключа.
  void _sparks(Canvas canvas, double s, Offset c, double tau) {
    final k = _medallionBreath(t);
    for (var i = 0; i < 8; i++) {
      final spread = 0.468 + 0.022 * k + 0.008 * (i.isEven ? 1 : -1);
      final a = lead(t, tau) + i / 8 * tau;
      final at = c + Offset(math.cos(a), math.sin(a)) * s * spread;
      final big = i % 3 == 0;
      if (big) {
        // Крупная искра получает ореол — тем же приёмом, что и голова
        // бегунка: два круга вместо размытия (blur здесь не по карману).
        canvas.drawCircle(at, s * 0.036, _ink(0.10 + 0.16 * k, pos: i / 8));
      }
      canvas.drawCircle(
        at,
        s * (big ? 0.017 : 0.010),
        _ink(0.30 + 0.45 * k, pos: i / 8),
      );
    }
  }

  /// Угол головы бегунка (тот же, что в [_runner]).
  static double lead(double t, double tau) => t * tau - math.pi / 2;

  /// Скважина проворачивается целиком: вращение самого провала читается как
  /// проворачиваемый механизм замка. Дырка остаётся ЧЁРНОЙ — цветная в тон
  /// темы она выглядела пятном краски, а не полостью.
  ///
  /// Подсветка поворота сделана светом, а не размером: по контуру полости
  /// разгорается обводка в тон темы на ту же долю цикла.
  void _keyhole(Canvas canvas, double s, Offset c, double angle) {
    final headY = -s * 0.088;
    final headR = s * 0.118;
    final bottom = s * 0.222;
    final w1 = headR * 0.58;
    final w2 = headR * 1.02;
    final q = s * 0.030;
    Paint ink(double a) => Paint()
      ..isAntiAlias = true
      ..color = Colors.black.withValues(alpha: a)
      ..style = PaintingStyle.fill;
    Path hole(double dy) {
      final hd = headY + dy;
      return Path()
        ..addOval(Rect.fromCircle(center: Offset(0, hd), radius: headR))
        ..moveTo(-w1, hd + headR * 0.30)
        ..lineTo(w1, hd + headR * 0.30)
        ..lineTo(w2, bottom + dy - q)
        ..quadraticBezierTo(w2, bottom + dy, w2 - q, bottom + dy)
        ..lineTo(-w2 + q, bottom + dy)
        ..quadraticBezierTo(-w2, bottom + dy, -w2, bottom + dy - q)
        ..close();
    }

    canvas
      ..save()
      ..translate(c.dx, c.dy)
      ..rotate(angle)
      // Свечение идёт ПЕРЕД чёрной полостью: заливка забрала бы обводку
      // внутрь себя, и снаружи остался бы только тонкий ободок.
      ..drawPath(
        hole(0),
        _ink((isDark ? 0.34 : 0.30) * _medallionBreath(t), w: s * 0.055, pos: t)
          ..strokeJoin = StrokeJoin.round,
      )
      ..drawPath(hole(s * 0.010), ink(isDark ? 0.30 : 0.22))
      ..drawPath(hole(0), ink(isDark ? 0.58 : 0.88))
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _MedallionMotionPainter old) =>
      old.t != t ||
      old.accent != accent ||
      old.isDark != isDark ||
      old.frost != frost;
}

class _WavyLinePainter extends CustomPainter {
  final Color color;
  _WavyLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = color;
    final path = Path();
    final amplitude = size.height * 0.32;
    const frequency = 4.0;
    const steps = 100;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = t * size.width;
      final y =
          size.height / 2 +
          amplitude * math.sin(t * math.pi * 2 * frequency);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavyLinePainter old) => old.color != color;
}

