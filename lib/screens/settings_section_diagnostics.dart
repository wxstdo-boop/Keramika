part of 'settings_screen.dart';

/// Диагностика и уголок разработчика.
extension _SettingsSectionDiagnostics on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsDiagnosticsSection(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bug_report_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.diagnosticsOf(context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _diagTile(
              context,
              icon: Icons.alarm_outlined,
              label: Translations.t('diagAlarmTest', context),
              onTap: () => _runAlarmDiag(),
            ),
            _diagTile(
              context,
              icon: Icons.psychology_outlined,
              label: Translations.t('diagRcTest', context),
              onTap: () => _runRcDiag(),
            ),
            _diagTile(
              context,
              icon: Icons.volume_up_outlined,
              label: Translations.t('diagSoundTest', context),
              onTap: () async {
                final played = Translations.t('diagSoundPlayed', context);
                final player = AudioPlayer();
                try {
                  await player.play(AssetSource('sounds/default.wav'));
                  await Future.delayed(const Duration(milliseconds: 1500));
                  await player.stop();
                } catch (_) {}
                if (!context.mounted) return;
                player.dispose();
                showBeautifulSnackBar(context, message: played);
              },
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    SizeTransition(
      sizeFactor: _perfScale,
      axis: Axis.vertical,
      child: FadeTransition(
        opacity: _perfFade,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          // Канарейка вместо «телефонной» иконки developer-mode: стоит
          // статично, при тапе плавно машет крылом; повторные тапы,
          // пока анимация жива, игнорируются внутри самой канарейки.
          leading: const CanaryIcon(size: 40),
          title: Text(_developerCornerTitle(context)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          onTap: _devOpening ? null : _showDevToolsScreen,
        ),
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
            Row(
              children: [
                Icon(
                  Icons.backup_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  Translations.t('data', context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // Значок плавно меняется при включении/выключении:
                // контурные часы → залитые + галочка, с fade и «попом».
                // Значок автоэкспорта плавно меняется при включении/выключении:
                // чистый кроссфейд (без «попа»-масштаба, который дёргал) между
                // двумя РАЗНЫМИ значками — ещё и цвет мягко анимируется, чтобы
                // переход был ощутимо плавным, а не щелчком.
                leading: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeInOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: Icon(
                    _autoExport
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_sync_outlined,
                    key: ValueKey('autoexport_$_autoExport'),
                    color: theme.colorScheme.primary.withValues(
                      alpha: _autoExport ? 1.0 : 0.45,
                    ),
                  ),
                ),
                title: Text(Translations.t('autoExport', context)),
                subtitle: Text(
                  Translations.t('autoExportHourly', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () async {
                  final newVal = !_autoExport;
                  await SettingsService.saveAutoExport(newVal);
                  _refresh(() => _autoExport = newVal);
                  if (newVal) {
                    startAutoExport(runImmediately: true);
                  } else {
                    stopAutoExport();
                  }
                },
                trailing: VolumetricSwitch(
                  value: _autoExport,
                  onChanged: (v) async {
                    await SettingsService.saveAutoExport(v);
                    _refresh(() => _autoExport = v);
                    if (v) {
                      startAutoExport(runImmediately: true);
                    } else {
                      stopAutoExport();
                    }
                  },
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _exportData,
                    icon: const Icon(Icons.upload_outlined, size: 18),
                    label: Text(Translations.t('export', context)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _importData,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(Translations.t('import', context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              Translations.t('license', context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _showDevModeDialog,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Agysha',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
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
