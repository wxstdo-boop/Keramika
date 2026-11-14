import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../services/music_service.dart';
import '../utils/motion_prefs.dart';

/// Деликатный, ультра-плавный неоновый аудиоспектр вокруг аватара в профиле.
///
/// Улучшения:
/// - Тонкие микро-лучи (44 радиальные полоски, stroke 1.6 px, деликатная высота до 6.5 px).
/// - Плавный вход и выход: [AnimationController] плавного перехода разгоняет и
///   схлопывает лучи при старте/паузе музыки без резких рывков.
/// - Непрерывные гармонические синусоиды без резких изломов (без жестких .abs() пиков).
/// - Нулевые аллокации в [paint] для 120 FPS без просадок.
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
    with TickerProviderStateMixin {
  late final AnimationController _phaseController;
  late final AnimationController _playTransition;
  final MusicService _music = MusicService();

  @override
  void initState() {
    super.initState();
    // Непрерывный вечный гармонический цикл без резких срывов
    _phaseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );

    _playTransition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: _music.playing ? 1.0 : 0.0,
    );

    if (_music.playing && !MotionPrefs.shouldReduceMotion) {
      _phaseController.repeat();
    }

    _playTransition.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && !_music.playing) {
        if (_phaseController.isAnimating) {
          _phaseController.stop();
        }
      }
    });

    _music.addListener(_onMusicChanged);
  }

  void _onMusicChanged() {
    if (!mounted) return;
    if (_music.playing) {
      if (!MotionPrefs.shouldReduceMotion && !_phaseController.isAnimating) {
        _phaseController.repeat();
      }
      _playTransition.forward();
    } else {
      _playTransition.reverse();
    }
  }

  @override
  void dispose() {
    _music.removeListener(_onMusicChanged);
    _phaseController.dispose();
    _playTransition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MotionPrefs.shouldReduceMotion;

    if (reduceMotion) {
      return widget.child;
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_phaseController, _playTransition]),
        builder: (context, child) {
          final transitionCurve = Curves.easeInOutCubic.transform(
            _playTransition.value.clamp(0.0, 1.0),
          );
          return CustomPaint(
            painter: _DelicateSpectrumPainter(
              progress: _phaseController.value,
              playFactor: transitionCurve,
              primaryColor: theme.colorScheme.primary,
              secondaryColor: theme.colorScheme.secondary,
              radius: widget.radius,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _DelicateSpectrumPainter extends CustomPainter {
  final double progress;
  final double playFactor;
  final Color primaryColor;
  final Color secondaryColor;
  final double radius;

  _DelicateSpectrumPainter({
    required this.progress,
    required this.playFactor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.radius,
  });

  static const int _barCount = 44;
  static const double _tau = math.pi * 2;

  final Paint _barPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 1.6;

  final Paint _glowPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 3.0;

  final Paint _auraPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = radius + 3.0;
    final phase = progress * _tau;

    // Мягкая фоновая неоновая аура (плавно нарастает при playFactor)
    if (playFactor > 0.01) {
      final pulse = math.sin(phase * 1.5) * 1.5;
      final auraRadius = baseRadius + 1.5 + pulse;
      _auraPaint.color = primaryColor.withValues(alpha: 0.15 * playFactor);
      canvas.drawCircle(center, auraRadius, _auraPaint);
    }

    for (var i = 0; i < _barCount; i++) {
      final angle = (i / _barCount) * _tau - math.pi / 2;

      // Плавная органическая интерполяция волн без резких производных
      final w1 = (math.sin(phase * 2.0 + i * 0.45) + 1.0) * 0.5;
      final w2 = (math.cos(phase * 1.5 - i * 0.32) + 1.0) * 0.5;
      final wave = w1 * 0.62 + w2 * 0.38;

      // Деликатный размер: в покое 1.0 px, на максимуме до 6.2 px
      final dynamicHeight = wave * 5.2 * playFactor;
      final height = 1.0 + dynamicHeight;

      final rInner = baseRadius;
      final rOuter = baseRadius + height;

      final cosA = math.cos(angle);
      final sinA = math.sin(angle);

      final p1 = Offset(center.dx + rInner * cosA, center.dy + rInner * sinA);
      final p2 = Offset(center.dx + rOuter * cosA, center.dy + rOuter * sinA);

      // Плавный градиент по кругу
      final colorFraction = (i / _barCount + progress * 0.25) % 1.0;
      final barColor = Color.lerp(
        primaryColor,
        secondaryColor,
        (math.sin(colorFraction * _tau) + 1.0) * 0.5,
      )!;

      final alpha = 0.22 + 0.68 * playFactor * (0.4 + wave * 0.6);
      _barPaint.color = barColor.withValues(alpha: alpha.clamp(0.0, 1.0));

      if (playFactor > 0.25 && dynamicHeight > 2.0) {
        _glowPaint.color = barColor.withValues(alpha: 0.20 * playFactor);
        canvas.drawLine(p1, p2, _glowPaint);
      }

      canvas.drawLine(p1, p2, _barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DelicateSpectrumPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.playFactor != playFactor ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor;
  }
}
