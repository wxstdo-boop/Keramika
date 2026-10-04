import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/markdown_text.dart';

/// Плавное зачёркивание текста: при отметке линия «рисуется» слева направо
/// по каждой строке (эффект пера), при снятии — плавно «стирается» обратно.
///
/// Обычный `TextDecoration.lineThrough` переключается мгновенно:
/// `TextStyle.lerp` меняет decoration скачком на середине анимации, поэтому
/// «плавного зачёркивания» не выходит даже через AnimatedDefaultTextStyle.
/// Здесь линия рисуется своим CustomPainter и анимируется контроллером.
class AnimatedStrikeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  /// Масштаб шрифта из MediaQuery: без него линии зачёркивания
  /// рисовались по метрикам масштаба 1.0 и при системном масштабе
  /// ≠ 1.0 (крупный шрифт на MIUI/Redmi) не совпадали со строками
  /// текста — зачёркнутое слово «разъезжалось» по строкам.
  ///
  /// null — взять `MediaQuery.textScalerOf(context)` (тот же масштаб,
  /// что рендерит сам RichText) — рекомендуется; явный масштаб можно
  /// передать только если нужно рассогласование.
  final TextScaler? textScaler;

  /// true — текст зачёркнут (линия рисуется), false — чистый текст.
  final bool struck;

  /// Цвет текста в зачёркнутом состоянии (обычно приглушённый
  /// onSurfaceVariant) — между исходным и этим цветом идёт плавный переход.
  final Color? struckColor;

  /// Цвет самой линии зачёркивания (по умолчанию — [struckColor]).
  final Color? strikeColor;

  final int? maxLines;
  final TextOverflow overflow;

  /// Выравнивание текста. `TextAlign.justify` здесь НЕ используется: он
  /// растягивает пробелы до правого края, и в узкой колонке карточки на
  /// короткой строке между словами открывались «дыры» в пол-экрана.
  final TextAlign? textAlign;
  final Duration duration;
  final Curve curve;

  const AnimatedStrikeText({
    super.key,
    required this.text,
    required this.style,
    required this.struck,
    this.textScaler,
    this.struckColor,
    this.strikeColor,
    this.maxLines,
    this.textAlign,
    this.overflow = TextOverflow.clip,
    // 420→520 мс и `easeInOutCubic`: ход «пера» начинался и заканчивался
    // рывком (easeOut стартует сразу на полной скорости), и зачёркивание
    // казалось щелчком, а не проведением линии. Кривая симметрична, поэтому
    // одинаково плавна и при снятии отметки (реверс кривой в этом Flutter не
    // работает — берётся прямая).
    this.duration = const Duration(milliseconds: 520),
    this.curve = Curves.easeInOutCubic,
  });

  @override
  State<AnimatedStrikeText> createState() => _AnimatedStrikeTextState();
}

class _AnimatedStrikeTextState extends State<AnimatedStrikeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// Раскладка строк пересчитывается только при смене текста/стиля/ширины,
  /// но не на каждый кадр анимации: см. [_StrikeLayout].
  final _StrikeLayout _layout = _StrikeLayout();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.struck ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedStrikeText old) {
    super.didUpdateWidget(old);
    if (old.struck != widget.struck) {
      if (widget.struck) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.style.color ?? const Color(0xFF000000);
    final struckColor = widget.struckColor ?? baseColor.withValues(alpha: 0.55);
    final strikeColor = widget.strikeColor ?? struckColor;
    // Масштаб, которым рендерится видимый RichText: если явно не передан,
    // берём из MediaQuery, чтобы линии зачёркивания всегда совпадали
    // со строками текста (при системном масштабе шрифта ≠ 1.0).
    final textScaler = widget.textScaler ?? MediaQuery.textScalerOf(context);
    // Спан для РАСКЛАДКИ один и тот же на все кадры: цвет в нём не участвует
    // (линии рисуются отдельным _StrikePainter, текст рисует RichText-ребёнок),
    // а сам объект стабильный — по `identical` кэш раскладки понимает, что
    // пересчитывать строки не надо.
    final layoutSpan = parseMarkdownSpans(
      widget.text,
      widget.style.copyWith(decoration: TextDecoration.none),
    );
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = widget.curve.transform(_ctrl.value);
        final color = Color.lerp(baseColor, struckColor, t)!;
        return CustomPaint(
          painter: _StrikePainter(
            span: layoutSpan,
            layout: _layout,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
            textAlign: widget.textAlign,
            progress: t,
            strikeColor: strikeColor,
            textScaler: textScaler,
          ),
          child: DefaultTextStyle.merge(
            style: widget.style.copyWith(
              color: color,
              decoration: TextDecoration.none,
            ),
            child: child!,
          ),
        );
      },
      child: RichText(
        text: layoutSpan,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        textAlign: widget.textAlign ?? TextAlign.start,
        softWrap: true,
      ),
    );
  }
}

/// Кэш раскладки абзаца для линий зачёркивания. Живёт в стейте виджета и
/// переиспользуется между кадрами одной анимации.
///
/// Почему это важно именно на слабом железе: `TextPainter.layout()` +
/// `computeLineMetrics()` на 1080×2400 при 60 fps пересобирали shaping всего
/// заголовка ~25 раз за один тап по галке, а в прокручиваемом списке таких
/// карточек десятки — это прямо заметные микрофризы на Adreno 610. При этом
/// за кадр меняется только `progress` и цвет, то есть геометрия строк ровно та
/// же. Пересчёт происходит при смене текста, стиля, ширины, maxLines,
/// выравнивания или системного масштаба шрифта.
class _StrikeLayout {
  TextSpan? _span;
  double? _width;
  int? _maxLines;
  TextOverflow? _overflow;
  TextAlign? _textAlign;
  TextScaler? _textScaler;
  List<LineMetrics> _metrics = const [];

  List<LineMetrics> metricsFor({
    required TextSpan span,
    required double width,
    required int? maxLines,
    required TextOverflow overflow,
    required TextAlign? textAlign,
    required TextScaler textScaler,
  }) {
    if (identical(span, _span) &&
        width == _width &&
        maxLines == _maxLines &&
        overflow == _overflow &&
        textAlign == _textAlign &&
        identical(textScaler, _textScaler)) {
      return _metrics;
    }
    final tp = TextPainter(
      text: span,
      textAlign: textAlign ?? TextAlign.start,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
      // КРИТИЧНО: тот же масштаб, что у видимого RichText. Без него
      // линии рисуются по раскладке масштаба 1.0 и при системном
      // масштабе шрифта ≠ 1.0 «сползают» с текста.
      textScaler: textScaler,
    )..layout(maxWidth: width);
    _span = span;
    _width = width;
    _maxLines = maxLines;
    _overflow = overflow;
    _textAlign = textAlign;
    _textScaler = textScaler;
    _metrics = tp.computeLineMetrics();
    return _metrics;
  }
}

/// Рисует линию зачёркивания по каждой строке текста. Прогресс 0..1 —
/// ширина линии; линия растёт слева направо с мягким «пером» на конце.
class _StrikePainter extends CustomPainter {
  final TextSpan span;
  final _StrikeLayout layout;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;
  final double progress;
  final Color strikeColor;
  final TextScaler textScaler;

  _StrikePainter({
    required this.span,
    required this.layout,
    required this.maxLines,
    required this.overflow,
    this.textAlign,
    required this.progress,
    required this.strikeColor,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;
    // МАСШТАБИРОВАННЫЙ размер: baseline от TextPainter приходит уже в
    // масштабированных координатах (textScaler применён к раскладке), а
    // span.style.fontSize — нет. Если брать немасштабированный fontSize,
    // линия при масштабе > 1.0 рисуется ниже, чем нужно, и «залезает»
    // в текст/descenders.
    final metrics = layout.metricsFor(
      span: span,
      width: size.width,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      textScaler: textScaler,
    );
    final fontSize = textScaler.scale(span.style?.fontSize ?? 16.0);

    final linePaint = Paint()
      ..color = strikeColor
      // Было: max(1.8, fontSize*0.11). При 19.5px это 1.8 — на телефоне линия
      // визуально сливалась с текстом и «зачёркивания не видно». 0.15 с
      // порогом 2.6 читается уверенно, но всё ещё не режет глаз.
      ..strokeWidth = math.max(2.6, fontSize * 0.15)
      ..strokeCap = StrokeCap.round;
    // «Перо» на растущем конце рисует со blur-маской, а это каждый вызов —
    // отдельный saveLayer. Краска создаётся один раз на кадр, а не на строку.
    final Paint? dotPaint;
    if (progress < 0.999) {
      dotPaint = Paint()
        ..color = strikeColor.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    } else {
      dotPaint = null;
    }

    // Линии рисуются ПОСЛЕДОВАТЕЛЬНО (первая → вторая → третья), а не все
    // сразу: раньше «перо» телепортировалось между строками, и зачёркивание
    // выглядело щелчком, а не плавным ходом.
    final n = metrics.length;
    for (var i = 0; i < n; i++) {
      final m = metrics[i];
      final local = ((progress * n) - i).clamp(0.0, 1.0);
      final lineWidth = m.width * local;
      if (lineWidth <= 0.3) continue;
      // Позиция по реальным метрикам КАЖДОЙ строки: линия ещё ниже —
      // 0.38 от верха (ascent), ближе к визуальной середине букв
      // (раньше 0.42/0.45 уходили к верху строки).
      final y = m.baseline - m.ascent * 0.38;
      canvas.drawLine(
        Offset(m.left, y),
        Offset(m.left + lineWidth, y),
        linePaint,
      );
      // Мягкое «перо» на растущем конце — линия выглядит живой.
      if (dotPaint != null) {
        canvas.drawCircle(
          Offset(m.left + lineWidth, y),
          m.ascent * 0.10,
          dotPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrikePainter old) =>
      old.progress != progress ||
      !identical(old.span, span) ||
      old.maxLines != maxLines ||
      old.overflow != overflow ||
      old.textAlign != textAlign ||
      old.strikeColor != strikeColor ||
      !identical(old.textScaler, textScaler);
}
