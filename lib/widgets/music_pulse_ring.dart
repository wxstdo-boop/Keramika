import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Пульс вокруг кнопки проигрывания: от неё расходятся ОДИН ЗА ДРУГИМ
/// тонкие круги — как волны от сердца. Кольца монотонные: один тон темы,
/// меняется только прозрачность и радиус, никакого перелива и мигания.
///
/// Три волны идут с равным шагом фазы: пока одна растворяется у края,
/// следующая уже рождается у кнопки. Так пульс читается ровным и
/// непрерывным, а не «вспышками» раз в цикл.
///
/// Кольцо живёт только когда трек играет ([active]) и мягко гаснет на паузе.
class MusicPulseRing extends StatefulWidget {
  final bool active;
  final Widget child;

  /// Толщина линии волны, px.
  final double lineWidth;

  const MusicPulseRing({
    super.key,
    required this.active,
    required this.child,
    this.lineWidth = 1.6,
  });

  @override
  State<MusicPulseRing> createState() => _MusicPulseRingState();
}

class _MusicPulseRingState extends State<MusicPulseRing>
    with TickerProviderStateMixin {
  /// Один «удар» — 2.4 с. Три волны внутри цикла дают шаг 0.8 с: ровный,
  /// спокойный пульс.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  /// Сколько волн одновременно в пути.
  static const int _waves = 3;

  /// Проявление/угасание при смене «играет / пауза».
  static const Duration _fade = Duration(milliseconds: 420);

  /// Тикер продолжает идти, пока кольцо ещё видно: если оборвать анимацию в
  /// момент паузы, гаснущее кольцо «замерзает» и переход читается рывком.
  Timer? _stopAfterFade;

  late final AnimationController _vis = AnimationController(
    vsync: this,
    duration: _fade,
    value: widget.active ? 1 : 0,
  );

  late final Animation<double> _visCurve = CurvedAnimation(
    parent: _vis,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active && !MotionPrefs.shouldReduceMotion) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant MusicPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _stopAfterFade?.cancel();
      _vis.forward();
      if (!MotionPrefs.shouldReduceMotion && !_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    } else {
      _vis.reverse();
      if (_ctrl.isAnimating) {
        // Волны догоняют свой фейд уже под угасанием: тикер не обрываем
        // мгновенно, иначе кольцо «замерзает» на полпути.
        _stopAfterFade?.cancel();
        _stopAfterFade = Timer(_fade, () {
          if (mounted && !widget.active) _ctrl.stop();
        });
      }
    }
  }

  @override
  void dispose() {
    _stopAfterFade?.cancel();
    _vis.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MotionPrefs.shouldReduceMotion;
    // Монотонный тон: одна краска на все волны. Красный бренда, чуть
    // разбавленный темой, — пульс читается в характере приложения и на
    // светлой, и на тёмной теме, но остаётся ОДНИМ цветом.
    final tone = Color.lerp(cs.primary, const Color(0xFFFF4D63), 0.35)!;
    return Stack(
      alignment: Alignment.center,
      // Свечение выходит за границы кружка: без этого Stack обрезал бы волны
      // по прямоугольнику виджета.
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_ctrl, _visCurve]),
                builder: (context, _) {
                  final vis = _visCurve.value;
                  if (vis <= 0.001) return const SizedBox.expand();
                  return CustomPaint(
                    painter: _PulsePainter(
                      t: _ctrl.value,
                      tone: tone,
                      alpha: vis,
                      lineWidth: widget.lineWidth,
                      waves: _waves,
                      still: reduce,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Рисует [waves] расходящихся кругов: радиус растёт от кнопки к краю,
/// прозрачность уходит в ноль. Одна волна — одна линия, никакой заливки.
class _PulsePainter extends CustomPainter {
  final double t;
  final Color tone;
  final double alpha;
  final double lineWidth;
  final int waves;
  final bool still;

  const _PulsePainter({
    required this.t,
    required this.tone,
    required this.alpha,
    required this.lineWidth,
    required this.waves,
    required this.still,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = math.min(size.width, size.height) / 2 - lineWidth;
    if (outer <= 0) return;
    // Внутренний радиус — по краю кнопки: волна рождается «из-под» иконки.
    final inner = outer * 0.62;

    // Тихая опорная кромка у самой кнопки: между волнами пульс не «пустует»,
    // а держит ровное дыхание. Тон тот же — кольцо остаётся монотонным.
    canvas.drawCircle(
      center,
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth
        ..color = tone.withValues(alpha: 0.28 * alpha),
    );

    if (still) return;

    for (var i = 0; i < waves; i++) {
      // Фаза волны: 0 — только родилась у кнопки, 1 — растворилась у края.
      final phase = (t + i / waves) % 1.0;
      final eased = Curves.easeOutCubic.transform(phase);
      final r = inner + (outer - inner) * eased;
      // Прозрачность: всплывает в начале, плавно гаснет к краю. Квадрат
      // синуса даёт ровный «вдох-выдох» без резкой вспышки у кнопки.
      final fade = math.sin(phase * math.pi);
      final a = 0.5 * fade * fade * alpha;
      if (a <= 0.004) continue;
      // Волна истончается по ходу: у края линия тоньше, чем у кнопки, —
      // так расходящийся пульс читается мягким, а не «верёвочным».
      final w = lineWidth * (1.0 - 0.45 * eased);
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = tone.withValues(alpha: a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter old) =>
      old.t != t ||
      old.alpha != alpha ||
      old.tone != tone ||
      old.lineWidth != lineWidth ||
      old.still != still;
}
