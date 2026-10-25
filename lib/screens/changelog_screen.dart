import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;
import '../l10n/translations.dart';

class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = <_ChangelogEntry>[
      _ChangelogEntry(
        version: '1.6.72',
        date: '2026-10-20',
        title: Translations.t('changelogTitle', context, "What's new"),
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
      _ChangelogEntry(
        version: '1.6.71',
        date: '2026-10-20',
        title: Translations.t('changelogTitle', context, "What's new"),
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
      _ChangelogEntry(
        version: '1.6.70',
        date: '2026-10-19',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeCIUpdate',
            context,
            'Build pipeline updated: newer GitHub Actions and a fixed lint job',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.69',
        date: '2026-10-19',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeCategoryDrag',
            context,
            'Categories can be dragged to reorder them in the task editor',
          ),
          Translations.t(
            'changeCategoryReorder',
            context,
            'Category order changes smoothly and is remembered',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.68',
        date: '2026-10-19',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeRemindAllCircle',
            context,
            '"Remind all" now matches the tone of the buttons next to it',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.67',
        date: '2026-10-19',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changePinSmooth',
            context,
            'The lock screen and habit ring animate smoothly',
          ),
          Translations.t(
            'changeFlockEdges',
            context,
            'The flock of birds fades in and out instead of being cut off',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.66',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeForgeTokenSave',
            context,
            'Forge: saving a GitHub token now works — the button comes back to life',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.65',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeForgeAgent',
            context,
            'Forge is a real chat agent: it answers questions and edits the code',
          ),
          Translations.t(
            'changeForgePr',
            context,
            'Agent changes go to a branch and open a pull request for review',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.64',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeForgeFree',
            context,
            'Forge works out of the box on built-in free providers — no API key needed',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.63',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeForgeSection',
            context,
            'Developer Corner gained the Forge section for repository edits',
          ),
          Translations.t(
            'changeForgeEntry',
            context,
            'Forge is reachable from Settings, in three languages',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.62',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeCIMemory',
            context,
            'Release builds no longer fail on the runner for lack of Gradle memory',
          ),
          Translations.t(
            'changeCISigning',
            context,
            'Signing secrets are checked upfront, with a clear error instead of a crash',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.6.61',
        date: '2026-10-18',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeAutoUpdateName',
            context,
            'Auto-update compares versions by name, so it works with split APKs',
          ),
          Translations.t(
            'changeHamster',
            context,
            'Hamster: statistics, search and a faster PIN screen',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.3-release',
        date: '2026-08-13',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeMutilatedTheme',
            context,
            'New theme MUTILATED — light bloody red with faint splatter overlay',
          ),
          Translations.t(
            'changeElegantEgg',
            context,
            "Hold the MUTILATED chip for 10 seconds to reveal 'Are you elegant?' easter egg",
          ),
          Translations.t(
            'changeMealConfirm',
            context,
            'Confirmation dialog before deleting a meal entry',
          ),
          Translations.t(
            'changeChatScroll',
            context,
            'AI chat now sticks to the last message while streaming and on open',
          ),
          Translations.t(
            'changeLangSmooth',
            context,
            'Smoother language switching transition',
          ),
          Translations.t(
            'changeEmDash',
            context,
            'All visible dashes are now long em-dashes across the app',
          ),
          Translations.t(
            'changeSplashFix',
            context,
            'Splash avatar no longer flickers on cold start',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '1.2',
        date: '2026-08-09',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeAdaGuide',
            context,
            'AI guide Ada — a mini chat that creates habits, tasks, alarms, reality checks and meals by itself',
          ),
          Translations.t(
            'changeSmoothAnim',
            context,
            'Smooth animations everywhere: section transitions, settings, cards, toggles',
          ),
          Translations.t(
            'changeStreakFix',
            context,
            'Fixed streaks and habit check-offs',
          ),
          Translations.t(
            'changePinBlur',
            context,
            'PIN lock now blurs the app in recent apps',
          ),
          Translations.t(
            'changeNotifIcon',
            context,
            'Notification icon — signature K badge',
          ),
          Translations.t(
            'changeAlarmFix',
            context,
            'Alarms: sounds restored, time picker works with drag',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '0.1.9',
        date: '2026-08-08',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeSwipeUp',
            context,
            'Swipe up on home screen to refresh screen',
          ),
          Translations.t(
            'changePerfectionismTitle',
            context,
            'Perfectionism plaques now use proper title case',
          ),
          Translations.t(
            'changeHabitLayout',
            context,
            'Habit cards redesigned: completion checkbox on top, habit type icon below',
          ),
          Translations.t(
            'changeHabitFit',
            context,
            'Habit rows now fit long titles, notes and day labels nicely',
          ),
          Translations.t(
            'changeCategoryLimit',
            context,
            'Category name limit reduced to 15 characters',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '0.1.8',
        date: '2026-07-23',
        title: Translations.t('changelogTitle', context, "What's new"),
        changes: [
          Translations.t(
            'changeGrokTheme',
            context,
            'Grok theme updated to monochrome light/dark',
          ),
          Translations.t(
            'changeMealCards',
            context,
            'Meal cards now have daily randomized colors and icons',
          ),
          Translations.t(
            'changeDropdowns',
            context,
            'Dropdown menus rounded in settings and tasks',
          ),
          Translations.t(
            'changeSnackbar',
            context,
            'Snackbar animations improved',
          ),
          Translations.t(
            'changeSwipeSnap',
            context,
            'Swipe between sections with smooth snap',
          ),
          Translations.t(
            'changeCornerSwipe',
            context,
            'Top corners rounded dynamically on swipe',
          ),
          Translations.t(
            'changeRoundedTiles',
            context,
            'Settings tiles rounded',
          ),
          Translations.t(
            'changeAuthorLinks',
            context,
            'Added links to author apps: Ataraxy and MSoc',
          ),
        ],
      ),
      _ChangelogEntry(
        version: '0.1.7',
        date: '2026-07-22',
        title: Translations.t('changelogTitle', context, 'Previous update'),
        changes: [
          Translations.t(
            'changePrev1',
            context,
            'Habits, tasks and alarms improvements',
          ),
          Translations.t('changePrev2', context, 'PIN lock added'),
          Translations.t('changePrev3', context, 'Export/import data'),
          Translations.t(
            'changePrev4',
            context,
            'Nutrition module with 7-day history',
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('patchNotes', context)),
        // Задизайненный «Назад» (тултип) — единый стиль со всеми экранами.
        leading: const BackButtonTooltip(),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t('patchNotes', context),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Translations.t(
                    'patchTodos',
                    context,
                    'Remaining to do — autosave',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...entries.map((entry) {
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.version,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          entry.date,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      entry.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...entry.changes.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
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
          }),
        ],
      ),
    );
  }
}

class _ChangelogEntry {
  final String version;
  final String date;
  final String title;
  final List<String> changes;

  const _ChangelogEntry({
    required this.version,
    required this.date,
    required this.title,
    required this.changes,
  });
}
