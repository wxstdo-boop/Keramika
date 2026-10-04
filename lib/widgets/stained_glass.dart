import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Пятна фирменного цвета внутри стекла — следы от упавших капель.
///
/// Каждый «удар» капли рисуется как реальный брызг: плоское пятно-блин с
/// рваным краем и хвостом вниз, из него расходятся жгутики, на концах жгутиков
/// — капли-бусины, вокруг разбросан мелкий осколочный веер. Крупные пятна
/// льются мягким радиальным градиентом (пигмент ПОД стеклом), мелкие капли и
/// жгутики — плотным цветом, иначе на 2–4 px они просто растворились бы.
///
/// Пятна статичны: стекло живёт на экране постоянно, и анимация
/// перерисовывала бы их каждый кадр вместе с Blur — на слабом GPU это лишний
/// load. Все размеры брызга заданы в долях ВЫСОТЫ панели, поэтому при любой
/// ширине пропорции остаются прежними; геометрия кэшируется по размеру и
/// густоте.
///
/// Используется и капсулой разделов (полная густота), и тултипами (редкий
/// «чуть-чуть» вариант) — мотив стекла в приложении один.
class StainedGlassPainter extends CustomPainter {
  final Color color;
  final double alpha;

  /// Сколько мелких брызг разбросать по кромкам. 0 — только крупные капли.
  final int specks;

  /// Насколько размыты пятна, 0…1. При 0 — капля с чётким рваным краем
  /// (так рисуются тултипы: там пятно служит текстурой и край держит форму).
  /// Капсула разделов просила `1.0`: край становится мягче, диффузия вокруг
  /// шире, плотность мелких брызг ниже — пигмент «сошёл», а не «засох».
  final double diffuse;

  /// Рисовать ли каплю-«поцелуй» (губы) вместо одного блина. Отметина стоит
  /// в самом краю таблетки, где её ничего не перекрывает.
  final bool kiss;

  StainedGlassPainter({
    required this.color,
    required this.alpha,
    this.specks = 26,
    this.diffuse = 0,
    this.kiss = false,
  });

  static final List<_Drop> _drops = _buildDrops();
  static final Map<String, _StainPattern> _cache = {};

  @override
  void paint(Canvas canvas, Size size) {
    // Размер паттерна КВАНТУЕМ до 2 px. Нужно для «камня» выбранного
    // раздела: он тянется в полёте между вкладками на доли пикселя каждый
    // кадр, и без кванта геометрия (~30 путей) перестраивалась бы на каждом
    // кадре, а пятна ещё и «плавали» бы вместе с шириной. Для капсулы и
    // тултипов (стабильные габариты) квант — no-op: сдвиг пятна не больше
    // одного пикселя.
    final w = (size.width / 2).roundToDouble() * 2;
    final h = (size.height / 2).roundToDouble() * 2;
    final key = '${w}x$h:$specks:$diffuse:${kiss ? 1 : 0}';
    var pattern = _cache[key];
    if (pattern == null) {
      // Разные ширины тултипов дают разную геометрию: без потолка кэш разрастался
      // бы всю сессию.
      if (_cache.length > 16) _cache.clear();
      pattern = _StainPattern(
        Size(w, h),
        _drops,
        _buildSpecks(specks),
        diffuse: diffuse,
        kiss: kiss,
      );
      _cache[key] = pattern;
    }
    pattern.draw(canvas, color, alpha);
  }

  @override
  bool shouldRepaint(covariant StainedGlassPainter old) =>
      old.color != color ||
      old.alpha != alpha ||
      old.specks != specks ||
      old.diffuse != diffuse ||
      old.kiss != kiss;

  /// Мелкий дождь вокруг крупных капель. Значки разделов перекрывают центр
  /// капсулы, поэтому брызги ставятся в две свободные полосы — у верхней и
  /// нижней кромки стекла, где их ничего не прячет.
  static List<_Speck> _buildSpecks(int count) {
    final rnd = math.Random(23);
    return [
      for (var k = 0; k < count; k++)
        _Speck(
          u: 0.02 + rnd.nextDouble() * 0.96,
          v: rnd.nextBool()
              ? 0.04 + rnd.nextDouble() * 0.15
              : 0.81 + rnd.nextDouble() * 0.15,
          r: 0.045 + rnd.nextDouble() * 0.095,
        ),
    ];
  }

  static List<_Drop> _buildDrops() {
    final rnd = math.Random(7);
    final out = <_Drop>[];
    // Капли садятся в промежутки между значками разделов (значки стоят по
    // центрам пятырей), иначе каждое пятно оказывалось под непрозрачной
    // фигурой и его не было видно.
    for (final u in const [0.2, 0.4, 0.6, 0.8]) {
      final v = 0.26 + rnd.nextDouble() * 0.48;
      final r = 0.34 + rnd.nextDouble() * 0.16;
      final arms = <_Arm>[
        for (var k = 0; k < 2 + rnd.nextInt(2); k++)
          _Arm(
            angle: rnd.nextDouble() * math.pi * 2,
            len: r * (1.05 + rnd.nextDouble() * 0.45),
            width: r * (0.07 + rnd.nextDouble() * 0.05),
          ),
      ];
      final dots = <_Dot>[
        // Капли-бусины на концах жгутиков.
        for (final a in arms)
          _Dot(
            du: math.cos(a.angle) * a.len,
            dv: math.sin(a.angle) * a.len * 0.72,
            r: a.width * (0.7 + rnd.nextDouble() * 0.5),
          ),
        // Осколочный веер вокруг пятна.
        for (var k = 0; k < 4 + rnd.nextInt(2); k++)
          _Dot(
            du: (rnd.nextDouble() - 0.5) * r * 4.4,
            dv: (rnd.nextDouble() - 0.5) * r * 2.2,
            r: 0.04 + rnd.nextDouble() * 0.06,
          ),
      ];
      out.add(
        _Drop(
          u: u,
          v: v,
          r: r,
          squash: 0.62 + rnd.nextDouble() * 0.24,
          seed: rnd.nextDouble() * math.pi * 2,
          arms: arms,
          dots: dots,
          // Правый край капсулы — самое свободное место: значки там не
          // стоят, и отметина губ читается целиком.
          kiss: u == 0.8,
        ),
      );
    }
    return out;
  }
}

class _Drop {
  final double u;
  final double v;

  /// Радиус основного пятна в половинах высоты панели.
  final double r;
  final double squash;
  final double seed;
  final List<_Arm> arms;
  final List<_Dot> dots;

  /// Эта капля — «поцелуй» (отпечаток губ) вместо блина от удара.
  final bool kiss;

  const _Drop({
    required this.u,
    required this.v,
    required this.r,
    required this.squash,
    required this.seed,
    required this.arms,
    required this.dots,
    this.kiss = false,
  });
}

class _Arm {
  final double angle;
  final double len;
  final double width;
  const _Arm({required this.angle, required this.len, required this.width});
}

class _Dot {
  /// Смещение центра капли относительно центра пятна, в тех же единицах.
  final double du;
  final double dv;
  final double r;
  const _Dot({required this.du, required this.dv, required this.r});
}

/// Самостоятельная мелкая брызжина: координаты в долях панели, радиус — в
/// единицах половины её высоты.
class _Speck {
  final double u;
  final double v;
  final double r;
  const _Speck({required this.u, required this.v, required this.r});
}

/// Один отрисовываемый элемент брызга: готовый путь + режим заливки.
class _StainSpot {
  final Path path;

  /// Rect радиального градиента; null — лить плотным цветом.
  final Rect? gradRect;
  final double core;

  /// Мягкая кромка градиента (режим «размытое пятно»): цвет сходит на нет
  /// раньше и плавнее, чем в обычном режиме, где у пятна есть граница.
  final bool feather;

  _StainSpot.solid(this.path, this.core) : gradRect = null, feather = false;
  _StainSpot.stained(
    this.path,
    this.gradRect,
    this.core, {
    this.feather = false,
  });
}

class _StainPattern {
  final List<_StainSpot> spots;

  Color? _paintColor;
  double? _paintAlpha;
  List<Paint>? _paints;

  _StainPattern(
    Size size,
    List<_Drop> drops,
    List<_Speck> specks, {
    double diffuse = 0,
    bool kiss = false,
  }) : spots = _flatten(size, drops, specks, diffuse, kiss);

  static List<_StainSpot> _flatten(
    Size size,
    List<_Drop> drops,
    List<_Speck> specks,
    double soft,
    bool kiss,
  ) {
    // Единица измерения брызга — половина высоты панели.
    final unit = size.height * 0.5;
    final out = <_StainSpot>[];
    for (final d in drops) {
      final c = Offset(d.u * size.width, d.v * size.height);
      final r = d.r * unit;
      final isKiss = d.kiss && kiss;
      if (isKiss) {
        // Отпечаток губ. Ключевое: у «помады» есть СВОЙ чёткий силуэт, а
        // размытым рисуется только ореол под ним. Раньше и форма, и край
        // уходили в один радиальный градиент с пером 1.75·r — широкие
        // уголки губ попадали в зону 0.85 радиуса, где альфа уже почти
        // нулевая, и вместо поцелуя оставалось широкое мыло (замечено на
        // золотом рендере). Теперь: ореол → тело губ → бледный второй
        // отпечаток со смещением, как от прижатия дважды неплотно.
        final (kw, kh) = _kissWH(r * 0.92, d.squash);
        out.add(
          _StainSpot.stained(
            _kissPath(c, r * 0.92, d.squash, d.seed),
            Rect.fromCenter(
              center: c,
              width: kw * 2 * 1.34,
              height: kh * 2 * 1.52,
            ),
            0.40,
            feather: true,
          ),
        );
        out.add(
          _StainSpot.solid(
            _kissPath(c, r * 0.92, d.squash, d.seed),
            0.62 - 0.22 * soft,
          ),
        );
        final ghost = c + Offset(r * 0.13, r * 0.10);
        final (gw, gh) = _kissWH(r * 0.86, d.squash);
        out.add(
          _StainSpot.solid(
            _kissPath(ghost, r * 0.86, d.squash, d.seed + 0.9),
            0.20 - 0.08 * soft,
          ),
        );
        out.add(
          _StainSpot.stained(
            _kissPath(ghost, r * 0.86, d.squash, d.seed + 0.9),
            Rect.fromCenter(
              center: ghost,
              width: gw * 2 * 1.30,
              height: gh * 2 * 1.48,
            ),
            0.16,
            feather: true,
          ),
        );
        // У поцелуя нет брызг: только два мазка в уголках рта. Случайный
        // «осколочный веер» капли превращал отметину в конфетти, и губы
        // переставали читаться (видно на золотом рендере).
        for (final s in [-1.0, 1.0]) {
          out.add(
            _StainSpot.solid(
              Path()..addOval(
                Rect.fromCircle(
                  center: c + Offset(s * kw * 1.02, kh * 0.16),
                  radius: r * 0.055,
                ),
              ),
              0.55 - 0.22 * soft,
            ),
          );
        }
        continue;
      }
      // Сначала — мягкая диффузия вокруг капли (пигмент разошёлся по стеклу),
      // поверх неё само пятно с ЧЁТКИМ рваным краем: капля на стекле имеет
      // границу, полностью мягкое пятно читалось бы как розовое мазюканье.
      // В режиме `soft` граница убирается: пятно льётся градиентом, а
      // рваность края режется вдвое — это и есть «размывистее».
      out.add(
        _StainSpot.stained(
          _splatPath(
            c,
            r * (1.68 + 0.42 * soft),
            d.squash * 1.12,
            d.seed + 1.3,
            soft,
          ),
          Rect.fromCircle(center: c, radius: r * (1.88 + 0.5 * soft)),
          0.24 + 0.08 * soft,
          feather: soft > 0,
        ),
      );
      if (soft > 0) {
        out.add(
          _StainSpot.stained(
            _splatPath(c, r, d.squash, d.seed, soft),
            Rect.fromCircle(center: c, radius: r * 1.22),
            1.0 - 0.34 * soft,
            feather: true,
          ),
        );
      } else {
        out.add(
          _StainSpot.solid(_splatPath(c, r, d.squash, d.seed, soft), 1.0),
        );
      }
      for (final a in d.arms) {
        out.add(_StainSpot.solid(_armPath(c, a, unit), 0.58 - 0.24 * soft));
      }
      for (final dot in d.dots) {
        final p = Offset(c.dx + dot.du * unit, c.dy + dot.dv * unit);
        out.add(
          _StainSpot.solid(
            Path()..addOval(Rect.fromCircle(center: p, radius: dot.r * unit)),
            0.78 - 0.3 * soft,
          ),
        );
      }
    }
    // Мелочь льётся плотным цветом и почти не сжата по вертикали: на 1–4 px
    // «рваный» блин превратился бы в бесформенную точку.
    for (final s in specks) {
      final p = Offset(s.u * size.width, s.v * size.height);
      out.add(
        _StainSpot.solid(
          _splatPath(p, s.r * unit, 0.86, s.u * 9 + s.v * 5, soft),
          0.85 - 0.42 * soft,
        ),
      );
    }
    return out;
  }

  /// Блин от удара капли: круг, сжатый по вертикали, с рваным краем (три
  /// несозвучные гармоники) и стекающей вниз гранью. `soft` приглушает
  /// гармоники — край перестаёт быть зубчатым.
  static Path _splatPath(
    Offset c,
    double r,
    double squash,
    double seed,
    double soft,
  ) {
    final path = Path();
    const n = 40;
    final jag = 1 - 0.55 * soft;
    for (var i = 0; i <= n; i++) {
      final a = i / n * math.pi * 2;
      final w =
          1 +
          jag *
              (0.13 * math.sin(a * 3 + seed) +
                  0.085 * math.sin(a * 5 + seed * 1.7) +
                  0.05 * math.sin(a * 9 + seed * 0.6));
      final drip = math.max(0.0, math.sin(a)) * 0.16 * (1 - 0.5 * soft);
      final pt = Offset(
        c.dx + math.cos(a) * r * w,
        c.dy + math.sin(a) * r * (w * squash + drip),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  /// Полуразмеры отпечатка губ: [ширина, высота]. Отдельно от построения
  /// пути — ради градиентного ореола, который обязан повторять силуэт, а не
  /// быть кругом.
  ///
  /// Губы ШИРОКИЕ (≈2.4 : 1): круглый или почти квадратный отпечаток
  /// читается как «блоба», а не как поцелуй.
  static (double, double) _kissWH(double r, double squash) =>
      (r * 1.55, r * (0.52 + 0.16 * squash));

  /// Отпечаток губ («поцелуй»): два верхних бугра с впадинкой по центру и
  /// нижняя дуга с лёгкой ямкой посередине. Строится кубическими Безье
  /// вокруг начала координат, а не гармониками как блин: форма губ задана,
  /// случайность в ней только в наклоне.
  static Path _kissPath(Offset c, double r, double squash, double seed) {
    final (w, h) = _kissWH(r, squash);
    final p = Path()
      ..moveTo(-w, -h * 0.10)
      // Левый бугор верхней губы.
      ..cubicTo(-w * 0.99, -h * 0.86, -w * 0.60, -h, -w * 0.30, -h * 0.70)
      // Впадинка между буграми.
      ..cubicTo(-w * 0.15, -h * 0.52, -w * 0.05, -h * 0.42, 0, -h * 0.40)
      ..cubicTo(w * 0.05, -h * 0.42, w * 0.15, -h * 0.52, w * 0.30, -h * 0.70)
      // Правый бугор.
      ..cubicTo(w * 0.60, -h, w * 0.99, -h * 0.86, w, -h * 0.10)
      // Нижняя губа: дуга вниз с ямкой по центру.
      ..cubicTo(w * 0.95, h * 0.46, w * 0.56, h * 0.94, w * 0.18, h)
      ..cubicTo(w * 0.06, h * 1.02, -w * 0.06, h * 1.02, -w * 0.18, h)
      ..cubicTo(-w * 0.56, h * 0.94, -w * 0.95, h * 0.46, -w, -h * 0.10)
      ..close();
    // T·R: повернуть вокруг своего центра, затем перенести на место капли.
    final m = Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..rotateZ(0.14 * math.sin(seed * 2.3));
    return p.transform(m.storage);
  }

  /// Жгутик брызга: вытянутый эллипс от края пятна под своим углом.
  static Path _armPath(Offset c, _Arm a, double unit) {
    final width = a.width * unit;
    final m = Matrix4.translationValues(c.dx, c.dy, 0)..rotateZ(a.angle);
    // Path.transform возвращает копию — исходный овал выбрасываем.
    final oval = Path()
      ..addOval(Rect.fromLTRB(-width, -width, a.len * unit, width));
    return oval.transform(m.storage);
  }

  void draw(Canvas canvas, Color color, double alpha) {
    // Краски пересобираются ТОЛЬКО когда меняется цвет или плотность заливки.
    // Геометрия узора уже кэшируется по размеру, а `paint()` вызывается каждый
    // кадр прокрутки (капсула разделов висит под BackdropFilter), так что без
    // этого кэша ~60 Paint'ов и 60 RadialGradient-шейдеров создавались на
    // ровном месте 60 раз в секунду — на Adreno 610 это прямые микрофризы.
    var paints = _paints;
    if (paints == null ||
        paints.length != spots.length ||
        _paintColor != color ||
        _paintAlpha != alpha) {
      paints = [for (final sp in spots) _paintFor(sp, color, alpha)];
      _paints = paints;
      _paintColor = color;
      _paintAlpha = alpha;
    }
    for (var i = 0; i < spots.length; i++) {
      canvas.drawPath(spots[i].path, paints[i]);
    }
  }

  static Paint _paintFor(_StainSpot sp, Color color, double alpha) {
    final a = alpha * sp.core;
    final paint = Paint()..isAntiAlias = true;
    final rect = sp.gradRect;
    if (rect == null) {
      return paint..color = color.withValues(alpha: a);
    }
    // Перо (режим «размытое пятно») — ядро сходит на нет раньше и плавнее:
    // у обычного пятна граница держится до 0.82 радиуса, иначе на стекле
    // оставалась бы заметная кромка, которую и просили убрать.
    return paint
      ..shader = RadialGradient(
        center: const Alignment(-0.24, -0.3),
        radius: 1.0,
        colors: sp.feather
            ? [
                color.withValues(alpha: a),
                color.withValues(alpha: a * 0.62),
                color.withValues(alpha: a * 0.22),
                color.withValues(alpha: 0.0),
              ]
            : [
                color.withValues(alpha: a),
                color.withValues(alpha: a * 0.72),
                color.withValues(alpha: a * 0.24),
                color.withValues(alpha: 0.0),
              ],
        stops: sp.feather
            ? const [0.0, 0.30, 0.58, 1.0]
            : const [0.0, 0.5, 0.82, 1.0],
      ).createShader(rect);
  }
}
