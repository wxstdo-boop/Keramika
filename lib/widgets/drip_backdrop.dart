import 'dart:math';
import 'package:flutter/material.dart';

/// Живой фон окна KID: редкие мягкие пятна, которые стекают ОТ фирменной
/// капсулы KID вниз, к медальону ПИНа — то есть живут в одной вертикальной
/// колонне, а не «дождём» по всему экрану.
///
/// Оба конца колонны растворены в ноль ([ShaderMask] с вертикальным
/// градиентом), поэтому пятно не «вырезается» верхней границей и не
/// обрывается нижней: оно проявляется из-под капсулы и гаснет перед
/// медальоном. Палитра целиком берётся из темы, поэтому фон меняется
/// вместе с Material You и всегда остаётся «в бренде».
///
/// Бережно к слабым GPU (Redmi Note 12, Adreno 610):
///  * шейдеры пятен создаются ОДИН раз (пятно рисуется в translated холсте
///    вокруг начала координат, поэтому позиция не влияет на шейдер);
///  * маска-фейд пересоздаётся только при смене размера, а не в кадре;
///  * кадр берётся с кванта 1/140 цикла (~12 fps при 11 с) — ступенек глаз
///    не видит, а fill-rate падает в 5 раз;
///  * весь слой обёрнут в RepaintBoundary, так что перерисовка пятен не
///    трогает контент PIN-экрана и не гоняет заново размытие стекол.
/// Контроллер «живых» капель для [DripBackdrop].
///
/// Фоновые пятна в бэкдропе живут своей бесконечной фазой. А здесь — капли,
/// которые падают ИЗ-ПОД капсулы KID в момент нажатия цифры: счётчик
/// [pulses] увеличивается, бэкдроп замечает разницу и роняет реальное пятно
/// с верхушки колонны вниз, к медальону ПИНа.
///
/// Хранить состояние в виджете нельзя — нажатие цифры приходит из LockScreen,
/// а бэкдроп лежит глубже в дереве. Поэтому связь односторонняя и дешёвая:
/// контроллер только считает, состояние разбирает счётчик в своём кадре.
class DripController {
  int _pulses = 0;
  double _x = 0.5;
  int _colorIndex = 0;

  /// Сколько всего капель заказано (монотонно растёт).
  int get pulses => _pulses;

  /// Горизонталь капли в долях ширины холста — колонна под капсулой KID.
  double get x => _x;

  /// Индекс цвета палитры для последней капли.
  int get colorIndex => _colorIndex;

  /// Роняет каплю. [x] — доля ширины холста, [colorIndex] — круг по палитре.
  void drip({double? x, int colorIndex = 0}) {
    if (x != null) _x = x;
    _colorIndex = colorIndex;
    _pulses++;
  }
}

class DripBackdrop extends StatefulWidget {
  const DripBackdrop({
    super.key,
    required this.colors,
    this.controller,
    this.isDark = false,
    this.dripCount = 5,
    this.duration = const Duration(seconds: 11),
    this.top = 0.0,
    this.bottom = 1.0,
    this.xCenter = 0.5,
    this.xSpread = 0.5,
    this.fade = 0.16,
  });

  /// Палитра темы — пятна берутся из неё по кругу.
  final List<Color> colors;

  /// Источник «живых» капель (нажатие цифры на ПИН-экране). null — фон молчит.
  final DripController? controller;

  /// Тёмная ли тема: на светлой дождь рисуем контрастнее.
  final bool isDark;
  final int dripCount;
  final Duration duration;

  /// Доли высоты холста, между которыми живёт колонна пятен.
  final double top;
  final double bottom;

  /// Центр и ширина колонны по горизонтали (доли ширины холста).
  final double xCenter;
  final double xSpread;

  /// Доля высоты колонны, на которой пятна растворяются сверху и снизу.
  final double fade;

  @override
  State<DripBackdrop> createState() => _DripBackdropState();
}

class _DripBackdropState extends State<DripBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Drip> _drips;
  final Map<int, Shader> _blobs = {};

  Shader? _maskShader;
  Size _maskSize = Size.zero;

  /// Капли, роняемые с ПИН-экрана (нажатие цифры). Фоновые [_drips] живут
  /// вечно, эти живут [_Live.life] и убираются по [_Live.age].
  final List<_Live> _live = [];

  /// Сколько капель уже отрисовали — по счётчику контроллера.
  int _seenPulses = 0;

  /// Пересобирает растр каждый кадр, пока висит хоть одна живая капля.
  /// Фоном (когда живых нет) остаётся квантование фазы — см. [_DripPainter].
  bool get _liveActive => _live.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _drips = _buildDrips();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
    _seenPulses = widget.controller?.pulses ?? 0;
  }

  @override
  void didUpdateWidget(covariant DripBackdrop old) {
    super.didUpdateWidget(old);
    if (old.colors != widget.colors ||
        old.dripCount != widget.dripCount ||
        old.top != widget.top ||
        old.bottom != widget.bottom ||
        old.xCenter != widget.xCenter ||
        old.xSpread != widget.xSpread ||
        old.fade != widget.fade) {
      // Смена темы/геометрии — пересобираем пятна и сбрасываем кэши.
      _drips = _buildDrips();
      _blobs.clear();
      _maskShader = null;
    }
  }

  List<_Drip> _buildDrips() {
    final rng = Random(7301);
    final n = widget.dripCount;
    final t = widget.top;
    final b = widget.bottom;
    return List.generate(n, (i) {
      final color = widget.colors[i % widget.colors.length];
      return _Drip(
        index: i,
        // Колонна, а не весь экран: x разбросан вокруг центра капсулы KID.
        x: widget.xCenter - widget.xSpread / 2 + rng.nextDouble() * widget.xSpread,
        y0: t + (b - t) * (0.34 * rng.nextDouble()),
        y1: t + (b - t) * (0.66 + 0.34 * rng.nextDouble()),
        radius: 22 + rng.nextDouble() * 30,
        tail: 0.10 + rng.nextDouble() * 0.18,
        offset: i / n + rng.nextDouble() * 0.12,
        sway: 5 + rng.nextDouble() * 9,
        color: color,
      );
    });
  }

  /// Забирает нажатия из контроллера и рождает розу дождя.
  ///
  /// Каждое нажатие цифры даёт 6 штрихов-капель, разбросанных по ширине
  /// колонны и по скорости/длине — разрозненный поток, а не столб.
  /// За один залп берём не больше 3 пульсов, иначе залипание пальца
  /// даёт «стену» дождя.
  void _pumpLive(double t, DateTime now) {
    final c = widget.controller;
    if (c != null) {
      final pending = c.pulses - _seenPulses;
      if (pending > 0) {
        _seenPulses = c.pulses;
        final bursts = pending > 3 ? 3 : pending;
        final palette = widget.colors;
        final rng = Random(c.colorIndex * 7 + c.pulses * 13);
        for (var b = 0; b < bursts; b++) {
          final base = c.colorIndex % palette.length;
          for (var k = 0; k < 8; k++) {
            final ci = (base + k) % palette.length;
            _live.add(
              _Live(
                // Разброс по ширине колонны — штрихи расходятся в стороны.
                // Широкий разброс — дождь разлетается по колонне,
                // а не сыпется в одну линию.
                x: c.x + (rng.nextDouble() - 0.5) * 0.60,
                length: 0.03 + rng.nextDouble() * 0.11,
                speed: 0.20 + rng.nextDouble() * 0.55,
                drift: rng.nextDouble() * 3.0,
                color: palette[ci],
                colorIndex: ci,
                // Лёгкий stagger: каждая следующая капля стартует на
                // 120 мс позже — поток разрознен во времени, а не «стеной».
                born: now.add(Duration(milliseconds: k * 120)),
              ),
            );
          }
        }
      }
    }
    _live.removeWhere((l) => l.ageAt(now) >= 1.0);
  }

  /// Шейдер мягкого пятна для конкретного drip. Рисуем пятно всегда вокруг
  /// (0,0), поэтому шейдер не зависит от позиции и создаётся один раз.
  Shader _blobShader(_Drip d) {
    final cached = _blobs[d.index];
    if (cached != null) return cached;
    final shader = RadialGradient(
      colors: [
        d.color.withValues(alpha: 0.26),
        d.color.withValues(alpha: 0.10),
        d.color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: d.radius));
    _blobs[d.index] = shader;
    return shader;
  }

  /// Яркость живой капли по прожитой доле жизни.
  ///
  /// Форма: быстрый подъём, плато и длинный спад. Спад длиннее подъёма
  /// специально — капля должна «стечь», а не лопнуть в последнем кадре.
  double _liveAlphaFor(_Live drip) {
    final a = drip.ageAt(DateTime.now());
    if (a <= 0 || a >= 1) return 0;
    // Подъём короче, спад длиннее: пятно мягко проявляется, долго держится
    // на пике и медленно стекает — плавнее, чем было.
    final rise = Curves.easeOutCubic.transform((a / 0.16).clamp(0.0, 1.0));
    final fall = Curves.easeInCubic.transform(((a - 0.42) / 0.58).clamp(0.0, 1.0));
    return rise * (1 - fall) * 1.9;
  }

  /// Маска: прозрачно → плотно → прозрачно по вертикали. Пересоздаётся
  /// ТОЛЬКО когда меняется размер холста.
  Shader _maskFor(Rect bounds) {
    final cur = _maskShader;
    final size = bounds.size;
    if (cur != null && _maskSize == size) return cur;
    final f = widget.fade.clamp(0.02, 0.45);
    _maskShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [
        Color(0x00FFFFFF),
        Color(0xFFFFFFFF),
        Color(0xFFFFFFFF),
        Color(0x00FFFFFF),
      ],
      stops: [0.0, f, 1.0 - f, 1.0],
    ).createShader(Offset.zero & size);
    _maskSize = size;
    return _maskShader!;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: _maskFor,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final now = DateTime.now();
              _pumpLive(_ctrl.value, now);
              return CustomPaint(
                // Квантование фазы: при неизменной фазе shouldRepaint == false,
                // и Skia переиспользует готовый растр вместо новой растеризации.
                // Но пока висит живая капля, квантование отключаем — её ход
                // обязан быть плавным, иначе стекание читается как прыжок.
                painter: _DripPainter(
                  drips: _drips,
                  t: _liveActive
                      ? _ctrl.value
                      : (_ctrl.value * 140).roundToDouble() / 140,
                  live: List<_Live>.unmodifiable(_live),
                  now: now,
                  liveAlphaFor: _liveAlphaFor,
                  blobShaderFor: _blobShader,
                  colTop: widget.top,
                  colBot: widget.bottom,
                  isDark: widget.isDark,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Drip {
  _Drip({
    required this.index,
    required this.x,
    required this.y0,
    required this.y1,
    required this.radius,
    required this.tail,
    required this.offset,
    required this.sway,
    required this.color,
  });

  final double x;

  /// Доли высоты, откуда капля вытекает и куда стекает.
  final double y0;
  final double y1;
  final double radius;

  /// Длина шлейфа как доля высоты холста.
  final double tail;

  /// Сдвиг фазы, чтобы пятна не шли синхронным «строем».
  final double offset;
  final double sway;
  final Color color;

  /// Позиция в списке — ключ для кэша шейдеров (заполняется при построении).
  final int index;
}

/// Капля, сорвавшаяся с капсулы KID по нажатию цифры.
///
/// Живёт [life] миллисекунд реального времени (не фазой фонового цикла):
/// нажатие должно отзываться сразу, поэтому отсчёт идёт от [_born].
/// Один штрих-капля дождя: вертикальная линия, которая срывается с края
/// капсулы KID и падает вниз с ускорением (как настоящая капля дождя).
/// Один штрих-капля дождя: вертикальная линия, которая срывается с края
/// капсулы KID и падает вниз с РОВНОЙ скоростью (плавный дождь, без
/// рывков-ускорений). Разная длина/скорость/наклон дают разрозненность.
class _Live {
  _Live({
    required this.x,
    required this.length,
    required this.speed,
    required this.drift,
    required this.color,
    required this.colorIndex,
    required this.born,
  });

  /// Горизонталь капли в долях ширины холста.
  final double x;
  /// Длина штриха в долях высоты (разная — разрозненность).
  final double length;
  /// Скорость: доля высоты за жизнь. Разная у каждой капли.
  final double speed;
  /// Фаза лёгкого покачивания (дождь «плывёт» вбок).
  final double drift;
  final Color color;
  /// Индекс цвета палитры.
  final int colorIndex;
  /// Момент рождения: нажатие обязано отозваться сразу.
  final DateTime born;

  /// Сколько живёт штрих (дольше, чем было — плавнее цикл).
  static const int life = 2400;

  /// Прожитое время в долях [life]: 0 → 1.
  double ageAt(DateTime now) => now.difference(born).inMilliseconds / life;
}

class _DripPainter extends CustomPainter {
  _DripPainter({
    required this.drips,
    required this.t,
    required this.live,
    required this.now,
    required this.liveAlphaFor,
    required this.blobShaderFor,
    required this.colTop,
    required this.colBot,
    this.isDark = false,
  });

  final List<_Drip> drips;
  final double t;

  /// Капли, сорвавшиеся с капсулы (живут [_Live.life] мс).
  final List<_Live> live;

  /// Момент кадра — им же обновляется возраст живых капель.
  final DateTime now;

  /// Яркость живой капли в её текущий момент жизни.
  final double Function(_Live drip) liveAlphaFor;

  final Shader Function(_Drip) blobShaderFor;

  /// Верх и низ колонны (доли высоты), между которыми живёт живая капля.
  final double colTop;
  final double colBot;

  /// Тёмная ли тема: на светлой дождь читаем контрастнее (темнее).
  final bool isDark;

  /// Радиус капли в долях ПОЛОВИНЫ высоты панели — единый масштаб, чтобы
  /// геометрия не зависела от ширины экрана (как у фона).

  @override
  void paint(Canvas canvas, Size size) {
    final blob = Paint()..isAntiAlias = true;
    final trail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    for (var i = 0; i < live.length; i++) {
      _paintRain(canvas, size, live[i]);
    }

    if (drips.isEmpty) return; // фоновых пятен нет — только живые

    for (var i = 0; i < drips.length; i++) {
      final d = drips[i];

      // Локальная фаза капли + плавный разгон/торможение внутри цикла.
      final p = (t + d.offset) % 1.0;
      final eased = Curves.easeInOutCubic.transform(p);

      final h = size.height;
      final from = d.y0 * h - d.radius - d.tail * h;
      final to = d.y1 * h + d.radius;
      final cy = from + (to - from) * eased;
      final cx = d.x * size.width + sin((p * 2 * pi) + d.offset * 7) * d.sway;

      // Шлейф: тянем за каплей, удлиняя по мере разгона.
      final trailLen = d.tail * h * (0.25 + 0.75 * eased);
      trail.color = d.color.withValues(alpha: 0.09);
      trail.strokeWidth = d.radius * 0.32;
      canvas.drawLine(Offset(cx, cy - trailLen), Offset(cx, cy), trail);

      // Само пятно — мягкий радиальный градиент (шейдер закэширован).
      canvas.save();
      canvas.translate(cx, cy);
      blob.shader = blobShaderFor(d);
      canvas.drawCircle(Offset.zero, d.radius, blob);
      canvas.restore();
    }
  }

  /// Одна капля дождя: вертикальный штрих с градиентом (хвост прозрачный,
  /// голова яркая), падающий С РОВНОЙ скоростью — плавный дождь без рывков.
  /// Лёгкое покачивание вбок (drift) + яркое пятно головы. Читаемо на
  /// любом фоне (тёмном и светлом): голова подмешивается в тон темы.
  void _paintRain(Canvas canvas, Size size, _Live l) {
    final a = l.ageAt(now).clamp(0.0, 1.0);
    if (a <= 0) return;

    // На светлой теме дождь темнеем для читаемости, на тёмной — как есть.
    // На светлой теме дождь темнеем сильнее, чтобы штрихи читались
    // на почти белом фоне; на тёмной — оставляем фирменный цвет.
    // На светлой теме дождь читаем: сильный сдвиг в холодный тёмный
    // (иначе на почти белом фоне штрихи не видно вовсе).
    final rainColor = isDark ? l.color
        : Color.lerp(l.color, const Color(0xFF233246), 0.85) ?? l.color;

    final h = size.height;
    final w = size.width;
    final fromY = colTop * h;
    final toY = colBot * h;

    // Ровная скорость + покачивание вбок (дождь «плывёт»).
    final fall = min(1.0, l.speed * a);
    final headY = fromY + (toY - fromY) * fall;
    final cx = l.x * w + sin(a * 4.0 + l.drift) * 3.0;
    final lenPx = l.length * h * max(0.5, 1.0 - 0.35 * a);

    // Яркость: мягкое проявление → плато → плавное гашение к концу.
    // Плавный цикл: медленный подъём (0.30) и очень мягкое затухание
    // (pow 1.6) — дождь не «вспыхивает/гаснет», а течёт.
    // Очень плавный цикл: медленный подъём (0.35), долгое плато,
    // мягкое затухание (pow 1.8) — дождь течёт, не «вспыхивает/гаснет».
    final alpha = (a < 0.35 ? a / 0.35 : 1 - pow(((a - 0.35) / 0.65).clamp(0.0, 1.0), 1.8)).clamp(0.0, 1.0);
    if (alpha <= 0.01) return;

    // Вертикальный штрих: хвост (сверху) прозрачный → голова (снизу) яркая.
    final strokeRect = Rect.fromLTRB(cx - 1.25, headY - lenPx, cx + 1.25, headY);
    canvas.drawLine(
      Offset(cx, headY - lenPx),
      Offset(cx, headY),
      Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rainColor.withValues(alpha: 0.0),
            rainColor.withValues(alpha: 0.85 * alpha),
          ],
        ).createShader(strokeRect)
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round,
    );

    // Голова капли — яркое пятно, чтобы дождь читался и на светлом фоне.
    canvas.drawCircle(
      Offset(cx, headY),
      2.4,
      Paint()..color = rainColor.withValues(alpha: (isDark ? 0.95 : 1.0) * alpha),
    );
  }
  @override
  bool shouldRepaint(covariant _DripPainter old) =>
      old.t != t || old.drips != drips;
}
