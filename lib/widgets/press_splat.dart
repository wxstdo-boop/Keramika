import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'press_scale.dart';

/// Мягкое «размашистое» органическое пятно при нажатии — точно как лужа на
/// PIN-цифрах (радиальный градиент + рваный контур + брызги). Рисует Path с
/// волнистыми краями, не жёсткий круг.
class PressSplat extends StatefulWidget {
  const PressSplat({
    super.key,
    required this.child,
    required this.color,
    this.maxRadius = 85,
    this.alpha = 0.45,
    this.onTap,
    this.hitBox,
    this.seed = 2.7,
    this.smeary = 0.0,
    this.duration = const Duration(milliseconds: 520),
    this.exitDuration = const Duration(milliseconds: 900),
    this.bloomOnRelease = false,
  });

  final Widget child;
  final Color color;
  final double maxRadius;
  final double alpha;
  final VoidCallback? onTap;
  final Size? hitBox;
  final double seed;

  /// 0 = ровное круглое пятно; 1 = размашистый «размаз»: рваные отростки,
  /// длинная капля вниз, брызги и мелкий шлейф по периметру.
  final double smeary;

  /// Сколько живёт раскрытие пятна. По умолчанию совпадает с раскрытием
  /// содержимого — вспышка растёт вместе с ним.
  final Duration duration;

  /// Сколько пятно УХОДИТ (медленнее, чем раскрывается): мягкое растворение.
  final Duration exitDuration;

  /// true — пока палец ДЕРЖИТ кнопку, пятна нет: оно расцветает только на
  /// отпускании, одновременно с действием тапа (раскрытием заметки). Под
  /// пальцем в это время видна лишь отдача самой кнопки ([PressScale]).
  /// false — прежнее поведение: пятно расплывается уже от касания.
  final bool bloomOnRelease;

  @override
  State<PressSplat> createState() => _PressSplatState();
}

class _PressSplatState extends State<PressSplat>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  int _downMs = 0;
  Timer? _tapReverse;
  bool _reversing = false;

  /// Медленное, сглаженное угасание пятна: уход заметно длиннее вспышки и
  /// идёт по easeInOutCubic, поэтому клякса «растворяется» плавно, а не
  /// пропадает рывком в последних кадрах.
  void _fadeOut() {
    if (!mounted) return;
    _reversing = true;
    _c.animateBack(
      0.0,
      duration: widget.exitDuration,
      curve: Curves.easeInOutCubic,
    );
  }

  void _pressDown() {
    _tapReverse?.cancel();
    _reversing = false;
    _downMs = DateTime.now().millisecondsSinceEpoch;
    // При [bloomOnRelease] пятно НЕ расплывается под пальцем: держишь —
    // видишь только отдачу самой кнопки. Пятно расцветёт на отпускании
    // (см. _pressUp), ровно вместе с действием тапа.
    if (!widget.bloomOnRelease) _c.forward();
  }

  void _pressUp() {
    final held = DateTime.now().millisecondsSinceEpoch - _downMs;
    if (held < 220) {
      // Простой тап: пятно ДОЛЖНО полностью расцвести и плавно исчезнуть.
      _tapReverse?.cancel();
      _c.forward().then((_) {
        _tapReverse = Timer(const Duration(milliseconds: 260), _fadeOut);
      });
      widget.onTap?.call();
    } else {
      // Длинное зажатие: отпускание — сразу медленно и плавно гаснет.
      _fadeOut();
    }
  }

  @override
  void dispose() {
    _tapReverse?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _pressDown(),
      onTapUp: (_) => _pressUp(),
      onTapCancel: _fadeOut,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final box = widget.hitBox ?? Size.square(widget.maxRadius * 2 + 20);
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              IgnorePointer(
                child: SizedBox(
                  width: box.width,
                  height: box.height,
                  child: CustomPaint(
                    painter: _BlobPainter(
                      color: widget.color,
                      alpha: widget.alpha,
                      v: _c.value,
                      maxRadius: widget.maxRadius,
                      seed: widget.seed,
                      smeary: widget.smeary,
                      reversing: _reversing,
                    ),
                    size: box,
                  ),
                ),
              ),
              Center(child: widget.child),
            ],
          );
        },
      ),
    );
  }
}

/// Кэшированный organic path (unit blob, как на PIN-цифрах).
///
/// Кэш — только для НЕподвижных фаз (пятнышки на «плюсе»). Текущий,
/// «дышащий» контур раскрывающегося пятна строится без кэша: его фаза
/// меняется каждый кадр, и кэш по ней рос бы бесконечно.
final Map<String, Path> _unitBlobCache = {};

Path _unitBlob(double phase, {double smeary = 0.0}) {
  final key = '${phase.toStringAsFixed(3)}|${smeary.toStringAsFixed(2)}';
  final cached = _unitBlobCache[key];
  if (cached != null) return cached;
  final path = _blobPath(phase, smeary);
  _unitBlobCache[key] = path;
  return path;
}

/// Единичный органический контур (радиус ~1): волнистая клякса с
/// отростками и каплей вниз. Строится без кэша — для анимации формы.
Path _blobPath(double phase, double smeary) {
  final path = Path();
  // Размашистый «размаз» требует больше сэмплов: контур идёт по кромке без
  // видимых граней, пятно читается как живая клякса, а не многоугольник.
  final n = smeary > 0.05 ? 96 : 64;
  for (var i = 0; i <= n; i++) {
    final a = i / n * math.pi * 2;
    // Базовая волнистость (низкая частота — «живой» камень).
    var w = 1 +
        0.12 * math.sin(a * 3 + phase) +
        0.08 * math.sin(a * 5 + phase * 1.7) +
        0.04 * math.sin(a * 9 + phase * 0.6);
    // При smeary: быстрые гармоники рвут контур в рваные отростки,
    // а длинная капля-хвост тянется вниз.
    w += smeary *
        (0.15 * math.sin(a * 6 + phase * 2.1) +
            0.10 * math.sin(a * 9 - phase) +
            0.07 * math.sin(a * 12 + phase * 0.4) +
            0.05 * math.sin(a * 15 - phase * 1.3));
    // Капля вниз (sin(a)>0): плавный хвост, длиннее при smeary.
    final drip = math.max(0.0, math.sin(a)) * (0.22 + 0.42 * smeary);
    // Боковые отростки — чуть размазываются по периметру.
    final side = smeary * 0.05 * math.cos(a * 4 + phase);
    final x = math.cos(a) * (w + side);
    final y = math.sin(a) * (w * (0.92 + 0.16 * smeary) + drip);
    if (i == 0) {
      path.moveTo(x, y);
    } else {
      path.lineTo(x, y);
    }
  }
  path.close();
  return path;
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({
    required this.color,
    required this.alpha,
    required this.v,
    required this.maxRadius,
    required this.seed,
    required this.smeary,
    this.reversing = false,
  });

  final Color color;
  final double alpha;
  final double v;
  final double maxRadius;
  final double seed;
  final double smeary;

  /// true — пятно уходит (реверс): форма/прозрачность идут линейно по
  /// сглаженному значению контроллера, без повторного easeOut.
  final bool reversing;

  @override
  void paint(Canvas canvas, Size size) {
    if (v <= 0.02) return;
    // «Расцветание» идёт по easeOutCubic, а вот УХОД — линейно по уже
    // сглаженной контроллером кривой (см. exitCurve): пятно растворяется
    // ровно и медленно, а не «сдувается» рывком в конце.
    final t = reversing
        ? v.clamp(0.0, 1.0)
        : Curves.easeOutCubic.transform(v.clamp(0.0, 1.0));
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = maxRadius * t;
    // Форма «дышит»: контур не просто масштабируется — с ростом t у него
    // едет фаза (новые гармоники), поэтому пятно каждый раз выглядит
    // по-новому («уникальнее»), а рваность наступает постепенно, а не
    // вылезает сразу рваным комком.
    final phase = seed + 0.85 * t;
    final sm = smeary * (0.35 + 0.65 * t);
    // Лёгкое вращение (растёт вместе с раскрытием) — пятно не «стоит»
    // на месте, а расплывается по поверхности.
    final rot = 0.18 * t - 0.06;
    final cosR = math.cos(rot);
    final sinR = math.sin(rot);

    final blob = _blobPath(phase, sm).transform(
      Float64List.fromList(<double>[
        r * cosR, r * sinR, 0, 0, //
        -r * sinR, r * cosR, 0, 0, //
        0, 0, 1, 0, //
        cx, cy, 0, 1, //
      ]),
    );

    // Все плотности ПРОПОРЦИОНАЛЬНЫ alpha: пятно остаётся полупрозрачным
    // при любой заданной прозрачности (раньше в формулах были константы,
    // из-за чего при малом alpha ядро всё равно «вылезало» плотным).
    // Мягкая подсветка под пятном (размазанная тень).
    canvas.drawPath(
      blob,
      Paint()
        ..color = color.withValues(alpha: 0.30 * alpha * t)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.45),
    );

    // Само пятно: радиальный градиент, ядро в центре, угасает к краям.
    // При smeary ядро смещено вниз (капля-хвост тянет форму вниз).
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: (1.35 * alpha + 0.015) * t),
        color.withValues(alpha: 0.75 * alpha * t),
        color.withValues(alpha: 0.0),
      ],
      stops: const [0.0, 0.60, 1.0],
    ).createShader(
      Rect.fromCenter(
        center: Offset(cx, cy + r * (0.12 * smeary)),
        width: r * 2.6,
        height: r * (2.6 + 0.8 * smeary),
      ),
    );
    canvas.drawPath(blob, Paint()..shader = shader);

    // Спутниковые брызги появляются ВОЛНОЙ (не сразу) — раскрытие читается
    // по-настоящему плавным. Плотность тоже пропорциональна alpha.
    final count = sm > 0.05 ? 7 : 4;
    for (var k = 0; k < count; k++) {
      final tk = ((t - 0.22 - 0.08 * k) / 0.70).clamp(0.0, 1.0);
      if (tk <= 0) continue;
      final a = seed * 1.4 +
          k * 1.9 +
          (smeary > 0 ? 0.45 * math.sin(seed * 3.7 + k * 1.3) : 0);
      final d = r * (1.02 + 0.13 * k + 0.34 * smeary * (k / count));
      final p = Offset(
        cx + math.cos(a) * d,
        cy + math.sin(a) * d * (0.80 + 0.18 * smeary),
      );
      final splashSize =
          size.width * (0.022 + 0.014 * (k % 3) + 0.012 * smeary) * tk;
      canvas.drawCircle(
        p,
        splashSize,
        Paint()
          ..color = color.withValues(alpha: 1.15 * alpha * tk)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * tk),
      );

      // Яркое ядро у каждой брызги — точечное блик-пятно.
      if (tk > 0.4) {
        canvas.drawCircle(
          p,
          splashSize * 0.35,
          Paint()..color = color.withValues(alpha: 1.6 * alpha * tk),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.v != v ||
      old.color != color ||
      old.maxRadius != maxRadius ||
      old.smeary != smeary ||
      old.seed != seed;
}

/// Кнопка-«плюс» — РОВНО как на экране будильников: обычная круглая
/// [FloatingActionButton]. Отличие одно: на её поверхности живут мелкие
/// размашистые органические пятнышки (спутники), которые мягко проступают
/// при зажатии и плавно гаснут при отпускании.
///
/// Пятнышки рисуются СТРОГО в пределах [size]×[size] (SizedBox + Stack с
/// фиксированным размером), поэтому они ничего не «задвигают» и не вылезают
/// за кнопку — раньше именно «летающий» splat уезжал поверх фона.
/// Долгое зажатие — режим BERSERK.
class OrganicFab extends StatefulWidget {
  const OrganicFab({
    super.key,
    required this.onTap,
    required this.onLongPress,
    this.seed = 5.2,
    this.size = 56,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final double seed;
  final double size;

  @override
  State<OrganicFab> createState() => _OrganicFabState();
}

class _OrganicFabState extends State<OrganicFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  Timer? _release;

  void _down() {
    _release?.cancel();
    _c.forward();
  }

  void _up() {
    _release?.cancel();
    // Небольшая задержка: пятнышки успевают «проявиться» под пальцем и
    // гаснут уже после отпускания — плавно, без щелчка.
    _release = Timer(const Duration(milliseconds: 110), () {
      if (mounted) _c.reverse();
    });
  }

  @override
  void dispose() {
    _release?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Сама кнопка — обычная FAB «как в будильниках». Долгое зажатие
            // (BERSERK) вешаем на неё же, как это сделано на будильниках.
            PressScale(
              child: GestureDetector(
                onLongPress: widget.onLongPress,
                child: FloatingActionButton(
                  // Округлый квадрат — ровно как FAB в будильниках (дефолтная
                  // форма M3). Кругом быть НЕ должно.
                  onPressed: widget.onTap,
                  child: const Icon(Icons.add),
                ),
              ),
            ),
            // Мелкие размашистые пятнышки ПОВЕРХ кнопки. IgnorePointer —
            // тап/долгое зажатие идут строго в FAB под ними.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (_, _) => CustomPaint(
                    painter: _PlusSpeckPainter(
                      // FAB по умолчанию M3 — это primaryContainer (светлая
                      // пастель) с тёмным значком. Пятнышки рисуем акцентом
                      // темы (primary) с мягким светлым ядром — они читаются
                      // на пастели и перекликаются с фирменным цветом.
                      color: cs.primary,
                      deep: Colors.white,
                      v: _c.value,
                      seed: widget.seed,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Мелкие размашистые пятнышки на поверхности кнопки-плюса: несколько
/// ОРГАНИЧЕСКИХ клякс (не ровные кружки) + блестящее ядрышко у каждой —
/// читаются как «веснушки»/чёрточки на цветной кнопке и перекликаются с
/// фирменными размашистыми пятнами приложения.
///
/// ГЛАВНОЕ: геометрия СТАТИЧНА. При зажатии пятнышки НЕ растут и НЕ
/// разъезжаются — нажатие лишь чуть-чуть углубляет их цвет. Раньше они
/// «раздувались» под пальцем (радиус и дистанция зависели от прогресса) и
/// это читалось как дефект отрисовки.
///
/// Всё строится от центра и не выходит за кромку FAB (радиус ~0.5*size).
class _PlusSpeckPainter extends CustomPainter {
  _PlusSpeckPainter({
    required this.color,
    required this.deep,
    required this.v,
    required this.seed,
  });

  final Color color;
  final Color deep;
  final double v;
  final double seed;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.5;
    const count = 5;
    // Цвет чуть плотнее под пальцем — единственная реакция на нажатие.
    // Никакого роста/смещения: и размер, и позиция фиксированы.
    final baseAlpha = 0.13 + 0.06 * v;
    final coreAlpha = 0.10 + 0.05 * v;
    for (var k = 0; k < count; k++) {
      final a = seed * 1.7 +
          k * (math.pi * 2 / count) +
          0.5 * math.sin(seed + k * 1.3);
      // Пятнышки держатся внутри кнопки, ближе к кромке (но не за ней).
      final d = r * (0.30 + 0.32 * ((k % 3) / 2));
      final p = Offset(cx + math.cos(a) * d, cy + math.sin(a) * d);
      // Разный размер у пятнышек + слегка вытянутый контур: не «горошины».
      final rr = 1.5 + 0.7 * ((k + 1) % 3);
      final blob = _unitBlob(
        seed * 2.1 + k * 0.77,
        smeary: 0.55,
      ).transform(
        Float64List.fromList(<double>[
          rr * (1.0 + 0.16 * ((k + 1) % 2)), 0, 0, 0, //
          0, rr * 0.92, 0, 0, //
          0, 0, 1, 0, //
          p.dx, p.dy, 0, 1, //
        ]),
      );
      canvas.drawPath(
        blob,
        Paint()
          ..color = color.withValues(alpha: baseAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );
      // Мягкое светлое ядрышко со смещением — клякса объёмная, «мокрая»,
      // а не плоская точка.
      canvas.drawCircle(
        Offset(p.dx - rr * 0.26, p.dy - rr * 0.30),
        rr * 0.30,
        Paint()
          ..color = deep.withValues(alpha: coreAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlusSpeckPainter old) =>
      old.v != v || old.color != color || old.deep != deep || old.seed != seed;
}
