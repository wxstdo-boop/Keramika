import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/nutrition_service.dart';

/// Тренды за окно истории: столбики дневных калорий, линия личной нормы и
/// три сводки под графиком.
///
/// График — ОДИН CustomPaint на все столбики: двадцать отдельных виджетов с
/// анимацией высоты стоили бы на Adreno 610 дороже, чем весь экран. Дёргается
/// только сегодняшний столбик (его значение приходит уже «докрученным»
/// снаружи), поэтому ни одного per-frame-тикера здесь нет.
class NutritionTrends extends StatelessWidget {
  const NutritionTrends({
    super.key,
    required this.days,
    required this.norm,
    required this.todayCalories,
  });

  final List<NutritionDay> days;

  /// Суточная норма — она же горизонталь на графике.
  final int norm;

  /// Калории сегодня, уже с плавным промежуточным значением анимации.
  final double todayCalories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final today = DateTime.now();
    final filled = days.where((d) => d.meals > 0).toList();
    final avg = filled.isEmpty
        ? 0
        : (filled.fold(0, (sum, d) => sum + d.calories) / filled.length)
              .round();
    final onTarget = filled
        .where((d) => d.calories > 0 && d.calories <= norm)
        .length;
    final best = filled.isEmpty
        ? 0
        : filled.map((d) => d.calories).reduce(math.max);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  Translations.t('trends', context, 'Тренды'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  // Окно задаёт сам график, поэтому в строках оно плейсхолдером.
                  Translations.t(
                    'trendsWindow',
                    context,
                    'за {n} дней',
                  ).replaceAll('{n}', '${days.length}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendsPainter(
                  days: days,
                  norm: norm,
                  todayCalories: todayCalories,
                  bar: cs.primary,
                  over: cs.tertiary,
                  empty: cs.surfaceContainerHighest,
                  line: cs.outline,
                  today: today,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Summary(
                  label: Translations.t('avgPerDay', context, 'Среднее в день'),
                  value: '$avg',
                  unit: Translations.t('kcalShort', context, 'ккал'),
                  color: cs.primary,
                ),
                _Summary(
                  label: Translations.t(
                    'daysOnTarget',
                    context,
                    'дней в норме',
                  ),
                  value: '$onTarget',
                  unit: '/ ${filled.length}',
                  color: cs.tertiary,
                ),
                _Summary(
                  label: Translations.t('bestDay', context, 'лучший день'),
                  value: '$best',
                  unit: Translations.t('kcalShort', context, 'ккал'),
                  color: cs.secondary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна сводка под графиком.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 3),
              Text(
                unit,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendsPainter extends CustomPainter {
  _TrendsPainter({
    required this.days,
    required this.norm,
    required this.todayCalories,
    required this.bar,
    required this.over,
    required this.empty,
    required this.line,
    required this.today,
  });

  final List<NutritionDay> days;
  final int norm;

  /// Калории сегодня с промежуточным значением анимации: только этот
  /// столбик и меняет высоту, остальные берутся из данных как есть.
  final double todayCalories;
  final Color bar;
  final Color over;
  final Color empty;
  final Color line;
  final DateTime today;

  static const double _gap = 3;

  /// Сколько ккал показывать для дня: сегодняшний — с учётом докрутки.
  double _caloriesOf(NutritionDay d) =>
      _isToday(d.date) ? todayCalories : d.calories.toDouble();

  bool _isToday(DateTime d) =>
      d.year == today.year && d.month == today.month && d.day == today.day;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final n = days.length;
    final slotW = (size.width - _gap * (n - 1)) / n;
    // Планка графика: норма с запасом, но не меньше реального максимума —
    // иначе лучший день переедет верх графика, и столбики упрутся в потолок.
    final maxV = math.max(norm * 1.3, _peak);
    final fill = Paint()..isAntiAlias = true;

    for (var i = 0; i < n; i++) {
      final d = days[i];
      final x = i * (slotW + _gap);
      final calories = _caloriesOf(d);
      if (calories <= 0) {
        // Пустой день — тонкая рисочка на базовой, чтобы ряд читался
        // непрерывным, а не «проваливался».
        fill.color = empty;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - 2, slotW, 2),
            const Radius.circular(1),
          ),
          fill,
        );
        continue;
      }
      final h = (calories / maxV * size.height).clamp(3.0, size.height);
      fill.color = calories > norm
          ? over
          : bar.withValues(alpha: _isToday(d.date) ? 1.0 : 0.66);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, slotW, h),
          Radius.circular(math.min(slotW / 2, 4)),
        ),
        fill,
      );
    }

    // Линия нормы.
    final y = size.height - (norm / maxV * size.height);
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..isAntiAlias = true
        ..color = line
        ..strokeWidth = 1.2,
    );
  }

  double get _peak {
    var m = 0.0;
    for (final d in days) {
      final c = _caloriesOf(d);
      if (c > m) m = c;
    }
    return m;
  }

  @override
  bool shouldRepaint(covariant _TrendsPainter old) =>
      old.days != days ||
      old.todayCalories != todayCalories ||
      old.norm != norm ||
      old.bar != bar ||
      old.over != over ||
      old.empty != empty ||
      old.line != line ||
      old.today != today;
}
