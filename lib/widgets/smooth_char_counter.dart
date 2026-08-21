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
    return AnimatedSwitcher(
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
        style: TextStyle(
          fontSize: 12,
          height: 1,
          fontWeight: nearLimit ? FontWeight.w700 : FontWeight.w500,
          color: nearLimit
              ? scheme.primary
              : scheme.onSurfaceVariant.withValues(alpha: 0.75),
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
