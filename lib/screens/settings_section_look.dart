part of 'settings_screen.dart';

/// Внешний вид: темы, язык, шрифт, «О приложении» и ссылки.
extension _SettingsSectionLook on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsLookSection(
    BuildContext context,
    AgyshaAppState appState,
    ThemeData theme,
  ) => <Widget>[
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.aboutOf(context),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            // «Agysha FOSS» — приписку FOSS выделяем розовым,
            // как она была на сплэше.
            Text.rich(
              TextSpan(
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
                children: [
                  const TextSpan(text: 'Agysha '),
                  const TextSpan(
                    text: 'FOSS',
                    style: TextStyle(
                      color: Color(0xFFF06292),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Номер версии — пасхалка: держим палец → конфетти в цветах
            // темы + тост. GestureDetector без ripple, чтобы не портить
            // «информационный» вид строки.
            // Версия (долгое нажатие — пасхалка) и рядом полупрозрачная
            // таблетка «Проверить обновления».
            Row(
              children: [
                GestureDetector(
                  onLongPress: _onVersionLongPress,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      // Версия — из установленного APK (Android) или из
                      // pubspec (web/десктоп). Раньше здесь стояла
                      // захардкоженная «1.3», и приложение на 1.6.72
                      // показывало пользователю старую версию.
                      'v${AppVersion.current}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 16),
            // Плашки карточки «О приложении» (Заметки о патче, GitHub,
            // GitFlic, GitLab) отдают нажатие ТАК ЖЕ плавно, как значки
            // шапки: мягкое вдавливание при зажатии и плавный возврат,
            // а не мгновенный InkWell-ripple.
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 220),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                onTap: _openChangelog,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          Translations.t('patchNotes', context),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      // В F-Droid-сборке самообновление выключено (магазин
                      // переподписывает APK своим ключом) — таблетку не показываем.
                      if (kSelfUpdateEnabled) const UpdatePill(),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 220),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                onTap: () => _openGitHub(),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.code,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GitHub',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      // Бейдж «Recommended» — в том же виде, что таблетка
                      // обновления рядом: тонкое градиентное кольцо и
                      // полупрозрачная подложка. Плоская кайма «разливалась»
                      // и выбивалась из ряда.
                      Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.primary.withValues(
                                alpha: theme.brightness == Brightness.dark
                                    ? 0.60
                                    : 0.45,
                              ),
                              theme.colorScheme.primary.withValues(
                                alpha: theme.brightness == Brightness.dark
                                    ? 0.12
                                    : 0.10,
                              ),
                              theme.colorScheme.tertiary.withValues(
                                alpha: theme.brightness == Brightness.dark
                                    ? 0.48
                                    : 0.30,
                              ),
                            ],
                            stops: const [0, 0.55, 1],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer
                                .withValues(
                                  alpha: theme.brightness == Brightness.dark
                                      ? 0.72
                                      : 0.78,
                                ),
                            borderRadius: BorderRadius.circular(998),
                          ),
                          child: Text(
                            'Recommended',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 220),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                onTap: () => _openLink(
                  'https://gitflic.ru/project/wetcorporation/agysha',
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_tree,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GitFlic',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 220),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                onTap: _openGitLab,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.merge,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GitLab',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person_outline,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.t('aboutAuthorTitle', context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _CtaButton(
              label: Translations.t('visitellaName', context, 'Visitella'),
              icon: Icons.rocket_launch_outlined,
              // Оригинальный вид Visitella: тёмный градиент + чёрное свечение.
              gradient: const [
                Color(0xFF4A4D54),
                Color(0xFF232428),
                Color(0xFF101013),
              ],
              glow: Colors.black,
              onTap: () => _openLink('https://mutilated.pages.dev/#top'),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.t(
                'visitellaDesc',
                context,
                'Projects, games, news',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.volunteer_activism_outlined,
                  color: Color(0xFFE91E63),
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    Translations.t(
                      'supportAuthorTitle',
                      context,
                      'Support the author',
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              Translations.t(
                'supportAuthorBody',
                context,
                'If this app helps you, you can thank the developer with a small donation.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            // Кнопка «Поддержать»: открывает снизу окно с выбором способа
            // оплаты — CloudTips, Boosty (и др.). Внутри окна — крупные
            // градиентные кнопки, каждая открывает свою страницу.
            _CtaButton(
              label: Translations.t('support', context, 'Support'),
              icon: Icons.favorite,
              // «Кровавый» вид: топ-стоп тёплого ализарина, середина —
              // насыщенный багровый, низ — почти вишнёвый, как Запекшаяся
              // кровь. Свечение в тон середины: кнопка горит изнутри,
              // а не светится розовым обертоном.
              gradient: const [
                Color(0xFFFF5A66),
                Color(0xFFD90D28),
                Color(0xFF7E0B1B),
              ],
              glow: const Color(0xFFC8102E),
              onTap: _showSupportSheet,
            ),
          ],
        ),
      ),
    ),
  ];
}
