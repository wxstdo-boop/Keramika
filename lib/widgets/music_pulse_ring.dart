import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';

/// Тонкая «кровавая» обводка вокруг кнопки проигрывания: цвета медленно
/// перетекают между алым, тёмно-красным и розовым (плюс чуть темы), толщина и
/// свечение пульсируют в такт музыке.
///
/// Кольцо — именно ОБВОДКА ([PaintingStyle.stroke]), а не залитый круг:
/// по периметру идёт только тонкая линия, а под пальцем нет ни заливки, ни
/// отклика.
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

  /// Как долго кольцо гаснет/проявляется при смене «играет/пауза».
  static const Duration _fade = Duration(milliseconds: 420);

  /// Тикер продолжает идти, пока кольцо ещё видно: если оборвать анимацию в
  /// момент паузы, гаснущее кольцо «замерзает» и переход читается рывком.
  /// Останавливаем пульс только после того, как гаснущий слой догорел.
  Timer? _stopAfterFade;

  @override
  void initState() {
    super.initState();
    if (widget.active && !MotionPrefs.shouldReduceMotion) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant MusicPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) {
      _stopAfterFade?.cancel();
      if (!MotionPrefs.shouldReduceMotion && !_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    } else if (_ctrl.isAnimating) {
      // Даём гаснущему кольцу дожить свой фейд, и только потом стоп.
      _stopAfterFade?.cancel();
      _stopAfterFade = Timer(_fade, () {
        if (mounted && !widget.active) _ctrl.stop();
      });
    }
  }

  @override
  void dispose() {
    _stopAfterFade?.cancel();
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
    final a = Color.lerp(BrandColors.red, cs.primary, 0.22)!;
    final b = const Color(0xFF7A0B16);
    final c = Color.lerp(const Color(0xFFFF5A6E), cs.tertiary, 0.18)!;
    return Stack(
      alignment: Alignment.center,
      // Свечение выходит за границы кружка: без этого `Stack` обрезал бы его
      // по прямоугольнику виджета, и вокруг круга читалась бы светящаяся
      // КВАДРАТНАЯ кромка.
      clipBehavior: Clip.none,
      children: [
        // Обводка — отдельный слой ПОД кнопкой, и он не ловит тапы.
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: widget.active ? 1.0 : 0.0,
              duration: reduce ? Duration.zero : _fade,
              // easeInOut: и появление, и угасание идут с нулевой скоростью на
              // концах — переход не «щёлкает».
              curve: Curves.easeInOut,
              // `RepaintBoundary`: перерисовка пульса не задевает кнопку и её
              // значок — те живут своим слоем.
              child: RepaintBoundary(
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
                      isComplex: true,
                      willChange: true,
                      painter: _RingPainter(
                        lead: lead,
                        tail: tail,
                        turn: turn,
                        // Пульс — ТОЛЩИНОЙ: от волосяной линии до заметного, но
                        // всё ещё тонкого кольца.
                        stroke: widget.baseWidth + widget.pulseWidth * pulse,
                        glow: 0.10 + 0.30 * pulse,
                      ),
                    );
                  },
                ),
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
/// заливки. Свечение — та же линия, но шире и полупрозрачнее.
class _RingPainter extends CustomPainter {
  final Color lead;
  final Color tail;
  final double turn;
  final double stroke;
  final double glow;

  const _RingPainter({
    required this.lead,
    required this.tail,
    required this.turn,
    required this.stroke,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Отступ на полную ширину свечения (stroke * 3.2): и обводка, и свет
    // укладываются ВНУТРЬ окна виджета, поэтому кромка не режется соседним
    // клипом.
    final r = math.min(size.width, size.height) / 2 - stroke * 1.6;
    if (r <= 0) return;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: r,
    );
    // ОДИН шейдер на кадр вместо трёх: раньше `SweepGradient.createShader`
    // звался трижды за кадр (для свечения и линии), и на слабом GPU это
    // читалось как лаг пульса. Теперь шейдер строится один раз, а нужную
    // прозрачность слоям даёт `ColorFilter.modulate` — без новой раскладки
    // градиента.
    final shader = SweepGradient(
      transform: GradientRotation(turn),
      colors: [lead, tail, lead],
    ).createShader(rect);

    Paint layer(double alpha, double width) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..shader = shader
      ..colorFilter = ColorFilter.mode(
        Color.fromRGBO(255, 255, 255, alpha),
        BlendMode.modulate,
      );

    // Мягкое свечение — БЕЗ размытия (фильтр маски не применяем).
    //
    // Раньше свечение рисовалось размытой копией линии. На устройстве
    // (Impeller) блюр применяется к ПРЯМОУГОЛЬНИКУ слоя, и вокруг круглой
    // обводки проступала светящаяся КВАДРАТНАЯ кромка. Теперь мягкость даёт
    // вторая, более ШИРОКАЯ полупрозрачная обводка: растр круглый, квадрату
    // взяться неоткуда, а blur заодно не пересобирается каждый кадр.
    canvas.drawCircle(rect.center, r, layer(glow * 0.35, stroke * 3.2));
    canvas.drawCircle(rect.center, r, layer(glow * 0.6, stroke * 1.8));
    // Сама обводка — тонкая и чёткая: кольцо должно читаться идеально ровным
    // кругом.
    canvas.drawCircle(rect.center, r, layer(0.9, stroke));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.lead != lead ||
      old.tail != tail ||
      old.turn != turn ||
      old.stroke != stroke ||
      old.glow != glow;
}
