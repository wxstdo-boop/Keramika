import 'dart:math';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';

/// Лёгкие, еле заметные «кровавые пятна» поверх фона темы MUTILATED.
/// Это не полноценные Splash'и — фон почти не меняется, а пятна чуть
/// «дышат», чтобы на слабых телефонах картинка не «залипала»,
/// при этом не отвлекала от контента.
///
/// Оптимизация для слабых устройств: шейдеры радиальных градиентов
/// создаются ОДИН раз на размер экрана и кэшируются в State — в paint()
/// остаются только дешёвые drawCircle. Раньше каждый кадр пересоздавал
/// 9 RadialGradient + createShader, что грузило GPU-пайплайн Redmi Note 12.
class MutilatedSplatter extends StatefulWidget {
  final Widget child;

  const MutilatedSplatter({super.key, required this.child});

  @override
  State<MutilatedSplatter> createState() => _MutilatedSplatterState();
}

class _MutilatedSplatterState extends State<MutilatedSplatter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Splatter> _spots;
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);
  final _ShaderCache _cache = _ShaderCache();

  @override
  void initState() {
    super.initState();
    final rng = Random(20260811);
    _spots = List.generate(9, (_) {
      return _Splatter(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        r: 28 + rng.nextDouble() * 70,
        alpha: 0.06 + rng.nextDouble() * 0.05,
        seed: rng.nextDouble() * pi * 2,
      );
    });
    _cache.spots = _spots;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..addListener(_syncPhase);
    _ctrl.repeat();
  }

  void _syncPhase() {
    final phase = (_ctrl.value * 96).roundToDouble() / 96;
    if (_phase.value != phase) _phase.value = phase;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _phase.dispose();
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
            // Свой слой обязателен: пятна «дышат» всё время, а без границы
            // перерисовки они красятся в тот же слой, что и весь контент под
            // ними, — то есть за каждый кадр заново растеризуется весь экран.
            // Порядок отрисовки и картинка не меняются вообще.
            child: RepaintBoundary(
              // Фаза обновляется только при переходе к следующему из тех
              // же 96 кадров. Painter слушает её напрямую: видимые кадры и
              // тайминг прежние, а дерево и delegate больше не создаются
              // на каждом тике контроллера.
              child: CustomPaint(
                painter: _SplatterPainter(cache: _cache, phase: _phase),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Цвета пятна, предвычисленные один раз (вместо withValues на каждый кадр).
class _SpotColors {
  final Color inner;
  final Color outer;
  const _SpotColors(this.inner, this.outer);
}

class _Splatter {
  final double dx;
  final double dy;
  final double r;
  final double alpha;
  final double seed;
  const _Splatter({
    required this.dx,
    required this.dy,
    required this.r,
    required this.alpha,
    required this.seed,
  });
}

/// Кэш шейдеров: пересоздаются только когда меняется размер холста.
class _ShaderCache {
  List<_Splatter>? spots;
  Size? _size;
  List<Shader>? _shaders;
  List<_SpotColors>? _colors;

  List<Shader> forSize(Size size, List<_Splatter> spots) {
    final cur = _shaders;
    if (cur != null && _size == size) return cur;
    _size = size;
    _colors ??= [
      for (final s in spots)
        _SpotColors(
          const Color(0xFFB8122C).withValues(alpha: s.alpha + 0.04),
          const Color(0xFFB8122C).withValues(alpha: 0.0),
        ),
    ];
    _shaders = [
      for (var i = 0; i < spots.length; i++)
        RadialGradient(
          colors: [_colors![i].inner, _colors![i].outer],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(
            center: Offset(spots[i].dx * size.width, spots[i].dy * size.height),
            radius: spots[i].r,
          ),
        ),
    ];
    return _shaders!;
  }

  void dispose() {
    _shaders = null;
    _colors = null;
    _size = null;
  }
}

class _SplatterPainter extends CustomPainter {
  final _ShaderCache cache;
  final ValueListenable<double> phase;
  _SplatterPainter({required this.cache, required this.phase})
    : super(repaint: phase);

  @override
  void paint(Canvas canvas, Size size) {
    final t = phase.value;
    final spots = cache.spots;
    if (spots == null || spots.isEmpty) return;
    final shaders = cache.forSize(size, spots);
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < spots.length; i++) {
      final s = spots[i];
      final bob = sin(t * pi * 2 + s.seed) * 4.0;
      final cy = s.dy * size.height + bob;
      paint.shader = shaders[i];
      canvas.drawCircle(Offset(s.dx * size.width, cy), s.r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SplatterPainter oldDelegate) =>
      oldDelegate.cache != cache || oldDelegate.phase != phase;
}
