import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Одна выпуклость глиняной поверхности.
class _Bump {
  const _Bump(this.center, this.radius, this.lean);

  final Offset center;
  final double radius;

  /// Небольшой сдвиг света у конкретной выпуклости — поверхность не
  /// выглядит штампованной сеткой.
  final double lean;
}

/// Матовая глиняная поверхность с «пупырками»: объём лепится светом, а не
/// бликом. У каждой выпуклости светлое пятно сверху-слева и мягкая тень
/// снизу-справа — плоская заливка читается как вылепленная из глины.
///
/// Позиции выпуклостей берутся из seeded-RNG и кэшируются по (размер, seed),
/// поэтому поверхность рисуется ОДИН раз, а [RepaintBoundary] держит готовую
/// текстуру: на прокрутке и переходах ничего не пересчитывается.
class ClaySurface extends StatelessWidget {
  const ClaySurface({
    super.key,
    required this.base,
    required this.isDark,
    this.gradient,
    this.seed = 7,
    this.bumpScale = 1.0,
    this.strength = 1.0,
    this.fill = true,
    this.child,
  });

  /// Базовый цвет (если не задан [gradient]).
  final Color base;

  /// Тёмная тема: свет и тень тише, иначе глина «блестит».
  final bool isDark;

  /// Базовая заливка под выпуклостями.
  final Gradient? gradient;

  final int seed;

  /// Множитель размера выпуклостей: 1 — крупная глина, 2 — мелкая.
  final double bumpScale;

  /// Общая сила света и тени (0 — плоско).
  final double strength;

  /// Рисовать ли базовую заливку. `false` — только выпуклости и зерно
  /// поверх уже нарисованного (например, поверх логотипа).
  final bool fill;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ClaySurfacePainter(
          base: base,
          isDark: isDark,
          gradient: gradient,
          seed: seed,
          bumpScale: bumpScale,
          strength: strength,
          fill: fill,
        ),
        child: child,
      ),
    );
  }
}

class _ClaySurfacePainter extends CustomPainter {
  _ClaySurfacePainter({
    required this.base,
    required this.isDark,
    required this.gradient,
    required this.seed,
    required this.bumpScale,
    required this.strength,
    required this.fill,
  });

  final Color base;
  final bool isDark;
  final Gradient? gradient;
  final int seed;
  final double bumpScale;
  final double strength;
  final bool fill;

  static final Map<String, List<_Bump>> _bumpCache = {};
  static final Map<String, List<(Offset, bool)>> _grainCache = {};

  static List<_Bump> _bumpsFor(Size size, int seed, double bumpScale) {
    final key = '${size.width.round()}x${size.height.round()}:$seed:$bumpScale';
    final cached = _bumpCache[key];
    if (cached != null) return cached;
    final rnd = math.Random(seed);
    final list = <_Bump>[];
    final cell = size.shortestSide / (5.0 * bumpScale);
    final cols = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    for (var iy = -1; iy <= rows; iy++) {
      for (var ix = -1; ix <= cols; ix++) {
        final cx =
            ix * cell + cell * 0.5 + (rnd.nextDouble() - 0.5) * cell * 0.7;
        final cy =
            iy * cell + cell * 0.5 + (rnd.nextDouble() - 0.5) * cell * 0.7;
        final r = cell * (0.34 + rnd.nextDouble() * 0.26);
        list.add(_Bump(Offset(cx, cy), r, rnd.nextDouble() - 0.5));
      }
    }
    if (_bumpCache.length > 16) _bumpCache.clear();
    _bumpCache[key] = list;
    return list;
  }

  static List<(Offset, bool)> _grainFor(Size size, int seed) {
    final key = '${size.width.round()}x${size.height.round()}:$seed';
    final cached = _grainCache[key];
    if (cached != null) return cached;
    final rnd = math.Random(seed * 31 + 5);
    final list = <(Offset, bool)>[];
    final count = ((size.width * size.height) / 900).clamp(120, 480).round();
    for (var i = 0; i < count; i++) {
      list.add((
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        rnd.nextBool(),
      ));
    }
    if (_grainCache.length > 16) _grainCache.clear();
    _grainCache[key] = list;
    return list;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    if (fill) {
      if (gradient != null) {
        canvas.drawRect(rect, Paint()..shader = gradient!.createShader(rect));
      } else {
        canvas.drawRect(rect, Paint()..color = base);
      }
    }

    final bumps = _bumpsFor(size, seed, bumpScale);
    final hiA = (isDark ? 0.16 : 0.20) * strength;
    final loA = (isDark ? 0.24 : 0.15) * strength;

    // Тени всех выпуклостей — одно направление света (сверху-слева).
    final shadow = Paint();
    for (final b in bumps) {
      final c =
          b.center +
          Offset(
            b.radius * (0.26 + b.lean * 0.10),
            b.radius * (0.32 + b.lean * 0.08),
          );
      final rr = b.radius * 1.28;
      shadow.shader = RadialGradient(
        colors: [
          Colors.black.withValues(alpha: loA),
          Colors.black.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: rr));
      canvas.drawCircle(c, rr, shadow);
    }

    final light = Paint();
    for (final b in bumps) {
      final c =
          b.center -
          Offset(
            b.radius * (0.24 + b.lean * 0.08),
            b.radius * (0.28 + b.lean * 0.06),
          );
      light.shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: hiA),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: b.radius));
      canvas.drawCircle(c, b.radius, light);
    }

    // Мелкое зерно — «отпечаток пальца» на глине.
    final grainA = (isDark ? 0.035 : 0.028) * strength;
    if (grainA > 0.004) {
      final grain = Paint();
      for (final (o, isLight) in _grainFor(size, seed)) {
        grain.color = isLight
            ? Colors.white.withValues(alpha: grainA)
            : Colors.black.withValues(alpha: grainA);
        canvas.drawCircle(o, 0.8, grain);
      }
    }

    // Виньетка: края чуть глубже центра — поверхность «дышит» объёмом.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: (isDark ? 0.22 : 0.10) * strength),
          ],
          stops: const [0.62, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_ClaySurfacePainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.isDark != isDark ||
      oldDelegate.gradient != gradient ||
      oldDelegate.seed != seed ||
      oldDelegate.bumpScale != bumpScale ||
      oldDelegate.strength != strength ||
      oldDelegate.fill != fill;
}
