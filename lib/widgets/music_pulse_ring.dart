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
/// Плавность держится на трёх вещах:
///  * **Всё считается от одного числа** — прогресса `t`. Толщина, поворот и
///    цвет это гладкие тригонометрические функции от `t`, без ветвлений и без
///    `if` посередине кадра. Прежний выбор цвета переключался по половинам
///    окружности: на стыке производная рвалась, и глаз читал это как рывок.
///  * **Один слой.** И аура, и линия живут в ОДНОМ `CustomPaint` внутри одного
///    `RepaintBoundary`: движок делает один слой и один растр на кадр. Раньше
///    поверх был `AnimatedOpacity` (лишний слой), а подсказки `isComplex` и
///    `willChange` заставляли кэшировать растр и тут же инвалидировать его
///    каждый кадр — отсюда «дёрганье» на слабом GPU.
///  * **Фаза.** У каждого кольца свой [seed]: два кольца на экране не
///    пульсируют в одну ногу, а идут вразнобой, как живой пульс.
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

  /// Сдвиг фазы 0…1: разводит пульс колец на одном экране, чтобы они не
  /// дышали синхронно.
  final double seed;

  const MusicPulseRing({
    super.key,
    required this.active,
    required this.child,
    this.baseWidth = 1.3,
    this.pulseWidth = 0.9,
    this.seed = 0,
  });

  @override
  State<MusicPulseRing> createState() => _MusicPulseRingState();
}

class _MusicPulseRingState extends State<MusicPulseRing>
    with TickerProviderStateMixin {
  /// Один «вдох» — 2.8 с. Дольше прежнего: пульс читается спокойным дыханием,
  /// а не мерцанием. Длительность задаёт и скорость перетекания тона.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  /// Как долго кольцо гаснет/проявляется при смене «играет/пауза».
  static const Duration _fade = Duration(milliseconds: 420);

  /// Тикер продолжает идти, пока кольцо ещё видно: если оборвать анимацию в
  /// момент паузы, гаснущее кольцо «замерзает» и переход читается рывком.
  /// Останавливаем пульс только после того, как гаснущий слой догорел.
  Timer? _stopAfterFade;

  /// Прозрачность кольца: 1 — играет, 0 — пауза. Живёт отдельным значением,
  /// потому что прозрачность считает сам painter (один слой), а не лишний
  /// `AnimatedOpacity` над ним.
  late final AnimationController _vis = AnimationController(
    vsync: this,
    duration: _fade,
    value: widget.active ? 1 : 0,
  );

  /// Проявление/угасание с нулевой скоростью на концах: переход не «щёлкает»
  /// ни в начале, ни в конце.
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
    if (widget.active) {
      _stopAfterFade?.cancel();
      _vis.forward();
      if (!MotionPrefs.shouldReduceMotion && !_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    } else {
      _vis.reverse();
      if (_ctrl.isAnimating) {
        // Даём гаснущему кольцу дожить свой фейд, и только потом стоп.
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
    // Кровавая гамма: алый → тёмно-красный → розово-красный. Тон темы лишь
    // подмешивается к краям, чтобы кольцо оставалось «в характере» светлой или
    // тёмной темы, но читалось именно красным.
    final palette = [
      Color.lerp(BrandColors.red, cs.primary, 0.22)!,
      const Color(0xFF7A0B16),
      Color.lerp(const Color(0xFFFF5A6E), cs.tertiary, 0.18)!,
    ];
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
            child: RepaintBoundary(
              // Оба контроллера слушает ОДИН билдер: смена «играет/пауза»
              // (проявление) и сам пульс идут через один painter, без
              // промежуточных слоёв.
              child: AnimatedBuilder(
                animation: Listenable.merge([_ctrl, _visCurve]),
                builder: (context, _) {
                  final vis = _visCurve.value;
                  if (vis <= 0.001) return const SizedBox.expand();
                  final t = _ctrl.value + widget.seed;
                  // Пульс 0…1: ОДИН мягкий «вдох» за цикл, оба конца
                  // замкнуты. Два удара на цикл читались как дрожь.
                  final pulse = reduce
                      ? 0.0
                      : (0.5 - 0.5 * math.cos(t * math.pi * 2));
                  // Медленный поворот градиента: цвет «перетекает» по кругу.
                  final turn = t * 2 * math.pi;
                  return CustomPaint(
                    painter: _RingPainter(
                      palette: palette,
                      turn: turn,
                      // Пульс — ТОЛЩИНОЙ: от волосяной линии до заметного, но
                      // всё ещё тонкого кольца.
                      stroke: widget.baseWidth + widget.pulseWidth * pulse,
                      glow: 0.10 + 0.30 * pulse,
                      alpha: vis,
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

/// Рисует по периметру ТОЛЬКО тонкую линию: [PaintingStyle.stroke], никакой
/// заливки. Аура — та же линия, но шире и полупрозрачнее.
///
/// За кадр ровно ДВА обхода окружности: аура и сама линия. Аура задаёт и
/// внутреннее, и наружное затухание одним радиальным градиентом, поэтому нет
/// ни «слоёного бублика», ни резкой кромки.
class _RingPainter extends CustomPainter {
  /// Три цвета палитры. Тон берётся непрерывной функцией от [turn], поэтому
  /// перетекание не рвётся на стыках.
  final List<Color> palette;
  final double turn;
  final double stroke;
  final double glow;
  final double alpha;

  const _RingPainter({
    required this.palette,
    required this.turn,
    required this.stroke,
    required this.glow,
    required this.alpha,
  });

  /// Тон палитры по фазе: плавно ходит по трём цветам по замкнутому кругу.
  /// Непрерывно по всей оси — в отличие от прежнего переключения по половинам.
  static Color _tone(List<Color> p, double phase) {
    final v = (phase / (2 * math.pi)) % 1.0; // 0…1, замкнуто
    final x = v * p.length;
    final i = x.floor();
    return Color.lerp(p[i % p.length], p[(i + 1) % p.length], x - i)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Отступ на полную ширину свечения (stroke * 3.2): и обводка, и свет
    // укладываются ВНУТРЬ окна виджета, поэтому кромка не режется соседним
    // клипом.
    final r = math.min(size.width, size.height) / 2 - stroke * 1.6;
    if (r <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    final lead = _tone(palette, turn);
    final tail = _tone(palette, turn + 2 * math.pi / 3);

    // Мягкая аура: ОДНА широкая обводка вокруг линии. Радиальный градиент
    // держит прозрачность на ноль по краям полосы и максимум на её середине —
    // свет растворяется и внутрь, и наружу, без резкой окружности.
    final auraWidth = stroke * 3.2;
    final auraColor = Color.lerp(lead, tail, 0.5)!;
    final outer = r + auraWidth / 2;
    final innerFrac = ((r - auraWidth / 2) / outer).clamp(0.0, 0.98);
    final midFrac = (r / outer).clamp(innerFrac, 0.99);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = auraWidth
        ..shader = RadialGradient(
          colors: [
            auraColor.withValues(alpha: 0),
            auraColor.withValues(alpha: glow * 0.55 * alpha),
            auraColor.withValues(alpha: 0),
          ],
          stops: [innerFrac, midFrac, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outer)),
    );

    // Сама обводка — тонкая и чёткая: кольцо читается ровным кругом.
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          transform: GradientRotation(turn),
          colors: [lead, tail, lead],
        ).createShader(rect)
        ..colorFilter = ColorFilter.mode(
          Color.fromRGBO(255, 255, 255, 0.9 * alpha),
          BlendMode.modulate,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.turn != turn ||
      old.stroke != stroke ||
      old.glow != glow ||
      old.alpha != alpha ||
      old.palette != palette;
}
