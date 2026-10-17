import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/nutrition_service.dart';
import 'rolling_counter.dart';

/// Тренды за окно истории: столбики дневных калорий, линия личной нормы и
/// три сводки под графиком.
///
/// График — ОДИН CustomPaint на все столбики: двадцать отдельных виджетов с
/// анимацией высоты стоили бы на Adreno 610 дороже, чем весь экран. Дёргается
/// только сегодняшний столбик (его значение приходит уже «докрученным»
/// снаружи), поэтому ни одного per-frame-тикера здесь нет.
///
/// Появление графика — одна волна слева направо на весь CustomPaint, а не
/// двадцать независимых анимаций: столбики «вырастают» из базовой линии,
/// норма проявляется вместе с ними.
class NutritionTrends extends StatelessWidget {
  const NutritionTrends({
    super.key,
    required this.days,
    required this.norm,
    required this.todayCalories,
    this.elevation = 1,
    this.radius = 20,
  });

  final List<NutritionDay> days;

  /// Суточная норма — она же горизонталь на графике.
  final int norm;

  /// Калории сегодня, уже с плавным промежуточным значением анимации.
  final double todayCalories;

  /// Тень карточки. Снаружи карточку обводят градиентным кольцом, у которого
  /// своя тень, — тогда здесь ноль, чтобы тени не складывались в грязный
  /// ореол по краю.
  final double elevation;

  /// Радиус углов. Кольцо обводки задаёт его на толщину кольца меньше
  /// внешнего, иначе в стыке углов видна щель.
  final double radius;

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
      elevation: elevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
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
              height: 104,
              width: double.infinity,
              child: filled.isEmpty
                  ? Center(
                      child: Text(
                        Translations.t('noMeals', context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (context, reveal, _) => CustomPaint(
                        painter: _TrendsPainter(
                          days: days,
                          norm: norm,
                          todayCalories: todayCalories,
                          bar: cs.primary,
                          over: cs.tertiary,
                          empty: cs.surfaceContainerHighest,
                          line: cs.outline,
                          today: today,
                          reveal: reveal,
                        ),
                      ),
                    ),
            ),
            if (filled.isNotEmpty) ...[
              const SizedBox(height: 6),
              // Подписи стоят по тем же слотам, что и столбики: каждая —
              // Expanded в общей строке, поэтому центры совпадают. Пишем не
              // под каждым днём (20 чисел сливаются), а раз в пять дней и
              // всегда под сегодняшним.
              _DayLabels(days: days),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _Summary(
                  label: Translations.t('avgPerDay', context, 'Среднее в день'),
                  value: avg,
                  unit: Translations.t('kcalShort', context, 'ккал'),
                  color: cs.primary,
                ),
                _Divider(color: cs.outlineVariant),
                _Summary(
                  label: Translations.t(
                    'daysOnTarget',
                    context,
                    'дней в норме',
                  ),
                  value: onTarget,
                  unit: '/ ${filled.length}',
                  color: cs.tertiary,
                ),
                _Divider(color: cs.outlineVariant),
                _Summary(
                  label: Translations.t('bestDay', context, 'лучший день'),
                  value: best,
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

/// Подписи дат под графиком.
class _DayLabels extends StatelessWidget {
  const _DayLabels({required this.days});

  final List<NutritionDay> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final n = days.length;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 9.5,
      height: 1.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 13,
      // Шаг подписей подбирается по ширине слота: при окне в 60 дней (подарок
      // 12-го дня) «раз в пять» давало 12 чисел на 330 px и они наезжали друг
      // на друга.
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxWidth / n;
          final stride = math.max(1, (40 / slot).ceil());
          return Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(
                  child: Center(
                    child: (i == n - 1 || (n - 1 - i) % stride == 0)
                        ? Text(
                            '${days[i].date.day}',
                            style: style?.copyWith(
                              color: i == n - 1
                                  ? cs.primary
                                  : cs.onSurfaceVariant.withValues(alpha: 0.65),
                              fontWeight: i == n - 1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          );
        },
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
  final int value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      color: color,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FittedBox вместо голого Row: на узком экране «лучший день» с
          // четырьмя разрядами и «ккал» переполнял треть карточки
          // (жёлто-чёрная полоса). Значение мягко уменьшается, а не режется.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // Сводка пересчитывается при каждом новом приёме пищи —
                // барабан доводит её до нового значения, а не переставляет
                // цифры одним кадром. При появлении карточки — с нуля.
                AnimatedCounter(
                  value: value.toDouble(),
                  from: 0,
                  duration: const Duration(milliseconds: 620),
                  style: valueStyle,
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

/// Тонкий разделитель между сводками.
class _Divider extends StatelessWidget {
  const _Divider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: color.withValues(alpha: 0.6),
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
    required this.reveal,
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

  /// 0…1 — волна появления графика.
  final double reveal;

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
    final maxV = math.max(norm * 1.25, _peak * 1.04);
    final fill = Paint()..isAntiAlias = true;
    final radius = math.min(slotW / 2, 4.0);

    // Базовая линия: ряд пустых дней читается как шкала, а не как обрыв.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..isAntiAlias = true
        ..color = line.withValues(alpha: 0.30 * reveal)
        ..strokeWidth = 1,
    );

    for (var i = 0; i < n; i++) {
      final d = days[i];
      final x = i * (slotW + _gap);
      final calories = _caloriesOf(d);
      // Волна слева направо: столбик входит в свой рост с задержкой по
      // индексу, а не все разом.
      final delayed = (reveal * 1.4 - (i / n) * 0.4).clamp(0.0, 1.0);
      final grow = Curves.easeOutCubic.transform(delayed);
      if (calories <= 0) {
        // Пустой день — тонкая рисочка на базовой, чтобы ряд читался
        // непрерывным, а не «проваливался».
        fill.color = empty.withValues(alpha: 0.9 * grow);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - 2, slotW, 2),
            const Radius.circular(1),
          ),
          fill,
        );
        continue;
      }
      final h = calories * grow / maxV * size.height;
      if (h < 0.5) continue;
      final shown = math.max(h, grow > 0.985 ? 2.5 : 0.0);
      fill.color = calories > norm
          ? over
          : bar.withValues(alpha: _isToday(d.date) ? 1.0 : 0.66);
      final rect = Rect.fromLTWH(x, size.height - shown, slotW, shown);
      // Скруглены только верхние углы: низ столбика стоит на базовой, и
      // закругление снизу оставляло под ним «просвет» в один кадр.
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: Radius.circular(radius),
          topRight: Radius.circular(radius),
        ),
        fill,
      );
      // Маркер сегодняшнего дня над столбиком — глаз находит «сейчас» без
      // подписи под каждой датой.
      if (_isToday(d.date) && rect.top > 8) {
        canvas.drawCircle(
          Offset(rect.center.dx, rect.top - 5),
          2.2,
          fill..color = calories > norm ? over : bar,
        );
      }
    }

    // Линия нормы — пунктиром: сплошная читалась как ещё один столбик.
    final y = size.height - (norm / maxV * size.height);
    final dashPaint = Paint()
      ..isAntiAlias = true
      ..color = line.withValues(alpha: 0.55 * reveal)
      ..strokeWidth = 1.2;
    const dash = 4.0;
    const space = 4.0;
    for (var dx = 0.0; dx < size.width; dx += dash + space) {
      canvas.drawLine(
        Offset(dx, y),
        Offset(math.min(dx + dash, size.width), y),
        dashPaint,
      );
    }
    // Подпись нормы у правого края, над линией: без неё пунктир ничего не
    // объясняет.
    if (reveal > 0.6 && y > 14) {
      final tp = TextPainter(
        text: TextSpan(
          text: '$norm',
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w600,
            color: line.withValues(alpha: 0.85 * reveal),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - tp.width, y - tp.height - 1.5));
    }
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
      old.today != today ||
      old.reveal != reveal;
}
