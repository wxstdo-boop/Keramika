import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/reality_check_service.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../services/completion_log_service.dart';
import '../l10n/translations.dart';

// import '../utils/smooth_refresh.dart'; (removed, no longer used)

class RealityCheckStatsScreen extends StatefulWidget {
  const RealityCheckStatsScreen({super.key});

  @override
  State<RealityCheckStatsScreen> createState() =>
      _RealityCheckStatsScreenState();
}

class _RealityCheckStatsScreenState extends State<RealityCheckStatsScreen>
    with SingleTickerProviderStateMixin {
  final _rcSvc = RealityCheckService();
  final _habitSvc = HabitService();
  final _taskSvc = TaskService();
  final _logSvc = CompletionLogService();

  /// Постоянная «живая» анимация чисел: лёгкий глитч/размытие.
  late final AnimationController _glitchCtrl;

  @override
  void initState() {
    super.initState();
    _rcSvc.load();
    _habitSvc.load();
    _taskSvc.load();
    _logSvc.load().then((_) => _logSvc.recordToday());
    _glitchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _glitchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final habitsDone = _habitSvc.habits.where((h) => h.doneToday).length;
    final habitsTotal = _habitSvc.habits.length;
    final tasksDone = _taskSvc.tasks.where((t) => t.done).length;
    final tasksTotal = _taskSvc.tasks.length;
    // Когда раздел РП выключен — он не участвует в общей статистике:
    // ни в общем проценте, ни в процентах completion, ни в дневной цифте.
    final rcOn = _rcSvc.enabled;
    final rcToday = rcOn ? _rcSvc.totalChecksToday : 0;
    final rcTotal = rcOn ? _rcSvc.checksPerDay : 0;

    final rcTarget = rcOn ? _rcSvc.checks.length * _rcSvc.checksPerDay : 0;
    final totalItems =
        habitsTotal +
        tasksTotal +
        (rcTarget > 0 ? rcTarget : (rcOn ? _rcSvc.checks.length : 0));
    final totalDone = habitsDone + tasksDone + rcToday;
    final overallPct = totalItems > 0
        ? (totalDone / totalItems).clamp(0.0, 1.0)
        : 0.0;

    // Daily motivation quote based on day of year
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final quoteIndex = (dayOfYear + DateTime.now().year) % 15;
    final motivationKeys = List.generate(15, (i) => 'motivationQuote${i + 1}');
    final motivationQuote = Translations.t(motivationKeys[quoteIndex], context);

    // 30 дней берём ВСЕГДА: lastDays сам дозаполняет дыры из streak
    // привычек, поэтому график виден даже при пустом логе (новая
    // установка) — раньше при пустом логе график вовсе не показывался.
    final monthDays = _logSvc.lastDays(30);

    final bodyContent = SingleChildScrollView(
      // Как на остальных экранах: свайп вверх/вниз работает всегда,
      // даже когда контента мало (иначе жест «не ловился» и экран
      // казался залипшим).
      // Та же физика, что на экранах привычек/задач: AlwaysScrollable +
      // Bouncing — свайп вверх/вниз работает всегда и с упругим
      // «оттягиванием» на краях (раньше ClampingScrollPhysics не давал
      // оттягивания, поэтому экран казался «залипшим»).
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        // Нижний отступ до навбара: контент при свайпе не «залезает»
        // за полосу навигации и не обрезается ею.
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        children: [
          _buildOverallSummary(context, theme, overallPct),
          const SizedBox(height: 16),
          _MonthChart(
            days: monthDays,
            glitch: _glitchCtrl,
            theme: theme,
          ),
          const SizedBox(height: 16),
          // Daily Motivation Card
          Card(
            color: theme.colorScheme.secondaryContainer,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.format_quote,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        Translations.t('dailyMotivation', context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // Кавычки убраны по дизайну: цитата читается как
                    // обычный мотивационный текст, а не как «вложенная»
                    // реплика. Визуальный акцент всё равно есть — это
                    // иконка «format_quote» слева и курсив самого текста.
                    motivationQuote.trim(),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (rcOn) ...[
            _buildStatCard(
              context,
              theme,
              Icons.psychology_outlined,
              Translations.t('rcStat', context),
              rcToday,
              rcTotal,
              glitch: _glitchCtrl,
            ),
            const SizedBox(height: 16),
          ],
          _buildStatCard(
            context,
            theme,
            Icons.auto_awesome_outlined,
            Translations.habitsOf(context),
            habitsDone,
            habitsTotal,
            glitch: _glitchCtrl,
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            context,
            theme,
            Icons.checklist_outlined,
            Translations.tasksOf(context),
            tasksDone,
            tasksTotal,
            glitch: _glitchCtrl,
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('statistics', context)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _rcSvc.load();
          await _habitSvc.load();
          await _taskSvc.load();
          await _logSvc.recordToday();
        },
        child: bodyContent,
      ),
    );
  }

  Widget _buildOverallSummary(
    BuildContext context,
    ThemeData theme,
    double pct,
  ) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              Translations.t('overallCompletion', context),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            ClipRect(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                // Без Transform.translate(-10px): внутри ClipRect текст при
                // подъёме обрезался сверху — «половины цифр не видно».
                // Чистый fade не режет цифры.
                transitionBuilder: (child, animation) {
                  return FadeTransition(opacity: animation, child: child);
                },
                child: _GlitchText(
                  '${(pct * 100).toInt()}%',
                  key: ValueKey('overall_${(pct * 100).toInt()}'),
                  ctrl: _glitchCtrl,
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    ThemeData theme,
    IconData icon,
    String label,
    int done,
    int total, {
    required Animation<double> glitch,
  }) {
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                    child: _GlitchText(
                      '$done / $total',
                      key: ValueKey('count_$done/$total'),
                      ctrl: glitch,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: pct,
              minHeight: 12,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            const SizedBox(height: 8),
            Text(
              '${(pct * 100).toInt()}% ${Translations.t('completed', context)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Число с постоянной «живой» анимацией: мягкий глитч (лёгкий сдвиг по X,
/// размытие и перелив тени) — читается, но выглядит живым, как неоновые
/// цифры. Скорость — от [ctrl] (общий контроллер, повторяется).
class _GlitchText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final Animation<double> ctrl;

  const _GlitchText(this.text, {super.key, required this.ctrl, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final t = ctrl.value;
        // Плавная волна «глитча»: лёгкая пульсация цветовых каналов.
        final wave = (math.sin(t * 2 * math.pi) + 1) / 2;
        final base = style ?? const TextStyle();
        // СТАТИКА: текст стоит на месте (никакого сдвига/размытия),
        // «глитч» — только расщепление цветных теней, пульсирующее
        // по амплитуде. Цвета холодный/тёплый — как RGB-расщепление.
        return Text(
          text,
          style: base.copyWith(
            shadows: [
              Shadow(
                color: const Color(0xFFFF3B5C).withValues(
                  alpha: 0.08 + wave * 0.14,
                ),
                blurRadius: 1.5,
                offset: const Offset(1.1, 0),
              ),
              Shadow(
                color: const Color(0xFF33D1FF).withValues(
                  alpha: 0.07 + wave * 0.12,
                ),
                blurRadius: 1.5,
                offset: const Offset(-1.1, 0),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// График «последние 30 дней»: объёмные 3D-столбики. Каждый день — один
/// «кирпичик» из двух фрагментов (привычки сверху, задачи снизу) с
/// псевдо-3D боковой гранью и градиентом, поверх — линия тренда.
/// Плавный рост при входе, подписи дней недели и «лучший день».
class _MonthChart extends StatelessWidget {
  final List<DayCompletion> days;
  final Animation<double> glitch;
  final ThemeData theme;

  const _MonthChart({
    required this.days,
    required this.glitch,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    // Максимум по стеку (привычки + задачи) — для нормировки высоты.
    var maxV = 1;
    for (final d in days) {
      final total = d.habits + d.tasks;
      if (total > maxV) maxV = total;
    }
    final habitColor = theme.colorScheme.primary.withValues(alpha: 0.95);
    final taskColor = theme.colorScheme.secondary.withValues(alpha: 0.95);

    // Итоги за месяц.
    var activeDays = 0;
    var bestTotal = 0;
    for (final d in days) {
      final total = d.habits + d.tasks;
      if (total > 0) activeDays++;
      if (total > bestTotal) bestTotal = total;
    }

    final totalHabit = days.fold(0, (a, b) => a + b.habits);
    final totalTask = days.fold(0, (a, b) => a + b.tasks);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.bar_chart_rounded,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    Translations.t('monthChartTitle', context),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Суммарные значения месяца — живые числа.
                  _GlitchText(
                    '$totalHabit + $totalTask',
                    ctrl: glitch,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Площадка графика: Улучшенная композиция — тонкая сетка и
            // плавная линия тренда со свечением рисуются CustomPaint'ом
            // в тех же координатах, что и столбцы; метки дней — отдельной
            // строкой под площадкой.
            SizedBox(
              height: 156,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) {
                  final values = [
                    for (final d in days) (d.habits + d.tasks) / maxV,
                  ];
                  return Column(
                    children: [
                      SizedBox(
                        height: 136,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ChartDecorPainter(
                                  values: values,
                                  grow: grow,
                                  gridColor: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.055),
                                  lineColor: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var i = 0; i < days.length; i++)
                                  Expanded(
                                    child: _stackedBar(
                                      days[i],
                                      maxV,
                                      habitColor,
                                      taskColor,
                                      grow,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),
                      // Метки под столбцами: день недели по каждой 5-й
                      // колонке, «сегодня» — точка.
                      Row(
                        children: [
                          for (var i = 0; i < days.length; i++)
                            Expanded(child: Center(child: _dayLabel(i))),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _legend(context, habitColor, Icons.check_circle_outline, Translations.t('monthChartHabits', context)),
                const SizedBox(width: 12),
                _legend(context, taskColor, Icons.checklist_outlined, Translations.t('monthChartTasks', context)),
                const Spacer(),
                _GlitchText(
                  '$activeDays ${Translations.t('monthChartDays', context)}',
                  ctrl: glitch,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Объёмный столбик: нижний фрагмент — задачи, верхний — привычки.
  /// «Объём» — правая/нижняя тёмная грань (сдвиг на 3px по диагонали)
  /// и лёгкий вертикальный градиент на лицевой части.
  Widget _stackedBar(
    DayCompletion d,
    int maxV,
    Color habitColor,
    Color taskColor,
    double grow,
  ) {
    final habitH = maxV <= 0
        ? 0.0
        : (d.habits / maxV).clamp(0.0, 1.0) * 136 * grow;
    final taskH = maxV <= 0
        ? 0.0
        : (d.tasks / maxV).clamp(0.0, 1.0) * 136 * grow;
    final total = habitH + taskH;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SizedBox(
        // БЕЗ «призрачного» тёмного столбика позади: объём даёт мягкий
        // градиент на самой колонке. Ширина чуть больше — спокойнее.
        width: 13,
        height: 136,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // Единый столбик: привычки (верх) + задачи (низ), со скруглением
            // ВСЕХ углов (верхние — у верхнего фрагмента, нижние — у
            // нижнего). Лёгкий градиент на каждом фрагменте даёт «объём».
            if (total > 0)
              Positioned(
                left: 0,
                top: 136 - total,
                width: 13,
                height: total,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (habitH > 0)
                      _face(
                        height: habitH,
                        color: habitColor,
                        radius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    if (taskH > 0)
                      _face(
                        height: taskH,
                        color: taskColor,
                        radius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _face({
    required double height,
    required Color color,
    required BorderRadius radius,
  }) {
    final top = Color.lerp(color, Colors.white, 0.20)!;
    final bottom = Color.lerp(color, Colors.black, 0.12)!;
    return Container(
      width: 13,
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, color, bottom],
        ),
        borderRadius: radius,
      ),
    );
  }

  Widget _dayLabel(int i) {
    final isToday = i == days.length - 1;
    if (isToday) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
      );
    }
    // Каждая 5-я колонка — буква дня недели.
    if ((days.length - 1 - i) % 5 != 0) return const SizedBox(height: 5);
    const names = ['П', 'В', 'С', 'Ч', 'П', 'С', 'В'];
    final wd = HabitService.mskNow().weekday;
    // weekday: 1=Пн..7=Вс
    final label = names[(wd - 1 - (days.length - 1 - i)) % 7];
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        fontSize: 9,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _legend(BuildContext context, Color color, IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Декор площадки графика: тонкая сетка (25/50/75 % по высоте и каждая
/// 5-я колонка) плюс плавная линия тренда со свечением и мягкой заливкой
/// под ней. Координаты совпадают со столбцами: по X — 30 равных колонок
/// с центром в (i + 0.5) * cellW, по Y — от низа площадки вверх.
class _ChartDecorPainter extends CustomPainter {
  final List<double> values; // нормированные суммы дня: 0..1
  final double grow; // прогресс анимации входа 0..1
  final Color gridColor;
  final Color lineColor;

  _ChartDecorPainter({
    required this.values,
    required this.grow,
    required this.gridColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0 || values.isEmpty) return;
    final cellW = w / values.length;

    // Сетка: горизонтали на 25/50/75 % и вертикали каждые 5 дней.
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75]) {
      final y = h * (1 - f);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }
    for (var i = 0; i < values.length; i += 5) {
      final x = (i + 0.5) * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }

    // Точки тренда: центр каждой колонки на высоте значения.
    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = (values[i] * grow).clamp(0.0, 1.0);
      pts.add(Offset((i + 0.5) * cellW, h * (1 - v)));
    }
    if (pts.length < 2) return;

    // Плавная линия: квадратичные дуги через середины отрезков.
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final prev = pts[i - 1];
      final mid = Offset(
        (prev.dx + pts[i].dx) / 2,
        (prev.dy + pts[i].dy) / 2,
      );
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
    }
    path.lineTo(pts.last.dx, pts.last.dy);

    // Мягкая заливка под линией — от цвета линии до прозрачного.
    final area = Path.from(path)
      ..lineTo(pts.last.dx, h)
      ..lineTo(pts.first.dx, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withValues(alpha: 0.16),
            lineColor.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    // Свечение и сама линия тренда.
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor.withValues(alpha: 0.30)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ChartDecorPainter old) =>
      old.values != values ||
      old.grow != grow ||
      old.gridColor != gridColor ||
      old.lineColor != lineColor;
}
