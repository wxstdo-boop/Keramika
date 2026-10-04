import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import 'press_scale.dart';

/// Цвет приоритета — тот же язык, что у таблетки приоритета в списке задач.
Color priorityColor(int p, ThemeData theme) => switch (p) {
  2 => Colors.red.shade400,
  1 => Colors.orange.shade500,
  _ => Colors.green.shade500,
};

/// Иконка приоритета: маркер совпадает с иконкой в карточке задачи,
/// поэтому «высокий» в списке и «высокий» в форме — одна и та же фигура.
IconData priorityIcon(int p) => switch (p) {
  2 => Icons.warning_amber_rounded,
  1 => Icons.hourglass_empty_rounded,
  _ => Icons.push_pin_rounded,
};

/// Выбор приоритета: три объёмные капсулы вместо плоского SegmentedButton.
///
/// «Глубина» собрана из трёх слоёв: диагональный градиент заливки,
/// световой блик по верхней кромке и цветное свечение-тень под выбранной
/// капсулой. Невыбранные остаются нейтральными — так активный уровень
/// читается одним взглядом, без сравнения подписей.
class PrioritySelector extends StatelessWidget {
  const PrioritySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (var p = 0; p < 3; p++) ...[
          if (p > 0) const SizedBox(width: 8),
          Expanded(
            child: _PriorityCapsule(
              priority: p,
              selected: value == p,
              theme: theme,
              onTap: () {
                if (value == p) return;
                Haptics.select();
                onChanged(p);
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _PriorityCapsule extends StatelessWidget {
  const _PriorityCapsule({
    required this.priority,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final int priority;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final color = priorityColor(priority, theme);
    final label = switch (priority) {
      2 => Translations.t('priorityHigh', context),
      1 => Translations.t('priorityMedium', context),
      _ => Translations.t('priorityLow', context),
    };

    return PressScale(
      pressedScale: 0.96,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [
                      color.withValues(alpha: isDark ? 0.38 : 0.30),
                      color.withValues(alpha: isDark ? 0.16 : 0.10),
                    ]
                  : [
                      cs.onSurface.withValues(alpha: 0.04),
                      cs.onSurface.withValues(alpha: 0.02),
                    ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.60)
                  : cs.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
              width: selected ? 1.4 : 1,
            ),
            // Тень работает «подсветкой»: у выбранной капсулы она цветная и
            // заметно приподнимает плашку над формой.
            boxShadow: [
              BoxShadow(
                color: selected
                    ? color.withValues(alpha: isDark ? 0.40 : 0.28)
                    : Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                blurRadius: selected ? 18 : 8,
                spreadRadius: selected ? -2 : 0,
                offset: Offset(0, selected ? 6 : 2),
              ),
            ],
          ),
          // Третий слой объёма: блик по верхней кромке выбранной капсулы.
          // foregroundDecoration красится поверх содержимого, поэтому белёсая
          // полоса лежит и на тексте — как настоящий стеклянный глянец.
          foregroundDecoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.14 : 0.22),
                      Colors.white.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.45],
                  ),
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                scale: selected ? 1.12 : 1,
                child: Icon(
                  priorityIcon(priority),
                  size: 17,
                  color: selected
                      ? color
                      : cs.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: (theme.textTheme.bodySmall ?? const TextStyle())
                      .copyWith(
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? isDark
                                  ? Colors.white
                                  : Color.lerp(color, Colors.black, 0.35)
                            : cs.onSurfaceVariant,
                        letterSpacing: 0.2,
                      ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
