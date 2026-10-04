import 'dart:math';
import 'package:flutter/material.dart';

/// «Метель» — подарочная тема 12-го дня ивента: северное сияние по снегу.
///
/// Это ТОТ же приём, что и пятна MUTILATED: слой лежит поверх контента,
/// ничего не блокирует (`IgnorePointer`) и живёт в своём [RepaintBoundary],
/// поэтому перерисовывается только он, а не весь экран.
///
/// Почему так дёшево: телефон автора raster-bound (Adreno 610, 1080×2400,
/// бюджет кадра 16.6 мс), а узкое место здесь — fill-rate. Поэтому ни
/// `ImageFiltered`, ни `saveLayer`, ни масок: семь радиальных градиентов
/// (шейдеры кешируются по размеру холста, а двигается и «дышит» всё дешёвой
/// трансформацией и colorFilter'ом) и горстка примитивов-снежинок. Ленты
/// сияния набраны перекрывающимися сегментами ОДНОГО шейдера: волна ленты —
/// это сдвиг примитивов, а не новая сборка градиента. Фаза цикла квантована
/// до 1/96 — это ~8 видимых изменений в секунду: за один шаг полоса
/// смещается меньше чем на пиксель, глаз разницы не видит, а работы
/// растеризатору в разы меньше.
class MetelAurora extends StatefulWidget {
  final Widget child;

  const MetelAurora({super.key, required this.child});

  @override
  State<MetelAurora> createState() => _MetelAuroraState();
}

class _MetelAuroraState extends State<MetelAurora>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Band> _bands;
  late final List<_Flake> _flakes;
  final _ShaderCache _cache = _ShaderCache();

  @override
  void initState() {
    super.initState();
    // Ручной seed: картина темы не должна «пересохраняться» при каждом
    // перезапуске, иначе сияние каждый раз прыгает по новым местам.
    final rng = Random(20270101);
    // ДВЕ широкие подсветки (небо сверху, снег снизу) плюс ВЕРТИКАЛЬНЫЕ
    // ЛЕНТЫ. Ленты — главное: без них картина была цветной кляксой, а
    // северное сияние — это стоячие, слегка наклонённые полотнища, уходящие
    // за верх экрана. Каждая лента набрана тремя перекрывающимися сегментами
    // одного шейдера и волной по X: сегмент узкий (0.09–0.14 экрана) и в
    // несколько раз выше себя, край уходит за пределы холста, поэтому
    // скруглённых «шаров» не видно — полотно стоит.
    _bands = [
      const _Band(dy: 0.02, wf: 1.70, hf: 0.30, hue: 0.10, alpha: 0.26),
      const _Band(dy: 0.94, wf: 1.70, hf: 0.30, hue: 0.70, alpha: 0.24),
      const _Band(
        curtain: true,
        dx: 0.20,
        dy: 0.20,
        wf: 0.16,
        hf: 0.30,
        tilt: -0.15,
        hue: 0.00,
        alpha: 0.40,
        segs: 3,
      ),
      const _Band(
        curtain: true,
        dx: 0.42,
        dy: 0.16,
        wf: 0.11,
        hf: 0.28,
        tilt: 0.10,
        hue: 0.14,
        alpha: 0.32,
        segs: 3,
      ),
      const _Band(
        curtain: true,
        dx: 0.64,
        dy: 0.22,
        wf: 0.18,
        hf: 0.32,
        tilt: -0.09,
        hue: 0.30,
        alpha: 0.34,
        segs: 3,
      ),
      const _Band(
        curtain: true,
        dx: 0.87,
        dy: 0.14,
        wf: 0.12,
        hf: 0.26,
        tilt: 0.16,
        hue: 0.48,
        alpha: 0.30,
        segs: 3,
      ),
    ];
    _flakes = List.generate(34, (_) {
      return _Flake(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        r: 1.4 + rng.nextDouble() * 2.2,
        alpha: 0.10 + rng.nextDouble() * 0.16,
        seed: rng.nextDouble() * pi * 2,
        // Снег идёт вниз и его сносит ветром: каждая снежинка — со своей
        // скоростью и своим сносом, иначе «метель» выглядит вихрем из одной
        // точки. Скорость в долях экрана за цикл (12 с).
        speed: 0.022 + rng.nextDouble() * 0.055,
        wind: 0.10 + rng.nextDouble() * 0.30,
      );
    });
    _cache.bands = _bands;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _cache.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) => CustomPaint(
                  painter: _AuroraPainter(
                    cache: _cache,
                    flakes: _flakes,
                    t: (_ctrl.value * 96).roundToDouble() / 96,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Северное сияние: мята → лазурь → фиолет, тот же круг, что и у скина
/// скважины на ПИН-экране, чтобы подарок читался одним набором.
const List<Color> _kAurora = [
  Color(0xFF2FBF94),
  Color(0xFF4FB6E8),
  Color(0xFF7C6BE0),
];

Color _auroraAt(double x) {
  final p = (x % 1.0) * _kAurora.length;
  final i = p.floor() % _kAurora.length;
  final j = (i + 1) % _kAurora.length;
  return Color.lerp(_kAurora[i], _kAurora[j], p - p.floor())!;
}

/// Одна полоса сияния: горизонтальная подсветка (`curtain: false`) или
/// вертикальная лента. Размеры — доли экрана, `tilt` — наклон ленты,
/// `segs` — сколько перекрывающихся сегментов набирает полотно.
class _Band {
  final bool curtain;
  final double dx;
  final double dy;
  final double wf;
  final double hf;
  final double tilt;
  final double hue;
  final double alpha;
  final int segs;

  const _Band({
    this.curtain = false,
    this.dx = 0.5,
    required this.dy,
    required this.wf,
    required this.hf,
    this.tilt = 0,
    required this.hue,
    required this.alpha,
    this.segs = 1,
  });
}

/// Снежинка: якорь на экране, радиус, плотность, фаза покачивания и скорость
/// падения со сносом ветром.
class _Flake {
  final double dx;
  final double dy;
  final double r;
  final double alpha;
  final double seed;

  /// Долей экрана за цикл: насколько снежинка успевает упасть за 12 с.
  final double speed;

  /// Снос ветром: во сколько раз горизонтальный уход больше вертикального.
  final double wind;

  const _Flake({
    required this.dx,
    required this.dy,
    required this.r,
    required this.alpha,
    required this.seed,
    required this.speed,
    required this.wind,
  });
}

/// Шейдеры полос пересоздаются только при смене размера холста. Каждая полоса
/// кешируется в координатах с центром в нуле: дальше двигать её можно
/// трансформацией холста, без новой сборки градиента. Лента несёт несколько
/// шейдеров — по одному на сегмент, потому что тон и плотность по высоте
/// ленты разные.
///
/// ВАЖНО, на чём обжёгся: `RadialGradient.createShader(rect)` НЕ растягивает
/// круг в овал — радиус берётся как `radius * min(rect.width, rect.height)`,
/// то есть градиент всегда КРУГ. Поэтому шейдер строится для квадрата со
/// стороной `s` (ширина полосы), а нужную высоту полоса получает дешёвой
/// `canvas.scale(1, sAspect)` — так и ленты стоят вертикально, а не выглядят
/// цветными кляксами.
class _ShaderCache {
  List<_Band>? bands;
  Size? _size;
  List<List<Shader>>? _shaders;

  List<List<Shader>> forSize(Size size, List<_Band> bands) {
    final cur = _shaders;
    if (cur != null && _size == size) return cur;
    _size = size;
    final w = size.width;
    _shaders = [
      for (final b in bands)
        [
          for (var s = 0; s < b.segs; s++)
            _shade(
              b,
              b.segs == 1 ? 0.0 : s / (b.segs - 1),
              Rect.fromLTWH(-w * b.wf / 2, -w * b.wf / 2, w * b.wf, w * b.wf),
            ),
        ],
    ];
    return _shaders!;
  }

  /// `up` — положение в ленте: 0 у нижнего края, 1 у верхнего.
  Shader _shade(_Band b, double up, Rect square) {
    // У настоящего сияния низ полотна плотный и зелёный, а к верху оно
    // выгорает в фиолет. Тот же порядок держим по сегментам ленты.
    final hue = b.hue + up * 0.26;
    final a = b.alpha * (1.0 - 0.36 * up);
    return RadialGradient(
      colors: [
        _auroraAt(hue).withValues(alpha: a),
        _auroraAt(hue + 0.30).withValues(alpha: a * 0.62),
        _auroraAt(hue + 0.30).withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.46, 1.0],
    ).createShader(square);
  }

  void dispose() {
    _shaders = null;
    _size = null;
  }
}

class _AuroraPainter extends CustomPainter {
  final _ShaderCache cache;
  final List<_Flake> flakes;
  final double t;

  _AuroraPainter({required this.cache, required this.flakes, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final bands = cache.bands;
    if (bands == null || size.isEmpty) return;
    final shaders = cache.forSize(size, bands);
    final paint = Paint()..isAntiAlias = true;
    final phase = t * pi * 2;
    final w = size.width;
    final h = size.height;

    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      // Дрейф: подсветки гуляют слабо, ленты — сильнее, и каждая со своей
      // фазой, иначе всё небо «дышит» одним горлом.
      final sway = sin(phase + i * 1.9) * w * (b.curtain ? 0.045 : 0.02);
      final swell = 1.0 + 0.10 * sin(phase * 0.5 + i * 2.3);
      final cx = w / 2 + sway + (b.curtain ? (b.dx - 0.5) * w : 0);
      final tilt = b.tilt * (1 + 0.35 * sin(phase * 0.5 + i * 1.3));
      // Шаг сегмента заметно меньше его высоты: соседние перекрываются ровно
      // настолько, чтобы в месте стыка сумма двух спадов давала ту же
      // плотность, что и в центре, — иначе лента распадается на отдельные
      // «сигары» с провалами между ними.
      final step = b.hf * 0.55;
      // Полоса рисуется квадратом со стороной w*wf и растягивается по Y:
      // круглый градиент становится вытянутым овалом без всякого blur.
      final side = w * b.wf;
      final aspect = h * b.hf / side;
      for (var s = 0; s < b.segs; s++) {
        // s=0 — нижний край ленты. Дальше сегменты идут вверх, а волна по X
        // растёт кверху: полотно не просто наклонено, его «ведёт» ветром, как
        // настоящую авроральную занавесу.
        final along = ((b.segs - 1) / 2 - s) * step;
        final wave = b.curtain
            ? sin(phase * 0.5 + i * 1.1 - s * 0.9) * w * 0.026
            : 0.0;
        // Плотность = alpha шейдера × breathe. Через color это не работает:
        // при заданном shader цвет краски игнорируется. modulate умножает
        // только прозрачность, тон полосы не трогает и не требует saveLayer.
        paint
          ..shader = shaders[i][s]
          ..colorFilter = ColorFilter.mode(
            Color.fromRGBO(
              255,
              255,
              255,
              0.72 + 0.28 * sin(phase + i * 1.9 + s * 0.7),
            ),
            BlendMode.modulate,
          );
        canvas
          ..save()
          ..translate(cx + wave, h * (b.dy + along))
          // Наклон живой: лента ходит туда-сюда вокруг своего угла, а не
          // стоит, привязанная линейкой.
          ..rotate(tilt)
          ..scale(1.0, aspect * swell)
          ..drawRect(Rect.fromLTWH(-side / 2, -side / 2, side, side), paint)
          ..restore();
      }
    }

    // Снежинки — холодного сине-серого оттенка: на почти белом фоне белая
    // пылинка не видна вовсе. Крупные идут КОРОТКИМ ШТРИХОМ вниз: так снег
    // читается падающим, а не рассыпанным по экрану мусором, а штрих с
    // круглыми торцами стоит ровно столько же, сколько круг.
    //
    // Раньше они только покачивались вокруг своей точки — для темы с именем
    // «Метель» это было ничем. Теперь снег ИДЁТ: своя скорость вниз и снос
    // ветром, с выходом за край и возвращением сверху (по модулю, доля
    // экрана, а не пиксели — телепорта на глазах не видно).
    final snow = Paint()
      ..isAntiAlias = true
      ..strokeCap = StrokeCap.round;
    for (final f in flakes) {
      final fall = (f.dy + t * f.speed) % 1.0;
      final gust = sin(phase * 0.5 + f.seed) * 0.014;
      final sway = sin(phase + f.seed) * 0.004;
      final x = ((f.dx + fall * f.wind * 0.25 + gust + sway) % 1.0) * w;
      final y = fall * h;
      snow.color = const Color(0xFF5C7C8C).withValues(alpha: f.alpha);
      if (f.r > 2.4) {
        snow.strokeWidth = f.r * 1.5;
        canvas.drawLine(
          Offset(x, y),
          Offset(x + gust * w * 0.4, y + f.r * 3.2),
          snow,
        );
      } else {
        canvas.drawCircle(Offset(x, y), f.r, snow);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.t != t;
}
