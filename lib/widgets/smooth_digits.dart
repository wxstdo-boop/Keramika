import 'package:flutter/material.dart';

import 'smooth_typing.dart';

/// Число, которое меняется ПО БУКВАМ — тем же приёмом, что и поля ввода
/// ([SmoothTyping]): изменившаяся цифра проявляется из прозрачного, а старая
/// так же мягко гаснет. Это и есть «плавная смена очков рейтинга»: не подмена
/// кадром и не грубый барабан, а живой отклик, как у счётчика в поле очков.
///
/// Внутри — настоящее (невидимое) [TextField]: оно остаётся «мозгом»
/// раскладки, а буквы рисует слой [SmoothTyping]. Поэтому ширина и метрики
/// совпадают с полем очков пиксель-в-пиксель.
class SmoothDigits extends StatefulWidget {
  const SmoothDigits({
    super.key,
    required this.value,
    this.style,
    this.sample,
    this.alignment = Alignment.centerRight,
  });

  final int value;
  final TextStyle? style;

  /// Опорная строка для ширины: держит разрядность, чтобы при «99 → 100»
  /// число не дёргалось по горизонтали.
  final String? sample;

  final AlignmentGeometry alignment;

  @override
  State<SmoothDigits> createState() => _SmoothDigitsState();
}

class _SmoothDigitsState extends State<SmoothDigits> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.value}',
  );

  @override
  void didUpdateWidget(covariant SmoothDigits oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = '${widget.value}';
    if (_ctrl.text != next) _ctrl.text = next;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _width(TextStyle? style) {
    final tp = TextPainter(
      text: TextSpan(text: widget.sample ?? '${widget.value}', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width;
  }

  @override
  Widget build(BuildContext context) {
    final style =
        widget.style ??
        (Theme.of(context).textTheme.titleMedium ?? const TextStyle());
    return SmoothTyping(
      controller: _ctrl,
      style: style,
      color: style.color,
      builder: (s) => SizedBox(
        width: _width(style),
        child: TextField(
          controller: _ctrl,
          style: s,
          readOnly: true,
          showCursor: false,
          enableInteractiveSelection: false,
          textAlign: TextAlign.right,
          decoration: const InputDecoration.collapsed(hintText: ''),
        ),
      ),
    );
  }
}
