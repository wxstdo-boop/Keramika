import 'package:flutter/material.dart';
import '../services/reality_check_service.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../l10n/translations.dart';
// import '../utils/smooth_refresh.dart'; (removed, no longer used)

class RealityCheckStatsScreen extends StatefulWidget {
  const RealityCheckStatsScreen({super.key});

  @override
  State<RealityCheckStatsScreen> createState() =>
      _RealityCheckStatsScreenState();
}

class _RealityCheckStatsScreenState extends State<RealityCheckStatsScreen> {
  final _rcSvc = RealityCheckService();
  final _habitSvc = HabitService();
  final _taskSvc = TaskService();

  @override
  void initState() {
    super.initState();
    _rcSvc.load();
    _habitSvc.load();
    _taskSvc.load();
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

    final bodyContent = SingleChildScrollView(
      // Как на остальных экранах: свайп вверх/вниз работает всегда,
      // даже когда контента мало (иначе жест «не ловился» и экран
      // казался залипшим).
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildOverallSummary(context, theme, overallPct),
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
          ),
          const SizedBox(height: 16),
          _buildStatCard(
            context,
            theme,
            Icons.checklist_outlined,
            Translations.tasksOf(context),
            tasksDone,
            tasksTotal,
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
                transitionBuilder: (child, animation) {
                  final t = Curves.easeOutCubic.transform(animation.value);
                  return FadeTransition(
                    opacity: animation,
                    child: Transform.translate(
                      offset: Offset(0, 12 * (1 - t)),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  '${(pct * 100).toInt()}%',
                  key: ValueKey('overall_${(pct * 100).toInt()}'),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
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
    int total,
  ) {
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
                      final t = Curves.easeOutCubic.transform(animation.value);
                      return FadeTransition(
                        opacity: animation,
                        child: Transform.translate(
                          offset: Offset(0, 12 * (1 - t)),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      '$done / $total',
                      key: ValueKey('count_$done/$total'),
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
