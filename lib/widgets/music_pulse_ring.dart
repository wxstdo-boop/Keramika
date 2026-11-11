import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/motion_prefs.dart';

/// Тонкая «кровавая» обводка вокруг кнопки проигрывания: цвета медленно
/// перетекают между алым, тёмно-красным и розовым (плюс чуть темы), толщина и
/// свечение пульсируют в такт музыке, а по периметру бегут мягкие пятна
/// сияния.
///
/// Кольцо — именно ОБВОДКА ([PaintingStyle.stroke]), а не залитый круг:
/// прежний вариант рисовал залитый градиентный контейнер ПОД кнопкой, и
/// вокруг значка был виден плотный «бублик» с квадратом. Теперь по периметру
/// идёт только тонкая линия, а под пальцем нет ни заливки, ни отклика.
///
/// Кольцо живёт ТОЛЬКО когда трек играет ([active]): на паузе гаснет до
/// прозрачного. Сама кнопка (child) при этом НИКОГДА не гаснет.
class MusicPulseRing extends StatefulWidget {
  final bool active;
  final Widget child;

  /// Толщина кольца в покое и прибавка на пике пульса, px. Тонкое кольцо —
  /// акцент, а не «бублик» вокруг кнопки.
  final double baseWidth;
  final double pulseWidth;

  const MusicPulseRing({
    super.key,
    required this.active,
    required this.child,
    this.baseWidth = 1.1,
    this.pulseWidth = 1.3,
  });

  @override
  State<MusicPulseRing> createState() => _MusicPulseRingState();
}

class _MusicPulseRingState extends State<MusicPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    // Чуть быстрее прежнего: пульс должен читаться как «дыхание в такт», а не
    // как едва заметное мерцание.
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active && !MotionPrefs.shouldReduceMotion) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant MusicPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !MotionPrefs.shouldReduceMotion) {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    } else if (_ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MotionPrefs.shouldReduceMotion;
    // Кровавая гамма: алый → тёмно-красный → розово-красный. Тон темы лишь
    // подмешивается к первому цвету, чтобы кольцо оставалось «в характере»
    // светлой/тёмной темы, но читалось именно красным, а не как угодно.
    final a = Color.lerp(const Color(0xFFE0192F), cs.primary, 0.22)!;
    final b = const Color(0xFF7A0B16);
    final c = Color.lerp(const Color(0xFFFF5A6E), cs.tertiary, 0.18)!;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Обводка — отдельный слой ПОД кнопкой, и он не ловит тапы.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.active ? 1.0 : 0.0,
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOut,
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final t = _ctrl.value;
                  // Пульс 0…1: два «удара» за цикл, оба конца замкнуты.
                  final pulse = reduce
                      ? 0.0
                      : (0.5 + 0.5 * math.sin(t * math.pi * 2));
                  // Медленный поворот градиента: цвет «перетекает» по кругу.
                  final turn = t * 2 * math.pi;
                  final lead = _wheel(a, b, c, math.sin(turn));
                  final tail = _wheel(b, c, a, math.cos(turn));
                  return CustomPaint(
                    painter: _RingPainter(
                      lead: lead,
                      tail: tail,
                      turn: turn,
                      // Пульс — ТОЛЩИНОЙ: от волосяной линии до заметного, но
                      // всё ещё тонкого кольца. Раньше менялось только
                      // свечение, и пульс почти не читался.
                      stroke: widget.baseWidth + widget.pulseWidth * pulse,
                      glow: 0.10 + 0.30 * pulse,
                      // Фаза «бегущих» пятен сияния: их угловое положение
                      // привязано к тому же контроллеру, поэтому кольцо живёт
                      // одним ритмом, а не двумя несогласованными.
                      phase: t,
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

  /// Тон темы по «фазе» −1…1: плавно ходит между тремя цветами палитры.
  static Color _wheel(Color a, Color b, Color c, double phase) {
    final v = (phase + 1) / 2; // 0…1
    return v < 0.5
        ? Color.lerp(a, b, v * 2)!
        : Color.lerp(b, c, (v - 0.5) * 2)!;
  }
}

/// Рисует по периметру ТОЛЬКО тонкую линию: [PaintingStyle.stroke], никакой
/// заливки. Свечение — мягкая копия линии с блюром, чтобы пульс читался, но
/// центр оставался пустым.
class _RingPainter extends CustomPainter {
  final Color lead;
  final Color tail;
  final double turn;
  final double stroke;
  final double glow;

  /// Фаза 0…1 для «бегущих» пятен сияния по периметру.
  final double phase;

  const _RingPainter({
    required this.lead,
    required this.tail,
    required this.turn,
    required this.stroke,
    required this.glow,
    required this.phase,
  });

  /// Сколько пятен сияния бежит по кругу.
  static const int _spotCount = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - stroke / 2;
    if (r <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: r,
    );
    // Прозрачность запекаем в ЦВЕТА градиента, а не в `Paint.color`: при
    // заданном `shader` цвет кисти не применяется.
    Shader sweep(double alpha) => SweepGradient(
      transform: GradientRotation(turn),
      colors: [
        lead.withValues(alpha: alpha),
        tail.withValues(alpha: alpha),
        lead.withValues(alpha: alpha),
      ],
    ).createShader(rect);
    // Мягкое свечение: та же линия с блюром, низкой прозрачностью.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + glow * 10),
    );
    // Сама обводка — тонкая и чёткая.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(0.9),
    );
    // «Пятна сияния»: несколько мягких размытых огоньков бегут по периметру.
    // Они дают кольцу объём и жизнь, оставаясь за пределами залитой
    // обводки — центр кнопки по-прежнему пустой.
    final spotR = math.max(2.0, stroke * 2.6);
    for (var i = 0; i < _spotCount; i++) {
      final ang = (phase + i / _spotCount) * 2 * math.pi;
      final c = Offset(
        rect.center.dx + math.cos(ang) * r,
        rect.center.dy + math.sin(ang) * r,
      );
      canvas.drawCircle(
        c,
        spotR,
        Paint()
          ..color = i.isEven
              ? lead.withValues(alpha: 0.30 * (0.6 + 0.4 * glow / 0.40))
              : tail.withValues(alpha: 0.26 * (0.6 + 0.4 * glow / 0.40))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, spotR),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.lead != lead ||
      old.tail != tail ||
      old.turn != turn ||
      old.stroke != stroke ||
      old.glow != glow ||
      old.phase != phase;
}
