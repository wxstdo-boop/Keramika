import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../utils/motion_prefs.dart';
import '../services/reality_check_service.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../services/completion_log_service.dart';
import '../l10n/translations.dart';


class RealityCheckStatsScreen extends StatefulWidget {
  const RealityCheckStatsScreen({super.key});

  @override
  State<RealityCheckStatsScreen> createState() =>
      _RealityCheckStatsScreenState();
}

class _RealityCheckStatsScreenState extends State<RealityCheckStatsScreen>
    with SingleTickerProviderStateMixin, MotionAwareRepeat {
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
    _glitchCtrl = ambientRepeat(
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2600),
      ),
    );
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

    // Daily motivation quote based on day of year. Всего цитат 90 (было
    // захардкожено 15 — из-за этого месяц за месяцем показывались ОДНИ И ТЕ ЖЕ
    // пять-шесть цитат, «мотивация дня» выглядела сломанной). Индекс берём по
    // полному числу цитат и примешиваем год, чтобы порядок не повторялся год
    // в год.
    const quoteCount = 90;
    final dayOfYear = DateTime.now()
        .difference(DateTime(DateTime.now().year, 1, 1))
        .inDays;
    final quoteIndex =
        (dayOfYear * 7 + DateTime.now().year * 3) % quoteCount;
    final motivationQuote = Translations.t(
      'motivationQuote${quoteIndex + 1}',
      context,
    );

    // 30 дней берём ВСЕГДА: lastDays сам дозаполняет дыры из streak
    // привычек, поэтому график виден даже при пустом логе (новая
    // установка) — раньше при пустом логе график вовсе не показывался.
    final monthDays = _logSvc.lastDays(30);

    final bodyContent = SingleChildScrollView(
      // Физика — как на ОСТАЛЬНЫХ экранах (привычки, задачи, будильники):
      // упругий BouncingScrollPhysics. Раньше здесь стоял ClampingScrollPhysics,
      // и статистика «не отдавала» край — при протяжке не было того мягкого
      // натяжения/сжатия, к которому привыкли на других списках. AlwaysScrollable
      // поверх — чтобы pull-to-refresh работал и на коротком контенте.
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
          _MonthChart(days: monthDays, glitch: _glitchCtrl, theme: theme),
          const SizedBox(height: 16),
          // Daily Motivation Card — верхняя панель и сама цитата сидят на
          // своих плашках «округлённый квадрат» (мягкий радиус 12, тонкая
          // обводка): заголовок читается как панель, цитата — как вкладыш.
          _ringedCard(
            theme: theme,
            accent: theme.colorScheme.secondary,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: const BorderRadius.all(Radius.circular(18.7)),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.secondary.withValues(
                        alpha: 0.10,
                      ),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.38,
                        ),
                        width: 1.1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.format_quote,
                          size: 22,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          Translations.t('dailyMotivation', context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surface.withValues(alpha: 0.42),
                      border: Border.all(
                        color: theme.colorScheme.secondary.withValues(
                          alpha: 0.24,
                        ),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      // Кавычки убраны по дизайну: цитата читается как
                      // обычный мотивационный текст, а не как «вложенная»
                      // реплика. Визуальный акцент дают панель заголовка,
                      // иконка «format_quote» и курсив самого текста.
                      motivationQuote.trim(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontStyle: FontStyle.italic,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
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
              accent: theme.colorScheme.tertiary,
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
            accent: theme.colorScheme.primary,
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
            accent: theme.colorScheme.secondary,
            glitch: _glitchCtrl,
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('statistics', context)),
        centerTitle: true,
        leading: const BackButtonTooltip(),
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
    return _ringedCard(
      theme: theme,
      accent: theme.colorScheme.primary,
      child: Card(
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
    required Color accent,
    required Animation<double> glitch,
  }) {
    final pct = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;
    return _ringedCard(
      theme: theme,
      accent: accent,
      child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.7)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: accent),
                const SizedBox(width: 12),
                // Заголовок под защитой: длинная подпись («Проверки
                // реальности») не выпирает за карточку — ужимается
                // многоточием, а счётчик справа остаётся целым.
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
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
            // Полоса-прогресс в тон кольцу: градиент идёт от акцента к
            // третичному, но с тёмным краем — залитая «глубина» делает
            // полосу контрастнее и читабельнее на любой теме (light и dark):
            // налив темнее с каждой темой, дорожка — более тёмный контраст.
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                height: 12,
                color: theme.colorScheme.onSurface.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10,
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: pct.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color.lerp(accent, Colors.black, 0.18)!,
                          accent,
                          Color.lerp(theme.colorScheme.tertiary, Colors.black, 0.10)!,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
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
      ),
    );
  }
}

/// Обводка-кольцо: тонкий градиент по краю (акцент → третичный) вместо
/// плоской рамки — мягкий перелив по периметру, читается и на светлой, и
/// на тёмной теме. Тень одна (у кольца), чтобы не было грязного двойного
/// ореола. Внутренний радиус на толщину кольца меньше, иначе в стыке
/// видна щель. Толщина кольца теперь тонкая (0.8): «обводка тоньше» —
/// перелив стал деликатнее, без жирного края.
Widget _ringedCard({
  required ThemeData theme,
  required Widget child,
  required Color accent,
  double radius = 20,
}) {
  // Обводка карточек — тоньше и прозрачнее прежней: цветной «кант» должен
  // читаться как лёгкая подсветка у грани, а не как рамка. Раньше он был
  // заметно плотнее (толщина 0.8, альфа до 0.55) и «обводил» карточку.
  const thickness = 0.6;
  final cs = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius + thickness),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          accent.withValues(alpha: dark ? 0.38 : 0.26),
          accent.withValues(alpha: dark ? 0.07 : 0.06),
          cs.tertiary.withValues(alpha: dark ? 0.26 : 0.16),
        ],
        stops: const <double>[0, 0.55, 1],
      ),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? 0.30 : 0.06),
          blurRadius: 14,
          spreadRadius: -6,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    padding: EdgeInsets.all(thickness),
    child: child,
  );
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
    // Глитч перерисовывается каждый кадр 60 fps. Без собственного
    // RepaintBoundary грязный абзац тянет за собой перерисовку ВСЕГО слоя
    // страницы — графика, карточки, текст. Слои координаты не меняют,
    // картинка остаётся пиксель-в-пиксель той же, а на Adreno 610 это
    // разница между «листается» и «тормозит».
    return RepaintBoundary(
      child: AnimatedBuilder(
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
                  color: const Color(
                    0xFFFF3B5C,
                  ).withValues(alpha: 0.08 + wave * 0.14),
                  blurRadius: 1.5,
                  offset: const Offset(1.1, 0),
                ),
                Shadow(
                  color: const Color(
                    0xFF33D1FF,
                  ).withValues(alpha: 0.07 + wave * 0.12),
                  blurRadius: 1.5,
                  offset: const Offset(-1.1, 0),
                ),
              ],
            ),
          );
        },
      ),
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

    return _ringedCard(
      theme: theme,
      accent: theme.colorScheme.primary,
      child: Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18.7)),
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
                  // Суммарные значения месяца — живые числа. Flexible +
                  // FittedBox: даже при больших суммах число не упирается
                  // в правую грань карточки и не обрезается.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: _GlitchText(
                        '$totalHabit + $totalTask',
                        ctrl: glitch,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Площадка «галактики»: 30 дней уложены в спираль — свежий день
            // в ядре, старые расходятся по рукавам. Вместо столбиков —
            // светящиеся звёзды: размер и яркость даёт активность дня
            // (привычки + задачи), а цвет — состав дня, поэтому легенда
            // внизу честная. Спираль медленно вращается и «дышит».
            SizedBox(
              height: 300,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) => _GalaxyView(
                  days: days,
                  maxV: maxV,
                  grow: grow,
                  glitch: glitch,
                  theme: theme,
                  habitColor: habitColor,
                  taskColor: taskColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _legend(
                  context,
                  habitColor,
                  Icons.check_circle_outline,
                  Translations.t('monthChartHabits', context),
                ),
                const SizedBox(width: 12),
                _legend(
                  context,
                  taskColor,
                  Icons.checklist_outlined,
                  Translations.t('monthChartTasks', context),
                ),
                const Spacer(),
                // Число дней тоже под защитой от правой грани.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _GlitchText(
                      '$activeDays ${Translations.t('monthChartDays', context)}',
                      ctrl: glitch,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _legend(
    BuildContext context,
    Color color,
    IconData icon,
    String text,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}


/// «Галактика»: 30 дней последнего месяца, уложенные в спираль. Самый
/// свежий день — в ядре, старые расходятся по рукавам. Вместо столбиков —
/// светящиеся звёзды: размер и яркость даёт активность дня (привычки +
/// задачи), а цвет — состав дня, поэтому легенда под графиком честная.
/// Спираль медленно вращается и «дышит» от [glitch]; при включённом
/// «убрать анимации» кадр замирает, но картинка остаётся читаемой.
class _GalaxyView extends StatelessWidget {
  final List<DayCompletion> days;
  final int maxV;
  final double grow;
  final Animation<double> glitch;
  final ThemeData theme;
  final Color habitColor;
  final Color taskColor;

  const _GalaxyView({
    required this.days,
    required this.maxV,
    required this.grow,
    required this.glitch,
    required this.theme,
    required this.habitColor,
    required this.taskColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    // Значения нормируем на максимум месяца: «лучший день» — самая крупная
    // звезда, остальные — пропорционально.
    final values = <double>[
      for (final d in days)
        maxV <= 0 ? 0.0 : ((d.habits + d.tasks) / maxV).clamp(0.0, 1.0),
    ];
    // Доля привычек в дне: цвет звезды честно отражает состав дня.
    final habitRatios = <double>[
      for (final d in days)
        (d.habits + d.tasks) == 0 ? 0.5 : d.habits / (d.habits + d.tasks),
    ];
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: glitch,
        builder: (context, _) => CustomPaint(
          painter: _GalaxyPainter(
            values: values,
            habitRatios: habitRatios,
            grow: grow,
            phase: glitch.value,
            habitColor: habitColor,
            taskColor: taskColor,
            coreColor: cs.primary,
            dustColor: cs.onSurfaceVariant,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// Художник «галактики». Дни кладём по спирали: `t = i / (n-1)` — 0 у самого
/// старого дня (внешний рукав), 1 у сегодняшнего (ядро). Размер и яркость
/// точки растут к ядру и вместе со значением дня.
class _GalaxyPainter extends CustomPainter {
  final List<double> values; // активность дня 0..1 (0 — старый, n-1 — свежий)
  final List<double> habitRatios; // доля привычек в дне 0..1 (цвет звезды)
  final double grow; // прогресс входа 0..1 (анимация «прорастания»)
  final double phase; // 0..1 — вечный цикл вращения/дыхания
  final Color habitColor;
  final Color taskColor;
  final Color coreColor;
  final Color dustColor;

  _GalaxyPainter({
    required this.values,
    required this.habitRatios,
    required this.grow,
    required this.phase,
    required this.habitColor,
    required this.taskColor,
    required this.coreColor,
    required this.dustColor,
  });

  static const double _turns = 1.8;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2 - 10;
    final minR = math.max(6.0, math.min(size.width, size.height) * 0.045);

    // Полный оборот за цикл: sin/cos замкнуты на стыке 1→0, поэтому
    // вращение идёт без рывка.
    final spin = phase * 2 * math.pi;
    final breath = math.sin(spin);

    double radiusOf(double t) => minR + (maxR - minR) * (1 - t);
    double angleOf(double t) =>
        -math.pi / 2 + _turns * 2 * math.pi * t + spin * 0.35;

    // Фоновая пыль: неподвижные тусклые звёзды — глубина кадра. Позиции
    // детерминированы индексом, чтобы картинка не «кипела» между кадрами.
    final dustPaint = Paint()..isAntiAlias = true;
    for (var s = 0; s < 60; s++) {
      final a = (s * 2.399963) % (math.pi * 2); // золотой угол — ровная россыпь
      final rr = maxR * (0.18 + 0.82 * ((s * 37 % 100) / 100));
      final p = center + Offset(math.cos(a), math.sin(a)) * rr;
      final twinkle = 0.3 + 0.7 * ((s * 53 % 100) / 100);
      dustPaint.color = dustColor.withValues(alpha: 0.05 + 0.10 * twinkle);
      canvas.drawCircle(p, 0.6 + 0.8 * twinkle, dustPaint);
    }

    // Два рукава спирали — тонкие ленты, на которых «сидят» дни. Угол
    // считаем непрерывно от t, иначе лента «ломается» ступеньками.
    final armPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    for (var arm = 0; arm < 2; arm++) {
      final path = Path();
      for (var s = 0; s <= 96; s++) {
        final t = s / 96;
        final r = radiusOf(t);
        final a = angleOf(t) + arm * math.pi;
        final p = center + Offset(math.cos(a), math.sin(a)) * r;
        if (s == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      armPaint
        ..color = coreColor.withValues(alpha: 0.16)
        ..strokeWidth = math.min(size.width, size.height) * 0.028;
      canvas.drawPath(path, armPaint);
    }

    // Ядро: мягкое светящееся пятно в центре — «сегодня» вырастает из него.
    final coreR = math.min(size.width, size.height) * 0.10;
    canvas.drawCircle(
      center,
      coreR * (0.9 + 0.1 * breath),
      Paint()
        ..shader = RadialGradient(
          colors: [
            coreColor.withValues(alpha: 0.36 + 0.07 * breath),
            coreColor.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: coreR)),
    );

    // Дни: от старого (внешний рукав) к свежему (ядро).
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 1.0 : i / (n - 1);
      final v = values[i].clamp(0.0, 1.0);
      // Каскад: свежие дни «загораются» позже старых — волна из центра.
      final local = (grow * 1.3 - (1 - t) * 0.3).clamp(0.0, 1.0);
      final a = angleOf(t);
      final r = radiusOf(t);
      final p = center + Offset(math.cos(a), math.sin(a)) * r;

      final ratio = habitRatios[i].clamp(0.0, 1.0);
      final color = v <= 0
          ? dustColor.withValues(alpha: 0.22)
          : Color.lerp(taskColor, habitColor, ratio)!;

      // Размер: пустой день — точка, плотный — крупная звезда. Ближе к
      // ядру дни чуть крупнее: перспектива «вглубь».
      final base = 2.4 + 6.8 * v + 1.6 * t;
      final dotR = base * local * (0.92 + 0.08 * breath);

      if (v > 0) {
        // Свечение вокруг звезды — тем сильнее, чем плотнее день.
        canvas.drawCircle(
          p,
          dotR * (2.2 + 1.4 * v),
          Paint()
            ..isAntiAlias = true
            ..shader = RadialGradient(
              colors: [
                color.withValues(alpha: (0.40 + 0.30 * v) * local),
                color.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(center: p, radius: dotR * (2.2 + 1.4 * v)),
            ),
        );
      }
      canvas.drawCircle(
        p,
        dotR,
        Paint()
          ..isAntiAlias = true
          ..color = color.withValues(alpha: v <= 0 ? 1.0 : 0.95 * local),
      );
    }

    // Кольцо «сегодня»: тонкий контур вокруг последней (самой свежей) точки
    // в ядре — отмечает текущий день, не перегружая картинку подписью.
    if (n > 0) {
      final a = angleOf(1.0);
      final r = radiusOf(1.0);
      final p = center + Offset(math.cos(a), math.sin(a)) * r;
      final ringR = (3.4 + 6.0 * values[n - 1].clamp(0.0, 1.0)) * grow + 3.4;
      canvas.drawCircle(
        p,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..isAntiAlias = true
          ..color = coreColor.withValues(alpha: 0.85 * grow),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter old) =>
      old.grow != grow ||
      old.phase != phase ||
      old.values != values ||
      old.habitRatios != habitRatios ||
      old.habitColor != habitColor ||
      old.taskColor != taskColor;
}
