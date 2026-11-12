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
    // Заметно медленнее прежнего: пульс читается как спокойное «дыхание», а
    // не как торопливое мерцание.
    duration: const Duration(milliseconds: 2600),
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
      // Свечение — размытая копия линии, и оно выходит за границы кружка.
      // У `Stack` по умолчанию `Clip.hardEdge`, поэтому блюр обрезался ровно
      // по прямоугольнику виджета: с четырёх сторон читалась СВЕТЯЩАЯСЯ
      // КВАДРАТНАЯ кромка вокруг круглой обводки. Отключаем клип — свечение
      // мягко расходится во все стороны, как и задумано.
      clipBehavior: Clip.none,
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
                  // Пульс 0…1: ОДИН мягкий «вдох» за цикл, оба конца
                  // замкнуты. Два удара на цикл читались как дрожь; один —
                  // как дыхание.
                  final pulse = reduce
                      ? 0.0
                      : (0.5 - 0.5 * math.cos(t * math.pi * 2));
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
                      // всё ещё тонкого кольца.
                      stroke: widget.baseWidth + widget.pulseWidth * pulse,
                      glow: 0.10 + 0.30 * pulse,
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
    //
    // Сигма блюра ПОСТОЯННА: раньше она зависела от пульса (2 + glow*10) и
    // менялась каждый кадр — растр кольца пересобирался целиком, и пульс
    // «лагал». Пульс теперь читается только прозрачностью свечения, а растр
    // берётся из кэша.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Сама обводка — тонкая и чёткая. Никаких «пятен сияния»: кольцо должно
    // читаться идеально ровным кругом, а бегущие блики по периметру выглядели
    // как грязь на обводке.
    canvas.drawCircle(
      rect.center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = sweep(0.9),
    );
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
