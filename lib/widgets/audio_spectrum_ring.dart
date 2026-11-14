import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/music_service.dart';
import '../utils/motion_prefs.dart';

/// Живой неоновый аудиоспектр вокруг аватарки в профиле.
///
/// Когда музыка играет ([MusicService.playing]), радиальные лучи-эквалайзеры
/// плавно танцуют вокруг аватара в такт ритму с киберпанк-градиентом.
/// В режиме паузы спектр сворачивается в мягкое, едва дышащее неоновое кольцо-ауру.
class AudioSpectrumRing extends StatefulWidget {
  final double radius;
  final Widget child;

  const AudioSpectrumRing({
    super.key,
    required this.radius,
    required this.child,
  });

  @override
  State<AudioSpectrumRing> createState() => _AudioSpectrumRingState();
}

class _AudioSpectrumRingState extends State<AudioSpectrumRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final MusicService _music = MusicService();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    if (_music.playing && !MotionPrefs.shouldReduceMotion) {
      _controller.repeat();
    }
    _music.addListener(_onMusicChanged);
  }

  void _onMusicChanged() {
    if (!mounted) return;
    if (_music.playing) {
      if (!MotionPrefs.shouldReduceMotion && !_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      _controller.stop();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _music.removeListener(_onMusicChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = _music.playing;
    final reduceMotion = MotionPrefs.shouldReduceMotion;

    if (reduceMotion) {
      return widget.child;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SpectrumPainter(
            progress: _controller.value,
            isPlaying: isPlaying,
            primaryColor: theme.colorScheme.primary,
            secondaryColor: theme.colorScheme.secondary,
            radius: widget.radius,
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color primaryColor;
  final Color secondaryColor;
  final double radius;

  // Кэшированные кисти для 0-allocation во время отрисовки
  final Paint _barPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

  _SpectrumPainter({
    required this.progress,
    required this.isPlaying,
    required this.primaryColor,
    required this.secondaryColor,
    required this.radius,
  });

  static const int _barCount = 36;
  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = radius + 4.0;
    final phase = progress * _tau;

    // Фоновая мягкая аура
    if (isPlaying) {
      final auraRadius = baseRadius + 3.0 + math.sin(phase * 2) * 2.0;
      final auraPaint = Paint()
        ..color = primaryColor.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
      canvas.drawCircle(center, auraRadius, auraPaint);
    }

    final barWidth = (baseRadius * _tau / _barCount) * 0.42;
    _barPaint.strokeWidth = barWidth.clamp(1.5, 3.2);
    _glowPaint.strokeWidth = _barPaint.strokeWidth * 1.5;

    for (var i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * _tau - math.pi / 2;

      // Моделирование гармоник частот: басы, средние, высокие частоты
      final f1 = math.sin(phase * 3.0 + i * 0.55);
      final f2 = math.cos(phase * 1.8 - i * 0.35);
      final f3 = math.sin(phase * 5.2 + i * 1.1);

      double height;
      if (isPlaying) {
        // Живой энергичный спектр высотой до 16 px
        final norm = (f1 * 0.45 + f2 * 0.35 + f3 * 0.20).abs();
        height = 3.0 + norm * 13.0;
      } else {
        // В паузе — деликатное дыхание 1.5..3.0 px
        final breath = (math.sin(phase + i * 0.2) + 1.0) * 0.5;
        height = 1.0 + breath * 1.8;
      }

      final rInner = baseRadius;
      final rOuter = baseRadius + height;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final p1 = Offset(center.dx + rInner * cosA, center.dy + rInner * sinA);
      final p2 = Offset(center.dx + rOuter * cosA, center.dy + rOuter * sinA);

      // Неоновый перелив цвета по окружности (Primary -> Secondary -> Amber)
      final colorFraction = (i / _barCount + progress * 0.3) % 1.0;
      final barColor = Color.lerp(
        primaryColor,
        secondaryColor,
        (math.sin(colorFraction * _tau) + 1.0) * 0.5,
      )!;

      final alpha = isPlaying ? (0.65 + (height / 16.0) * 0.35) : 0.28;
      _barPaint.color = barColor.withValues(alpha: alpha);

      if (isPlaying && height > 8.0) {
        _glowPaint.color = barColor.withValues(alpha: 0.35);
        canvas.drawLine(p1, p2, _glowPaint);
      }

      canvas.drawLine(p1, p2, _barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isPlaying != isPlaying ||
        oldDelegate.primaryColor != primaryColor;
  }
}
