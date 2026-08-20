import 'dart:math' as math;
import 'dart:ui' as ui;

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

    final monthDays = _logSvc.log.isEmpty ? null : _logSvc.lastDays(30);

    final bodyContent = SingleChildScrollView(
      // Как на остальных экранах: свайп вверх/вниз работает всегда,
      // даже когда контента мало (иначе жест «не ловился» и экран
      // казался залипшим).
      physics: const AlwaysScrollableScrollPhysics(),
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
          if (monthDays != null) ...[
            _MonthChart(
              days: monthDays,
              glitch: _glitchCtrl,
              theme: theme,
            ),
            const SizedBox(height: 16),
          ],
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
        // Плавная волна: два «дыхания» за цикл.
        final wave = (math.sin(t * 2 * math.pi * 2) + 1) / 2;
        final dx = (wave - 0.5) * 2.0; // -1..1
        final blur = 0.4 + wave * 1.1;
        final shadowA = 0.10 + wave * 0.25;
        final base = style ?? const TextStyle();
        final glow = base.color ?? Colors.black;
        return Transform.translate(
          offset: Offset(dx * 0.8, 0),
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: blur * 0.25,
              sigmaY: blur * 0.25,
            ),
            child: Text(
              text,
              style: base.copyWith(
                shadows: [
                  Shadow(
                    color: glow.withValues(alpha: shadowA),
                    blurRadius: 4 + wave * 6,
                    offset: Offset(dx * 1.2, 0),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// График «последние 30 дней»: две серии столбиков (привычки — фиолетовый,
/// задачи — синий), плавный рост при входе, подписи дней недели и число
/// «лучший день». Значения над столбиками — с той же глитч-анимацией.
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
    // Максимум по обеим сериям — для нормировки высоты.
    var maxV = 1;
    for (final d in days) {
      if (d.habits > maxV) maxV = d.habits;
      if (d.tasks > maxV) maxV = d.tasks;
    }
    final habitColor = theme.colorScheme.primary.withValues(alpha: 0.92);
    final taskColor = theme.colorScheme.secondary.withValues(alpha: 0.92);

    // Итоги за месяц.
    var habitDays = 0;
    var taskDays = 0;
    var bestTotal = 0;
    for (final d in days) {
      if (d.habits > 0) habitDays++;
      if (d.tasks > 0) taskDays++;
      final total = d.habits + d.tasks;
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
            SizedBox(
              height: 130,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < days.length; i++) ...[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              // Две колонки: привычка и задача.
                              SizedBox(
                                height: 115,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _bar(days[i].habits, maxV, habitColor, grow),
                                    const SizedBox(width: 2),
                                    _bar(days[i].tasks, maxV, taskColor, grow),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 3),
                              // Метка: день недели по каждой 5-й колонке,
                              // «сегодня» — точка.
                              _dayLabel(i),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _legend(context, habitColor, Translations.t('monthChartHabits', context)),
                const SizedBox(width: 14),
                _legend(context, taskColor, Translations.t('monthChartTasks', context)),
                const Spacer(),
                _GlitchText(
                  '$bestTotal ★',
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

  Widget _bar(int v, int maxV, Color color, double grow) {
    final h = maxV <= 0 ? 0.0 : (v / maxV).clamp(0.0, 1.0) * 100 * grow;
    return Container(
      width: 4,
      height: h,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _dayLabel(int i) {
    final now = HabitService.mskToday();
    final day = now.subtract(Duration(days: days.length - 1 - i));
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

  Widget _legend(BuildContext context, Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
