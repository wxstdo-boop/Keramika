import 'package:flutter/material.dart';

/// Число, которое меняется ПО ЦИФРАМ: изменившийся разряд проявляется из
/// прозрачного, старый так же мягко гаснет. Это и есть «плавная смена очков
/// рейтинга»: не подмена кадром и не грубый барабан, а живой отклик.
///
/// Раньше здесь лежало настоящее (невидимое) [TextField] ради совпадения
/// метрик с полем ввода. Для ЧИСЛА это лишнее и вредно: скрытое поле
/// попадало в `find.byType(TextField)` и ломало выбор настоящих полей в
/// тестах и в семантике. Теперь разряды рисуются обычными [Text], а
/// анимация — [AnimatedSwitcher] на каждый разряд.
class SmoothDigits extends StatefulWidget {
  const SmoothDigits({
    super.key,
    required this.value,
    this.style,
    this.sample,
    this.alignment = Alignment.centerRight,
    this.textAlign,
  });

  final int value;
  final TextStyle? style;

  /// Опорная строка для ширины: держит разрядность, чтобы при «99 → 100»
  /// число не дёргалось по горизонтали.
  final String? sample;

  final AlignmentGeometry alignment;

  /// Выравнивание внутри опорной ширины. По умолчанию выводится из
  /// [alignment]: `centerRight` → вправо, `centerLeft` → влево.
  final TextAlign? textAlign;

  @override
  State<SmoothDigits> createState() => _SmoothDigitsState();
}

class _SmoothDigitsState extends State<SmoothDigits> {
  static const Duration _fade = Duration(milliseconds: 220);

  double _width(TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: widget.sample ?? '${widget.value}', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  Alignment _align() {
    final fromText = switch (widget.textAlign) {
      TextAlign.left => Alignment.centerLeft,
      TextAlign.center => Alignment.center,
      TextAlign.right => Alignment.centerRight,
      _ => null,
    };
    if (fromText != null) return fromText;
    return switch (widget.alignment) {
      Alignment.centerLeft ||
      AlignmentDirectional.centerStart => Alignment.centerLeft,
      Alignment.center => Alignment.center,
      _ => Alignment.centerRight,
    };
  }

  @override
  Widget build(BuildContext context) {
    final base =
        widget.style ??
        (Theme.of(context).textTheme.titleMedium ?? const TextStyle());
    // Табличные цифры: без них разряды «пляшут» по горизонтали на смене
    // значения.
    final style = base.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final chars = '${widget.value}'.split('');
    final last = chars.length - 1;
    return SizedBox(
      width: _width(style),
      child: Align(
        alignment: _align(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < chars.length; i++)
              // Ключ считается ОТ ПРАВОГО края: единицы остаются единицами,
              // и при «500 → 1500» анимируется только новый старший разряд,
              // а не все четыре цифры подряд.
              AnimatedSwitcher(
                key: ValueKey('digit_${last - i}'),
                duration: _fade,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.center,
                  children: <Widget>[...previous, ?current],
                ),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.72, end: 1).animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  chars[i],
                  key: ValueKey(chars[i]),
                  style: style,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
