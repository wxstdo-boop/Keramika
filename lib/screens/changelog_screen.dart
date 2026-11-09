import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../widgets/stagger_in.dart';
import '../l10n/translations.dart';
import '../models/changelog_entry.dart';
import '../services/update_service.dart';
import '../utils/design_tokens.dart';

/// Набор значков для пунктов «Что нового». Значок у каждого пункта СВОЙ и
/// смещается от карточки к карточке (см. [ChangelogScreen._buildCard]):
/// снежинка остаётся одним из многих, а не лицом каждого релиза.
const List<IconData> _changeIcons = [
  Icons.ac_unit_rounded,
  Icons.auto_awesome_rounded,
  Icons.bolt_rounded,
  Icons.palette_rounded,
  Icons.rocket_launch_rounded,
  Icons.tune_rounded,
  Icons.brush_rounded,
  Icons.insights_rounded,
  Icons.speed_rounded,
  Icons.emoji_objects_rounded,
  Icons.architecture_rounded,
  Icons.water_drop_rounded,
  Icons.eco_rounded,
  Icons.sailing_rounded,
  Icons.nightlight_round,
  Icons.auto_fix_high_rounded,
];

/// Фирменный «кровавый» акцент — тот же, что у свежего релиза и подписи.
const Color _heartRed = Color(0xFFE53935);

/// Экран «Что нового».
///
/// Список берётся из живых GitHub-релизов ([UpdateService.fetchChangelog]),
/// поэтому он не отстаёт от версии приложения. Пока идёт загрузка — тонкая
/// полоса прогресса, а если сети нет — показывается встроенный список
/// последних значимых версий, чтобы экран никогда не был пустым.
class ChangelogScreen extends StatefulWidget {
  const ChangelogScreen({super.key});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  List<ChangelogEntry>? _entries;
  bool _loading = true;

  /// Список пришёл из сети (true) или это встроенная подстраховка (false).
  bool _live = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (force && mounted) setState(() => _loading = true);
    final fetched = await UpdateService.instance.fetchChangelog(force: force);
    if (!mounted) return;
    setState(() {
      _entries = fetched;
      _live = fetched != null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Живой список; если сеть недоступна — встроенный запасной.
    final entries = _entries ?? _fallbackEntries(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('patchNotes', context)),
        // Задизайненный «Назад» (тултип) — единый стиль со всеми экранами.
        leading: const BackButtonTooltip(),
        centerTitle: true,
        actions: [
          // Когда показана подстраховка (сети не было), даём обновить вручную:
          // иначе экран выглядел бы тупиком до перезахода.
          if (!_loading && !_live)
            IconButton(
              tooltip: Translations.t('retry', context),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _load(force: true),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        // Смена «скелет → список» кросс-фейдом, а не кадром: подмена контента
        // читалась как мигание сразу после открытия экрана.
        child: AnimatedSwitcher(
          duration: Motion.normal,
          switchInCurve: Motion.standard,
          switchOutCurve: Curves.easeInCubic,
          child: _loading
              ? const _ChangelogSkeleton(key: ValueKey('changelog_loading'))
              // ЛЕНИВЫЙ список: живых релизов бывает под сотню, и построение
              // всех карточек одним кадром (ListView(children: […])) держало
              // первый кадр экрана и «съедало» память. ListView.builder строит
              // только видимое + запас, поэтому открытие остаётся мгновенным.
              : ListView.builder(
                  // Ключ зависит от содержимого: когда список обновляется
                  // (refresh или новый релиз), AnimatedSwitcher кросс-фейдит
                  // старый и новый списки, а не подменяет их одним кадром.
                  key: ValueKey(
                    'changelog_list_${entries.length}_'
                    '${entries.isEmpty ? '' : entries.first.version}',
                  ),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(Spacing.md),
                  // Индекс 0 — плашка-заголовок, дальше — карточки релизов.
                  itemCount: entries.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(theme),
                          const SizedBox(height: Spacing.md),
                        ],
                      );
                    }
                    final card = i - 1;
                    // Карточки входят каскадом: длинный список проявляется
                    // мягко, а не возникает одним кадром.
                    return StaggerIn(
                      index: card,
                      child: _buildCard(
                        theme,
                        entries[card],
                        cardIndex: card,
                        isLatest: card == 0,
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок плашки — сразу «Как развивается приложение» (без
          // отдельной строки «Список изменений»), а под ним мелким текстом
          // план работ. В конце заголовка — красное сердечко: приложение
          // растёт «с любовью», тем же тёплым акцентом, что и свежий релиз.
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: Translations.t(
                    'patchDeveloping',
                    context,
                    'How the app is developing',
                  ),
                ),
                const TextSpan(text: '  '),
                const TextSpan(
                  text: '\u2764',
                  style: TextStyle(color: _heartRed),
                ),
              ],
            ),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: Weights.bold,
            ),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            Translations.t(
              'patchRoadmap',
              context,
              'Minor tweaks, PR in 2027',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(
                alpha: 0.72,
              ),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  /// Карточка одного релиза.
  ///
  /// [cardIndex] — порядковый номер карточки в списке: он сдвигает набор
  /// значков, поэтому у каждого релиза свой первый значок, а не один и тот же
  /// на всех (иначе снежинка снова стала бы «лицом» всего списка).
  ///
  /// [isLatest] — самая свежая версия: её номер мягко подчёркивается
  /// полупрозрачной красной полосой (плавно «прочерчивается» при появлении),
  /// чтобы свежий выпуск читался с первого взгляда.
  Widget _buildCard(
    ThemeData theme,
    ChangelogEntry entry, {
    int cardIndex = 0,
    bool isLatest = false,
  }) {
    // Дата и точное время — через запятую: у авторелизов одной датой
    // выходит по нескольку выпусков подряд, и по одному дню их не различить.
    final stamp = [
      entry.date,
      if (entry.time.isNotEmpty) entry.time,
    ].where((s) => s.isNotEmpty).join(', ');

    return PressScale(
      // «Отдача» карточки при зажатии: медленное и очень плавное уменьшение,
      // маленькое по величине — карточка мягко «уходит» под палец и так же
      // неспешно возвращается. Быстрый щелчок здесь читался бы дёшево.
      pressedScale: 0.975,
      duration: const Duration(milliseconds: 480),
      releaseDuration: const Duration(milliseconds: 560),
      curve: Curves.easeOutCubic,
      child: Card(
        margin: const EdgeInsets.only(bottom: Spacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isLatest)
                    _LatestVersion(version: entry.version)
                  else
                    Text(
                      entry.version,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: Weights.bold,
                      ),
                    ),
                  const Spacer(),
                  if (stamp.isNotEmpty)
                    Text(
                      stamp,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: Spacing.sm),
              for (var j = 0; j < entry.changes.length; j++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Значок у каждого пункта СВОЙ: набор смещён на номер
                      // карточки, поэтому у каждого релиза свой первый значок
                      // и список не выглядит частоколом одинаковых иконок.
                      Icon(
                        _changeIcons[(j + cardIndex) % _changeIcons.length],
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      // Текст заметки — курсивом: пункты читаются как живая
                      // заметка автора, а не как протокол официального отчёта.
                      Expanded(
                        child: Text(
                          entry.changes[j],
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Встроенный запасной список: последние значимые версии на случай, когда
  /// релизы с GitHub недоступны (нет сети, лимит API). Держим коротким —
  /// это именно подстраховка, а не второй источник правды.
  List<ChangelogEntry> _fallbackEntries(BuildContext context) => [
    ChangelogEntry(
      version: '1.6.72',
      date: '2026-10-20',
      changes: [
        Translations.t(
          'changeTaskShelvesContrast',
          context,
          'Task shelves: headings are now readable in both light and dark themes',
        ),
        Translations.t(
          'changeLintCleanup',
          context,
          'Internal cleanup: test helpers no longer use underscore-prefixed names',
        ),
      ],
    ),
    ChangelogEntry(
      version: '1.6.71',
      date: '2026-10-20',
      changes: [
        Translations.t(
          'changeTaskShelves',
          context,
          'Tasks are split into "Active" and "Completed" shelves',
        ),
        Translations.t(
          'changeTaskMarkFinal',
          context,
          'Completing a task is final — it moves to the completed shelf',
        ),
      ],
    ),
    ChangelogEntry(
      version: '1.6.70',
      date: '2026-10-19',
      changes: [
        Translations.t(
          'changeCIUpdate',
          context,
          'Build pipeline updated: newer GitHub Actions and a fixed lint job',
        ),
      ],
    ),
  ];
}

/// Номер САМОЙ СВЕЖЕЙ версии с мягким подчёркиванием.
///
/// Красная полупрозрачная полоса «прочерчивается» слева направо при
/// появлении карточки (scaleX 0→1, easeOutCubic) и остаётся под номером.
/// Рисуется ПОД текстом (Stack + Positioned), поэтому не сдвигает строку
/// и не влияет на соседнюю дату.
class _LatestVersion extends StatefulWidget {
  final String version;

  const _LatestVersion({required this.version});

  @override
  State<_LatestVersion> createState() => _LatestVersionState();
}

class _LatestVersionState extends State<_LatestVersion>
    with SingleTickerProviderStateMixin {
  /// Тот же «кровавый», что у подписи LARAF: свежий релиз помечен тем же
  /// фирменным акцентом, что и сплэш.
  static const Color _blood = Color(0xFFB3121F);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: Weights.bold,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(widget.version, style: style),
        Positioned(
          left: 0,
          right: 0,
          bottom: -4,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              // Прочерка слева направо: к моменту окончания контроллера
              // волнистая линия нарисована целиком.
              return SizedBox(
                height: 5,
                child: CustomPaint(
                  painter: _WavyUnderlinePainter(
                    progress: Curves.easeOutCubic.transform(_ctrl.value),
                    color: _blood.withValues(alpha: 0.5),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Волнистая «извилистая» линия под номером свежей версии.
///
/// Рисуется синусом с плавно убывающей амплитудой к концу: штрих начинается
/// ровно, «дышит» волной в середине и мягко сходит на нет — красивее и
/// живее прямого подчёркивания. [progress] (0..1) задаёт, какая доля линии
/// уже прочерчена.
class _WavyUnderlinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _WavyUnderlinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.width <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final midY = size.height / 2;
    // Амплитуда волны — до 2 px: заметно «извилисто», но не мешает тексту.
    const amp = 2.0;
    final path = Path();
    final steps = (size.width / 2).ceil().clamp(2, 400);
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      if (t > progress) break;
      final x = size.width * t;
      // Волна «живёт» в середине и сходит на нет к обоим краям.
      final envelope = math.sin(math.pi * t);
      final y = midY + amp * envelope * math.sin(t * math.pi * 6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavyUnderlinePainter old) =>
      old.progress != progress || old.color != color;
}

/// Скелет загрузки: три «пустые» карточки-плашки с мягким пульсом.
///
/// Держит высоту и ритм будущего списка, поэтому подмена «скелет → список»
/// читается как догрузка, а не как мигание.
class _ChangelogSkeleton extends StatefulWidget {
  const _ChangelogSkeleton({super.key});

  @override
  State<_ChangelogSkeleton> createState() => _ChangelogSkeletonState();
}

class _ChangelogSkeletonState extends State<_ChangelogSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.ambient,
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Spacing.md),
      children: [
        for (var i = 0; i < 3; i++)
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              // Соседние плашки пульсируют вразнобой — скелет «дышит»,
              // а не мигает целиком.
              final v = (0.5 + 0.5 * math.sin(math.pi * (i / 3 + _pulse.value)))
                  .clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: Spacing.md),
                child: Container(
                  padding: const EdgeInsets.all(Spacing.lg),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(Radii.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(base.withValues(alpha: 0.07 + 0.06 * v), 96, 18),
                      const SizedBox(height: Spacing.sm),
                      _bar(base.withValues(alpha: 0.07 + 0.06 * v), 180, 12),
                      const SizedBox(height: Spacing.xs),
                      _bar(base.withValues(alpha: 0.07 + 0.06 * v), 140, 12),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _bar(Color color, double width, double height) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height / 2),
    ),
  );
}
