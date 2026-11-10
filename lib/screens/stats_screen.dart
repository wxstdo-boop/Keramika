import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;

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

  /// Скролл статистики: деформация растяжения читает его позицию каждый кадр
  /// (см. [_StretchScroll]) — так возврат в покой не зависит от того, какие
  /// уведомления успела прислать физика.
  final _scrollCtrl = ScrollController();

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
    _scrollCtrl.dispose();
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

    // Физика — как на ОСТАЛЬНЫХ экранах (привычки, задачи, будильники):
    // упругий BouncingScrollPhysics. AlwaysScrollable поверх — чтобы
    // pull-to-refresh работал и на коротком контенте. Сверх этого —
    // [_StretchScroll]: при протяжке края контент физически ТЯНЕТСЯ
    // (сверху и снизу), как блок разделов на главном экране.
    final bodyContent = _StretchScroll(
      controller: _scrollCtrl,
      child: SingleChildScrollView(
      controller: _scrollCtrl,
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
  // Ещё тоньше: 0.35 — кант почти волосяной, карточки не выглядят
  // «окантованными».
  const thickness = 0.35;
  final cs = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius + thickness),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          accent.withValues(alpha: dark ? 0.30 : 0.20),
          accent.withValues(alpha: dark ? 0.05 : 0.04),
          cs.tertiary.withValues(alpha: dark ? 0.20 : 0.12),
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
    // Глитч — ЧИСТАЯ ПЕРЕРИСОВКА: видимый текст рисует статичный [Text], а
    // цветные «двойники»-тени — painter, слушающий [ctrl] через `repaint`.
    // Дерево при этом НЕ перестраивается каждый кадр. Это не только про
    // 60 fps: перестройка анимированного абзаца помечает слой скролла
    // «грязным» на каждом кадре, и вертикальный драг перестаёт двигать
    // список — статистика «не листалась» (проверено регрессом
    // stats_stretch_test).
    final base = style ?? const TextStyle();
    return RepaintBoundary(
      child: CustomPaint(
        painter: _GlitchShadowPainter(
          text: text,
          style: base,
          ctrl: ctrl,
          textDirection: Directionality.of(context),
        ),
        child: Text(text, style: base),
      ),
    );
  }
}

/// Тени-«глитч» под текстом: два полупрозрачных цветных двойника, амплитуда
/// которых пульсирует волной от [ctrl]. Рисуются ПОД текстом (background
/// painter), поэтому сам текст остаётся чётким.
class _GlitchShadowPainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final Animation<double> ctrl;
  final TextDirection textDirection;

  _GlitchShadowPainter({
    required this.text,
    required this.style,
    required this.ctrl,
    required this.textDirection,
  }) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) {
    final t = ctrl.value;
    // Плавная волна «глитча»: лёгкая пульсация цветовых каналов.
    final wave = (math.sin(t * 2 * math.pi) + 1) / 2;
    // Текст стоит на месте (никакого сдвига/размытия), «глитч» — только
    // расщепление цветных теней, пульсирующее по амплитуде. Холодный/тёплый
    // — как RGB-расщепление.
    _drawShadowCopy(
      canvas,
      size,
      const Color(0xFFFF3B5C).withValues(alpha: 0.08 + wave * 0.14),
      const Offset(1.1, 0),
    );
    _drawShadowCopy(
      canvas,
      size,
      const Color(0xFF33D1FF).withValues(alpha: 0.07 + wave * 0.12),
      const Offset(-1.1, 0),
    );
  }

  /// Рисует одну цветную тень: прозрачный текст с цветной размытой тенью —
  /// ровно то, что давало прежнее `shadows` у [Text], но без пересборки.
  void _drawShadowCopy(Canvas canvas, Size size, Color color, Offset offset) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: Colors.transparent,
          shadows: [Shadow(color: color, blurRadius: 1.5, offset: offset)],
        ),
      ),
      textDirection: textDirection,
      maxLines: 1,
    )..layout(maxWidth: size.width);
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _GlitchShadowPainter old) =>
      old.text != text || old.style != style || old.textDirection != textDirection;
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
            // Интуитивный столбчатый график за 30 дней: высота столбика —
            // активность дня, а его две части — привычки (снизу) и задачи
            // (сверху). Так видно и «сколько всего», и «из чего сложилось»,
            // без легенды-головоломки: что закрашено — то и сделано.
            // Плавный рост при входе, подписи дат по краям, отметка
            // «лучшего дня» и «сегодня».
            SizedBox(
              height: 190,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, grow, _) => _DaysBarChart(
                  days: days,
                  maxV: maxV,
                  grow: grow,
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



/// Столбчатый график «последние 30 дней»: один столбик на день, высота —
/// суммарная активность (привычки + задачи), стек — привычки снизу, задачи
/// сверху. Подписи дат по краям, «сегодня» подсвечено, а «лучший день»
/// отмечен меткой сверху. Никакой спирали: график читается за секунду.
class _DaysBarChart extends StatelessWidget {
  final List<DayCompletion> days;
  final int maxV;
  final double grow;
  final ThemeData theme;
  final Color habitColor;
  final Color taskColor;

  const _DaysBarChart({
    required this.days,
    required this.maxV,
    required this.grow,
    required this.theme,
    required this.habitColor,
    required this.taskColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DaysBarPainter(
          days: days,
          maxV: maxV,
          grow: grow,
          habitColor: habitColor,
          taskColor: taskColor,
          axisColor: cs.onSurfaceVariant.withValues(alpha: 0.30),
          gridColor: cs.onSurfaceVariant.withValues(alpha: 0.14),
          labelColor: cs.onSurfaceVariant,
          todayColor: cs.primary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Художник столбчатого графика. Столбик дня стоит на общей базовой линии,
/// его высота пропорциональна активности дня относительно [maxV]. Стек:
/// нижний сегмент — привычки ([habitColor]), верхний — задачи ([taskColor]).
/// Три тонкие горизонтальные линии задают шкалу, а пунктирная линия на
/// уровне [maxV] показывает «лучший день».
class _DaysBarPainter extends CustomPainter {
  final List<DayCompletion> days;
  final int maxV;
  final double grow;
  final Color habitColor;
  final Color taskColor;
  final Color axisColor;
  final Color gridColor;
  final Color labelColor;
  final Color todayColor;

  _DaysBarPainter({
    required this.days,
    required this.maxV,
    required this.grow,
    required this.habitColor,
    required this.taskColor,
    required this.axisColor,
    required this.gridColor,
    required this.labelColor,
    required this.todayColor,
  });

  static const double _topPad = 20; // место под метку «лучший день»
  static const double _bottomPad = 18; // место под подписи дат

  @override
  void paint(Canvas canvas, Size size) {
    final n = days.length;
    if (n == 0 || size.width <= 0 || size.height <= 0) return;

    final chartTop = _topPad;
    final chartBottom = size.height - _bottomPad;
    final chartH = chartBottom - chartTop;
    if (chartH <= 4) return;

    final maxValue = math.max(1, maxV);

    // Горизонтальные линии шкалы: четверть, половина, три четверти — без
    // подписей-цифр, чтобы не шуметь; ориентир даёт сама высота.
    final gridPaint = Paint()
      ..strokeWidth = 1
      ..isAntiAlias = true
      ..color = gridColor;
    for (var g = 1; g <= 3; g++) {
      final y = chartBottom - chartH * (g / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Базовая линия — чуть плотнее сетки.
    canvas.drawLine(
      Offset(0, chartBottom),
      Offset(size.width, chartBottom),
      Paint()
        ..strokeWidth = 1.2
        ..isAntiAlias = true
        ..color = axisColor,
    );

    // Геометрия столбиков: ширина доли минус небольшой зазор.
    final slot = size.width / n;
    final barW = math.max(1.5, slot * 0.62);
    final radius = Radius.circular(math.min(barW / 2, 2.4));

    var bestIndex = -1;
    var bestTotal = 0;
    for (var i = 0; i < n; i++) {
      final t = days[i].habits + days[i].tasks;
      if (t > bestTotal) {
        bestTotal = t;
        bestIndex = i;
      }
    }

    for (var i = 0; i < n; i++) {
      final d = days[i];
      final total = d.habits + d.tasks;
      final cx = slot * (i + 0.5);
      if (total <= 0) {
        // Пустой день — маленькая точка у базовой линии, а не пустое
        // место: видно, что день был, но активности нет.
        canvas.drawCircle(
          Offset(cx, chartBottom - 1.6),
          1.6,
          Paint()..color = axisColor.withValues(alpha: 0.55),
        );
        continue;
      }
      final full = chartH * (total / maxValue);
      final h = (full * grow).clamp(0.0, chartH);
      // Доли привычек и задач в столбике.
      final habitH = h * (d.habits / total);
      final taskH = h - habitH;
      final left = cx - barW / 2;
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(left, chartBottom - h, barW, h),
        topLeft: radius,
        topRight: radius,
      );

      // Стек: снизу привычки, сверху задачи.
      canvas.save();
      canvas.clipRRect(rect);
      canvas.drawRect(
        Rect.fromLTWH(left, chartBottom - habitH, barW, habitH),
        Paint()..color = habitColor,
      );
      canvas.drawRect(
        Rect.fromLTWH(left, chartBottom - h, barW, taskH),
        Paint()..color = taskColor,
      );
      canvas.restore();
      // Тонкий контур — столбики не «слипаются» на тёмной теме.
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..isAntiAlias = true
          ..color = todayColor.withValues(alpha: 0.18),
      );

      // «Сегодня» — последний столбик: подписываем дату акцентом.
      final isToday = i == n - 1;
      if (bestIndex == i && grow > 0.85) {
        // Метка «лучший день»: маленькая звёздочка над столбиком.
        _drawStar(
          canvas,
          Offset(cx, chartBottom - h - 8),
          4.2,
          todayColor.withValues(alpha: 0.9 * grow),
        );
      }
      if (isToday) {
        canvas.drawCircle(
          Offset(cx, chartBottom + 6),
          2.0,
          Paint()..color = todayColor,
        );
      }
    }

    // Подписи дат по краям: первый и последний день диапазона. Короткие
    // числа («1», «30») — без нагромождения.
    _label(canvas, size, days.first.date, chartBottom + _bottomPad - 4, TextAlign.left);
    _label(canvas, size, days.last.date, chartBottom + _bottomPad - 4, TextAlign.right);
  }

  void _label(Canvas canvas, Size size, String date, double y, TextAlign align) {
    // date приходит в формате 'yyyy-MM-dd' — берём день месяца.
    final day = date.length >= 10 ? date.substring(8, 10) : date;
    final tp = TextPainter(
      text: TextSpan(
        text: day.replaceFirst(RegExp(r'^0'), ''),
        style: TextStyle(color: labelColor, fontSize: 10, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final x = align == TextAlign.left ? 0.0 : size.width - tp.width;
    tp.paint(canvas, Offset(x, y - tp.height));
  }

  void _drawStar(Canvas canvas, Offset c, double r, Color color) {
    final path = Path();
    for (var k = 0; k < 10; k++) {
      final rad = k.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + k * math.pi / 5;
      final p = c + Offset(math.cos(a), math.sin(a)) * rad;
      if (k == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(covariant _DaysBarPainter old) =>
      old.grow != grow ||
      old.maxV != maxV ||
      old.days != days ||
      old.habitColor != habitColor ||
      old.taskColor != taskColor;
}


/// «Растяжение» края скролла: при протяжке за верхнюю/нижнюю границу
/// содержимое мягко тянется вдоль оси (и слегка сжимается поперёк), а на
/// отпускании так же плавно возвращается.
///
/// Почему не [OverscrollNotification]: с [BouncingScrollPhysics] пиксели
/// уходят за границу свободно, и граничное условие возвращает ноль —
/// уведомления о перепротяжке не приходят вовсе. Поэтому деформацию берём
/// прямо из позиции контроллера, опрашивая её тикером, пока край оттянут:
/// тогда и пружина возврата сама тянет наш масштаб обратно, без отдельной
/// анимации отпускания и без зависимости от чужих уведомлений.
///
/// Деформация — это [Transform] (не влияет на layout), поэтому размеры списка
/// и pull-to-refresh не задеты.
class _StretchScroll extends StatefulWidget {
  final ScrollController controller;
  final Widget child;

  const _StretchScroll({required this.controller, required this.child});

  @override
  State<_StretchScroll> createState() => _StretchScrollState();
}

class _StretchScrollState extends State<_StretchScroll>
    with SingleTickerProviderStateMixin {
  /// Величина протяжки 0..1 (0 — покой, 1 — предел деформации).
  final ValueNotifier<double> _pull = ValueNotifier<double>(0);

  late final Ticker _ticker = createTicker(_sample);

  /// Тянут за верхний край (иначе — за нижний): от этого зависит, из какого
  /// угла контент «растягивается».
  bool _atTop = true;

  /// Кадров подряд в границах: двух достаточно, чтобы считать движение
  /// завершённым и остановить тикер (в простое не тратим кадры).
  int _calm = 0;

  /// Ход протяжки, на котором деформация достигает предела, px.
  static const double _fullPull = 220;

  @override
  void dispose() {
    _ticker.dispose();
    _pull.dispose();
    super.dispose();
  }

  /// Один замер позиции: переносим «выход за границу» в деформацию.
  void _sample(Duration _) {
    final pos = widget.controller.hasClients
        ? widget.controller.position
        : null;
    if (pos == null) {
      _ticker.stop();
      return;
    }
    final double beyondTop = pos.minScrollExtent - pos.pixels;
    final double beyondBottom = pos.pixels - pos.maxScrollExtent;
    final double beyond = math.max(beyondTop, beyondBottom);
    _atTop = beyondTop >= beyondBottom;
    _pull.value = (beyond / _fullPull).clamp(0.0, 1.0);
    if (beyond <= 0.5) {
      if (++_calm >= 2) {
        _pull.value = 0;
        _ticker.stop();
      }
    } else {
      _calm = 0;
    }
  }

  bool _onNotification(ScrollNotification n) {
    if (MotionPrefs.shouldReduceMotion) return false;
    if (n is ScrollStartNotification ||
        n is ScrollUpdateNotification ||
        n is ScrollEndNotification) {
      _calm = 0;
      if (!_ticker.isActive) _ticker.start();
      // Замер сразу, не дожидаясь следующего кадра: тикер успевает только
      // к следующему фрейму, а деформация должна быть видна уже на этом.
      _sample(Duration.zero);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: ValueListenableBuilder<double>(
        valueListenable: _pull,
        builder: (context, raw, child) {
          final p = Curves.easeOutCubic.transform(raw);
          // Transform присутствует ВСЕГДА (в покое — единичный): если
          // убирать/вставлять его на ходу, дерево под пальцем меняется, и
          // жест обрывается. Поэтому «покой» — это масштаб 1, а не
          // отсутствие виджета.
          return Transform.scale(
            // Ключ — точка опоры для тестов растяжения: по нему находят
            // именно эту деформацию, не путая с прочими Transform на экране.
            key: const ValueKey('stats_stretch'),
            // Растяжка вдоль оси протяжки + лёгкое сжатие поперёк —
            // «резина», а не просто сдвиг.
            scaleX: 1 - 0.018 * p,
            scaleY: 1 + 0.030 * p,
            alignment: _atTop ? Alignment.topCenter : Alignment.bottomCenter,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
