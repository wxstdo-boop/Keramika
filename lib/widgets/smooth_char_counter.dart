import 'package:flutter/material.dart';

/// Плавный счётчик символов для TextField (buildCounter): цифры мягко
/// сменяются при вводе вместо резкого «0/150 → 1/150». Единый стиль для
/// всех полей приложения.
class SmoothCharCounter extends StatelessWidget {
  final int currentLength;
  final int? maxLength;
  final bool isFocused;

  const SmoothCharCounter({
    super.key,
    required this.currentLength,
    required this.isFocused,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = maxLength == null
        ? '$currentLength'
        : '$currentLength/$maxLength';
    final nearLimit = maxLength != null && currentLength >= maxLength! * 0.9;
    final style = TextStyle(
      fontSize: 12,
      height: 1,
      fontWeight: nearLimit ? FontWeight.w700 : FontWeight.w500,
      color: nearLimit
          ? scheme.primary
          : scheme.onSurfaceVariant.withValues(alpha: 0.75),
    );
    // Стабильная ширина ПОД САМЫЙ ДЛИННЫЙ вариант («999/999»): правая грань
    // счётчика не дёргается на каждом новом разряде. Меряем реальной
    // раскладкой текста, а не «7.6 px на цифру»: жёсткий пиксельный фактор
    // не знал ни про системный масштаб шрифта (MIUI «крупный» текст), ни
    // про полужирный у лимита — счётчик не влезал в свою колонку и
    // переносил «/150» на вторую строку, наезжая на неё.
    final scaler = MediaQuery.textScalerOf(context);
    final maxDigits = (maxLength ?? currentLength).toString().length;
    final widest = maxLength == null
        ? '9' * (currentLength.toString().length).clamp(1, maxDigits)
        : '${'9' * maxDigits}/$maxLength';
    final measure =
        TextPainter(textDirection: TextDirection.ltr, textScaler: scaler)
          ..text = TextSpan(
            text: widest,
            style: style.copyWith(fontWeight: FontWeight.w700),
          );
    measure.layout();
    final counterWidth = (measure.width + 8).clamp(38.0, 220.0);
    return SizedBox(
      width: counterWidth,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.35),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          text,
          key: ValueKey('sc_$text'),
          // Одна строка всегда: если системный шрифт окажется крупнее
          // посчитанного, цифры должны выйти за габарит слота, но НЕ
          // разваливаться на вторую строку.
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          // Правое выравнивание внутри фиксированной ширины: правый край
          // счётчика не движется, когда 0 → 10 → 100.
          textAlign: TextAlign.right,
          style: style,
        ),
      ),
    );
  }
}

/// Готовый [InputCounterWidgetBuilder] — передаётся в `buildCounter:`
/// у TextField. Везде счётчики меняются одинаково плавно.
InputCounterWidgetBuilder smoothCharCounterBuilder =
    (
      context, {
      required int currentLength,
      required bool isFocused,
      int? maxLength,
    }) {
      return SmoothCharCounter(
        currentLength: currentLength,
        isFocused: isFocused,
        maxLength: maxLength,
      );
    };
