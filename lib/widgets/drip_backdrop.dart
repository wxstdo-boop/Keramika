import 'dart:math';
import 'package:flutter/material.dart';

/// Живой фон окна KID: редкие мягкие пятна, которые стекают ОТ фирменной
/// капсулы KID вниз, к медальону ПИНа — то есть живут в одной вертикальной
/// колонне, а не «дождём» по всему экрану.
///
/// Оба конца колонны растворены в ноль ([ShaderMask] с вертикальным
/// градиентом), поэтому пятно не «вырезается» верхней границей и не
/// обрывается нижней: оно проявляется из-под капсулы и гаснет перед
/// медальоном. Палитра целиком берётся из темы, поэтому фон меняется
/// вместе с Material You и всегда остаётся «в бренде».
///
/// Бережно к слабым GPU (Redmi Note 12, Adreno 610):
///  * шейдеры пятен создаются ОДИН раз (пятно рисуется в translated холсте
///    вокруг начала координат, поэтому позиция не влияет на шейдер);
///  * маска-фейд пересоздаётся только при смене размера, а не в кадре;
///  * кадр берётся с кванта 1/140 цикла (~12 fps при 11 с) — ступенек глаз
///    не видит, а fill-rate падает в 5 раз;
///  * весь слой обёрнут в RepaintBoundary, так что перерисовка пятен не
///    трогает контент PIN-экрана и не гоняет заново размытие стекол.
class DripBackdrop extends StatefulWidget {
  const DripBackdrop({
    super.key,
    required this.colors,
    this.dripCount = 5,
    this.duration = const Duration(seconds: 11),
    this.top = 0.0,
    this.bottom = 1.0,
    this.xCenter = 0.5,
    this.xSpread = 0.5,
    this.fade = 0.16,
  });

  /// Палитра темы — пятна берутся из неё по кругу.
  final List<Color> colors;
  final int dripCount;
  final Duration duration;

  /// Доли высоты холста, между которыми живёт колонна пятен.
  final double top;
  final double bottom;

  /// Центр и ширина колонны по горизонтали (доли ширины холста).
  final double xCenter;
  final double xSpread;

  /// Доля высоты колонны, на которой пятна растворяются сверху и снизу.
  final double fade;

  @override
  State<DripBackdrop> createState() => _DripBackdropState();
}

class _DripBackdropState extends State<DripBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Drip> _drips;
  final Map<int, Shader> _blobs = {};

  Shader? _maskShader;
  Size _maskSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _drips = _buildDrips();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant DripBackdrop old) {
    super.didUpdateWidget(old);
    if (old.colors != widget.colors ||
        old.dripCount != widget.dripCount ||
        old.top != widget.top ||
        old.bottom != widget.bottom ||
        old.xCenter != widget.xCenter ||
        old.xSpread != widget.xSpread ||
        old.fade != widget.fade) {
      // Смена темы/геометрии — пересобираем пятна и сбрасываем кэши.
      _drips = _buildDrips();
      _blobs.clear();
      _maskShader = null;
    }
  }

  List<_Drip> _buildDrips() {
    final rng = Random(7301);
    final n = widget.dripCount;
    final t = widget.top;
    final b = widget.bottom;
    return List.generate(n, (i) {
      final color = widget.colors[i % widget.colors.length];
      return _Drip(
        index: i,
        // Колонна, а не весь экран: x разбросан вокруг центра капсулы KID.
        x: widget.xCenter - widget.xSpread / 2 + rng.nextDouble() * widget.xSpread,
        y0: t + (b - t) * (0.34 * rng.nextDouble()),
        y1: t + (b - t) * (0.66 + 0.34 * rng.nextDouble()),
        radius: 22 + rng.nextDouble() * 30,
        tail: 0.10 + rng.nextDouble() * 0.18,
        offset: i / n + rng.nextDouble() * 0.12,
        sway: 5 + rng.nextDouble() * 9,
        color: color,
      );
    });
  }

  /// Шейдер мягкого пятна для конкретного drip. Рисуем пятно всегда вокруг
  /// (0,0), поэтому шейдер не зависит от позиции и создаётся один раз.
  Shader _blobShader(_Drip d) {
    final cached = _blobs[d.index];
    if (cached != null) return cached;
    final shader = RadialGradient(
      colors: [
        d.color.withValues(alpha: 0.26),
        d.color.withValues(alpha: 0.10),
        d.color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: d.radius));
    _blobs[d.index] = shader;
    return shader;
  }

  /// Маска: прозрачно → плотно → прозрачно по вертикали. Пересоздаётся
  /// ТОЛЬКО когда меняется размер холста.
  Shader _maskFor(Rect bounds) {
    final cur = _maskShader;
    final size = bounds.size;
    if (cur != null && _maskSize == size) return cur;
    final f = widget.fade.clamp(0.02, 0.45);
    _maskShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0x00FFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0.0, f, 1.0 - f, 1.0],
    ).createShader(Offset.zero & size);
    _maskSize = size;
    return _maskShader!;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: _maskFor,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) => CustomPaint(
              // Квантование фазы: при неизменной фазе shouldRepaint == false,
              // и Skia переиспользует готовый растр вместо новой растеризации.
              painter: _DripPainter(
                drips: _drips,
                t: (_ctrl.value * 140).roundToDouble() / 140,
                blobShaderFor: _blobShader,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ),
    );
  }
}

class _Drip {
  _Drip({
    required this.index,
    required this.x,
    required this.y0,
    required this.y1,
    required this.radius,
    required this.tail,
    required this.offset,
    required this.sway,
    required this.color,
  });

  final double x;

  /// Доли высоты, откуда капля вытекает и куда стекает.
  final double y0;
  final double y1;
  final double radius;

  /// Длина шлейфа как доля высоты холста.
  final double tail;

  /// Сдвиг фазы, чтобы пятна не шли синхронным «строем».
  final double offset;
  final double sway;
  final Color color;

  /// Позиция в списке — ключ для кэша шейдеров (заполняется при построении).
  final int index;
}

class _DripPainter extends CustomPainter {
  _DripPainter({
    required this.drips,
    required this.t,
    required this.blobShaderFor,
  });

  final List<_Drip> drips;
  final double t;
  final Shader Function(_Drip) blobShaderFor;

  @override
  void paint(Canvas canvas, Size size) {
    final blob = Paint()..isAntiAlias = true;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var i = 0; i < drips.length; i++) {
      final d = drips[i];

      // Локальная фаза капли + плавный разгон/торможение внутри цикла.
      final p = (t + d.offset) % 1.0;
      final eased = Curves.easeInOutCubic.transform(p);

      final h = size.height;
      final from = d.y0 * h - d.radius - d.tail * h;
      final to = d.y1 * h + d.radius;
      final cy = from + (to - from) * eased;
      final cx = d.x * size.width + sin((p * 2 * pi) + d.offset * 7) * d.sway;

      // Шлейф: тянем за каплей, удлиняя по мере разгона.
      final trailLen = d.tail * h * (0.25 + 0.75 * eased);
      trail.color = d.color.withValues(alpha: 0.09);
      trail.strokeWidth = d.radius * 0.32;
      canvas.drawLine(Offset(cx, cy - trailLen), Offset(cx, cy), trail);

      // Само пятно — мягкий радиальный градиент (шейдер закэширован).
      canvas.save();
      canvas.translate(cx, cy);
      blob.shader = blobShaderFor(d);
      canvas.drawCircle(Offset.zero, d.radius, blob);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _DripPainter old) =>
      old.t != t || old.drips != drips;
}
