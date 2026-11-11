import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import 'press_scale.dart';

/// Полностью скруглённый выбор даты вместо стандартного Material-пикера.
///
/// Стандартный `showDatePicker` на бюджетниках выглядит «тяжёлым» и
/// прямоугольным. Здесь — свой диалог: радиус 28, круглые дни, плавная
/// смена месяца (slide+fade) и мягкая отдача на каждом дне.
Future<DateTime?> showDueDatePicker(BuildContext context, DateTime? initial) {
  return showGeneralDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, a, b) => _DueDatePickerDialog(initial: initial),
    transitionBuilder: (ctx, anim, _, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _DueDatePickerDialog extends StatefulWidget {
  final DateTime? initial;

  const _DueDatePickerDialog({this.initial});

  @override
  State<_DueDatePickerDialog> createState() => _DueDatePickerDialogState();
}

class _DueDatePickerDialogState extends State<_DueDatePickerDialog> {
  /// Высота одной клетки календаря при ширине диалога 360 и набивке 18 px:
  /// (360 - 36) / 7 ≈ 46. По ней же фиксируем высоту сетки на 6 недель —
  /// диалог не меняет размер при смене месяца.
  static const double _cellSize = 46.0;

  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial ?? DateTime.now();
    _month = DateTime(_selected.year, _selected.month, 1);
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta, 1);
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final local = MaterialLocalizations.of(context);

    final firstDay = local.firstDayOfWeekIndex; // 0=Sun..6=Sat
    final weekdays = <String>[
      for (var i = 0; i < 7; i++) local.narrowWeekdays[(firstDay + i) % 7],
    ];
    final first = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final firstWeekday = first.weekday % 7; // 0=Sun..6=Sat
    final leading = (firstWeekday - firstDay) % 7;
    final total = ((leading + daysInMonth + 6) ~/ 7) * 7;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Translations.t('duePickDate', context, 'Выбрать дату'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PressScale(
                  pressedScale: 0.9,
                  duration: const Duration(milliseconds: 160),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _MonthNavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _shiftMonth(-1),
                ),
                Expanded(
                  // Название месяца меняется КРОССФЕЙДОМ: горизонтальный
                  // слайд читался как «дёргает вправо» (новое имя въезжало
                  // сбоку, а старое уезжало, и текст на миг «двоился»).
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      local.formatMonthYear(_month),
                      key: ValueKey('${_month.year}-${_month.month}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                _MonthNavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _shiftMonth(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final w in weekdays)
                  Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // ВЫСОТА СЕТКИ ФИКСИРОВАНА под максимальные 6 недель: при
            // переходе между месяцами число недель меняется (5↔6), и без
            // этого диалог «скукоживался»/раздувался скачком — экран
            // дёргался. Постоянная высота + кроссфейд без слайда: смена
            // месяца идёт спокойно и стабильно.
            SizedBox(
              height: 6 * _cellSize,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: GridView.builder(
                key: ValueKey('${_month.year}-${_month.month}'),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                ),
                itemCount: total,
                itemBuilder: (context, i) {
                  final day = i - leading + 1;
                  if (day < 1 || day > daysInMonth) {
                    return const SizedBox.shrink();
                  }
                  final date = DateTime(_month.year, _month.month, day);
                  final selected = _sameDay(date, _selected);
                  final today = _sameDay(date, DateTime.now());
                  return Padding(
                    padding: const EdgeInsets.all(3),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        Haptics.select();
                        setState(() => _selected = date);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? cs.primary : Colors.transparent,
                          border: today && !selected
                              ? Border.all(
                                  color: cs.primary.withValues(alpha: 0.6),
                                  width: 1.2,
                                )
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: selected ? cs.onPrimary : cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(Translations.cancelOf(context)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => Navigator.pop(context, _selected),
                  child: Text(
                    Translations.t('done', context, 'Готово'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MonthNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PressScale(
      pressedScale: 0.9,
      duration: const Duration(milliseconds: 160),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHighest,
          ),
          child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
