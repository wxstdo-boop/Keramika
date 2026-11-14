import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../utils/motion_prefs.dart';

/// Элемент парящей частицы дзена
class _ZenParticle {
  final Offset origin;
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double createdAt;

  _ZenParticle({
    required this.origin,
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
    required this.createdAt,
  });
}

/// Виджет-оверлей парящих частиц дзена.
class ZenParticlesOverlay extends StatefulWidget {
  final Widget child;

  const ZenParticlesOverlay({
    super.key,
    required this.child,
  });

  static ZenParticlesOverlayState? of(BuildContext context) {
    return context.findAncestorStateOfType<ZenParticlesOverlayState>();
  }

  @override
  State<ZenParticlesOverlay> createState() => ZenParticlesOverlayState();
}

class ZenParticlesOverlayState extends State<ZenParticlesOverlay>
    with SingleTickerProviderStateMixin {
  final List<_ZenParticle> _particles = [];
  Ticker? _ticker;
  double _time = 0;
  Duration _lastDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastDuration == Duration.zero) {
      _lastDuration = elapsed;
      return;
    }
    final dt = (elapsed - _lastDuration).inMicroseconds / 1000000.0;
    _lastDuration = elapsed;

    _time += dt;
    _particles.removeWhere((p) => (_time - p.createdAt) > 0.85);

    if (_particles.isEmpty) {
      _ticker?.stop();
      _lastDuration = Duration.zero;
    }
    setState(() {});
  }

  void spawnParticles(Offset localPosition, Color baseColor, {int count = 7}) {
    if (MotionPrefs.shouldReduceMotion) return;
    final random = math.Random();
    for (var i = 0; i < count; i++) {
      final angle = -math.pi / 2 + (random.nextDouble() - 0.5) * 1.5;
      final speed = 40.0 + random.nextDouble() * 65.0;
      final size = 3.2 + random.nextDouble() * 4.5;
      final color = Color.lerp(
        baseColor,
        Colors.amberAccent,
        random.nextDouble(),
      )!;

      _particles.add(
        _ZenParticle(
          origin: localPosition,
          angle: angle,
          speed: speed,
          size: size,
          color: color,
          createdAt: _time,
        ),
      );
    }
    if (_particles.length > 50) {
      _particles.removeRange(0, _particles.length - 50);
    }
    if (!(_ticker?.isActive ?? false)) {
      _lastDuration = Duration.zero;
      _ticker?.start();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _ZenPainter(
        particles: _particles,
        time: _time,
      ),
      child: widget.child,
    );
  }
}

class _ZenPainter extends CustomPainter {
  final List<_ZenParticle> particles;
  final double time;

  _ZenPainter({
    required this.particles,
    required this.time,
  });

  final Paint _paint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final age = time - p.createdAt;
      if (age < 0 || age > 0.85) continue;
      final progress = age / 0.85;

      final dist = p.speed * age;
      final dx = p.origin.dx + math.cos(p.angle) * dist;
      final dy = p.origin.dy + math.sin(p.angle) * dist - (age * age * 35.0);

      final alpha = (1.0 - progress).clamp(0.0, 1.0);
      final currentSize = p.size * (1.0 - progress * 0.4);

      _paint.color = p.color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(dx, dy), currentSize, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ZenPainter oldDelegate) => true;
}
