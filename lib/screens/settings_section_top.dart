part of 'settings_screen.dart';

/// Верх настроек: переключатель проверок реальности, предупреждение о разрешениях.
extension _SettingsSectionTop on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsTopSection(
    BuildContext context,
    AgyshaAppState appState,
    ThemeData theme,
  ) => <Widget>[
    // === Beautiful whole-section toggle for Reality Checks, top of Settings.
    // Adds or removes the 'РП' tab in Home, schedule, and notifications.
    const _RealityCheckToggleCard(),
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.themeOf(context),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            _buildThemeCarousel(context),
            // Значок Flutter ПОД каруселью тем, внутри той же карточки:
            // аккуратный фирменный акцент внизу секции.
            const SizedBox(height: 14),
            const Center(child: _FlutterBadge()),
          ],
        ),
      ),
    ),

    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Шрифт',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Шрифт выбирается так же, как язык: тап по плитке открывает
            // меню-квадрат с иконками, плавной обводкой и галочкой —
            // окно не закрывается при выборе, только тапом вне квадрата.
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showFontMenu(context, appState),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        appState.fontFamily == 'caveat'
                            ? Icons.draw_outlined
                            : Icons.font_download_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          appState.fontFamily == 'caveat'
                              ? 'Caveat'
                              : 'Обычный',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
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

    // Проверяем статус уведомлений — если false и предупреждение не скрыто, показываем карточку.
    // На web статус уведомлений не определить (всегда true), поэтому карточку
    // показываем тоже — иначе «Сбросить предупреждения» не даёт видимого результата.
    if (kIsWeb ||
        _notificationsEnabled == false ||
        _notificationsEnabled == null)
      // AnimatedSize + AnimatedSwitcher: карточка плавно исчезает
      // (fade + сворачивание высоты) при нажатии «Выдать».
      AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: _permissionWarningDismissed
              ? const SizedBox.shrink(key: ValueKey('warn_hidden'))
              : _buildPermissionWarning(context),
        ),
      ),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.languageOf(context),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            // Своё «выпадающее» меню вместо DropdownButton: появляется
            // мелким квадратом и плавно растёт в полный рост (scale +
            // fade), по бокам урезано — компактный квадрат со скруглёнными
            // углами, как просил.
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showLanguageMenu(context, appState),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.language,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _languageLabel(context, appState.languageCode),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Icon(
                        Icons.expand_more,
                        color: theme.colorScheme.onSurfaceVariant,
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
  ];
}
