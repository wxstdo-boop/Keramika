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
    this.overflow = TextOverflow.clip,
    this.duration = const Duration(milliseconds: 420),
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<AnimatedStrikeText> createState() => _AnimatedStrikeTextState();
}

class _AnimatedStrikeTextState extends State<AnimatedStrikeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

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
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = widget.curve.transform(_ctrl.value);
        final color = Color.lerp(baseColor, struckColor, t)!;
        // Маркдаун из заголовка рендерится (…*курсив*… → курсив), а не
        // показывается звёздочками. Спаны пересобираются на каждый кадр,
        // чтобы анимация цвета (обычный → приглушённый) применялась и к
        // вложенным участкам.
        final span = parseMarkdownSpans(
          widget.text,
          widget.style.copyWith(color: color, decoration: TextDecoration.none),
        );
        return CustomPaint(
          painter: _StrikePainter(
            span: span,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
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
        text: parseMarkdownSpans(
          widget.text,
          widget.style.copyWith(decoration: TextDecoration.none),
        ),
        maxLines: widget.maxLines,
        overflow: widget.overflow,
        softWrap: true,
      ),
    );
  }
}

/// Рисует линию зачёркивания по каждой строке текста. Прогресс 0..1 —
/// ширина линии; линия растёт слева направо с мягким «пером» на конце.
class _StrikePainter extends CustomPainter {
  final TextSpan span;
  final int? maxLines;
  final TextOverflow overflow;
  final double progress;
  final Color strikeColor;
  final TextScaler textScaler;

  _StrikePainter({
    required this.span,
    required this.maxLines,
    required this.overflow,
    required this.progress,
    required this.strikeColor,
    required this.textScaler,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.001) return;
    final baseFontSize = span.style?.fontSize ?? 16.0;
    // МАСШТАБИРОВАННЫЙ размер: baseline от TextPainter приходит уже в
    // масштабированных координатах (textScaler применён к раскладке), а
    // span.style.fontSize — нет. Если брать немасштабированный fontSize,
    // линия при масштабе > 1.0 рисуется ниже, чем нужно, и «залезает»
    // в текст/descenders.
    final fontSize = textScaler.scale(baseFontSize);
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: overflow == TextOverflow.ellipsis ? '…' : null,
      // КРИТИЧНО: тот же масштаб, что у видимого RichText. Без него
      // линии рисуются по раскладке масштаба 1.0 и при системном
      // масштабе шрифта ≠ 1.0 «сползают» с текста.
      textScaler: textScaler,
    )..layout(maxWidth: size.width);

    final linePaint = Paint()
      ..color = strikeColor
      ..strokeWidth = math.max(1.8, fontSize * 0.11)
      ..strokeCap = StrokeCap.round;

    for (final m in tp.computeLineMetrics()) {
      final lineWidth = m.width * progress;
      if (lineWidth <= 0.3) continue;
      // Позиция по реальным метрикам КАЖДОЙ строки: asc+desc — высота
      // строки, линия на 45% от верха (ближе к середине букв). Раньше
      // 0.45 от ascent поднималась слишком высоко и «заезжала» на
      // верх текста — опускаем чуть ниже, к центру строки.
      final y = m.baseline - m.ascent * 0.42;
      canvas.drawLine(
        Offset(m.left, y),
        Offset(m.left + lineWidth, y),
        linePaint,
      );
      // Мягкое «перо» на растущем конце — линия выглядит живой.
      if (progress < 0.999) {
        final dotPaint = Paint()
          ..color = strikeColor.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
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
      old.span != span ||
      old.maxLines != maxLines ||
      old.overflow != overflow ||
      old.strikeColor != strikeColor ||
      old.textScaler != textScaler;
}
