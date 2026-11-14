part of 'settings_screen.dart';

/// Поведение: автосохранение, экспериментальное, вибрация, звуки, «убрать анимации».
extension _SettingsSectionBehavior on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsBehaviorSection(
    BuildContext context,
    AgyshaAppState appState,
    ThemeData theme,
  ) => <Widget>[
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          children: [
            // «Экспериментальное» — показ/скрытие секции таймеров на экране
            // будильников. Только видимость: таймеры при выключении НЕ
            // удаляются, они остаются в хранилище.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: TweenAnimationBuilder<Color?>(
                  // Цвет значка секции таймера меняется ПЛАВНО при
                  // включении/выключении (300 мс), а не мигает резко.
                  tween: ColorTween(
                    end: _experimental
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  builder: (context, color, _) =>
                      Icon(Icons.science_outlined, color: color),
                ),
                title: Text(Translations.t('experimentalSettings', context)),
                subtitle: Text(
                  Translations.t('experimentalDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_experimental;
                  await SettingsService.saveExperimental(newVal);
                  _refresh(() => _experimental = newVal);
                },
                trailing: VolumetricSwitch(
                  value: _experimental,
                  onChanged: (v) async {
                    await SettingsService.saveExperimental(v);
                    _refresh(() => _experimental = v);
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.save_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('autoSave', context)),
                subtitle: Text(
                  Translations.t('autoSaveDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_autoSave;
                  await SettingsService.saveAutoSave(newVal);
                  _refresh(() => _autoSave = newVal);
                  if (newVal) {
                    startAutoSave();
                  } else {
                    stopAutoSave();
                  }
                },
                trailing: VolumetricSwitch(
                  value: _autoSave,
                  onChanged: (v) async {
                    await SettingsService.saveAutoSave(v);
                    _refresh(() => _autoSave = v);
                    if (v) {
                      startAutoSave();
                    } else {
                      stopAutoSave();
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.cleaning_services_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('clearCache', context)),
                subtitle: Text(
                  Translations.t('clearCacheDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: _clearCache,
              ),
            ),
            const Divider(height: 1),
            // Вибрация: гасит ВСЕ отклики — и прямые вызовы, и плеск
            // кнопок. Тот же объёмный переключатель, что у соседних
            // строк, чтобы карточка читалась единым блоком.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.vibration,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('haptics', context)),
                subtitle: Text(
                  Translations.t('hapticsDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final v = !_haptics;
                  await _setHaptics(v);
                },
                trailing: VolumetricSwitch(
                  value: _haptics,
                  onChanged: _setHaptics,
                  activeColor: theme.colorScheme.primary,
                  semanticLabel: Translations.t('haptics', context),
                ),
              ),
            ),
            const Divider(height: 1),
            // «Звуки»: короткие системные отклики на подтверждениях.
            // Выключены по умолчанию — звук навязчивее вибрации.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.volume_up_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('sounds', context)),
                subtitle: Text(
                  Translations.t('soundsDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final v = !_sounds;
                  await _setSounds(v);
                },
                trailing: VolumetricSwitch(
                  value: _sounds,
                  onChanged: _setSounds,
                  activeColor: theme.colorScheme.primary,
                  semanticLabel: Translations.t('sounds', context),
                ),
              ),
            ),
            const Divider(height: 1),
            // «Убрать анимации»: гасит декоративные петли (блики, стая
            // птиц, дыхание свечения) и переходы. Системный запрос
            // «убрать анимации» действует независимо и всегда сильнее.
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  Icons.motion_photos_off_outlined,
                  color: theme.colorScheme.primary,
                ),
                title: Text(Translations.t('reduceMotion', context)),
                subtitle: Text(
                  Translations.t('reduceMotionDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final v = !_reduceMotion;
                  await _setReduceMotion(v);
                },
                trailing: VolumetricSwitch(
                  value: _reduceMotion,
                  onChanged: _setReduceMotion,
                  activeColor: theme.colorScheme.primary,
                  semanticLabel: Translations.t('reduceMotion', context),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ];
}
