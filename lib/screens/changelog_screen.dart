import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../l10n/translations.dart';
import '../models/changelog_entry.dart';
import '../services/update_service.dart';
import '../utils/design_tokens.dart';

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
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(Spacing.md),
          children: [
            _buildHeader(theme),
            const SizedBox(height: Spacing.md),
            ...entries.map((entry) => _buildCard(theme, entry)),
          ],
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
          Text(
            Translations.t('patchNotes', context),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              fontWeight: Weights.bold,
            ),
          ),
          const SizedBox(height: Spacing.xxs),
          Text(
            Translations.t('patchTodos', context, 'Remaining to do — autosave'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onPrimaryContainer.withValues(
                alpha: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ThemeData theme, ChangelogEntry entry) {
    return Card(
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
                Text(
                  entry.version,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: Weights.bold,
                  ),
                ),
                const Spacer(),
                if (entry.date.isNotEmpty)
                  Text(
                    entry.date,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            ...entry.changes.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(c)),
                  ],
                ),
              ),
            ),
          ],
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
