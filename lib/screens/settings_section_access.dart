part of 'settings_screen.dart';

/// Доступ и сигналы: ПИН-код, уведомления, полноэкранные уведомления, батарея.
extension _SettingsSectionAccess on _SettingsScreenState {
  /// Раздел списка настроек. Живёт отдельно, чтобы uild оставался читаемым.
  List<Widget> _settingsAccessSection(
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
            Text(
              Translations.pinLockOf(context),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Заголовок «Установить / Сменить ПИН» плавно
                      // меняется, а не дёргается при переключении.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(sizeFactor: anim),
                        ),
                        child: Text(
                          _hasPin
                              ? Translations.changePinOf(context)
                              : Translations.setPinOf(context),
                          key: ValueKey('pin_title_$_hasPin'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Translations.pinDescriptionOf(context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Замок плавно переключается между lock/lock_open
                // (fade + лёгкий поворот), а не дёргается мгновенно.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: RotationTransition(
                      turns: Tween<double>(
                        begin: -0.12,
                        end: 0,
                      ).animate(anim),
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.85,
                          end: 1,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                  ),
                  child: PressScale(
                    pressedScale: 0.90,
                    duration: const Duration(milliseconds: 200),
                    releaseDuration: const Duration(milliseconds: 320),
                    child: IconButton(
                      key: ValueKey('pin_lock_$_hasPin'),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_hasPin ? Icons.lock : Icons.lock_open),
                      onPressed: _managePin,
                    ),
                  ),
                ),
                // Кнопка «удалить ПИН» появляется/исчезает плавно, а место
                // под неё зарезервировано всегда (48px) — ряд не «прыгает»
                // влево-вправо при переключении.
                SizedBox(
                  width: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: ScaleTransition(scale: anim, child: child),
                    ),
                    child: _hasPin
                        ? PressScale(
                            pressedScale: 0.86,
                            duration: const Duration(milliseconds: 200),
                            releaseDuration: const Duration(
                              milliseconds: 320,
                            ),
                            child: IconButton(
                              key: const ValueKey('pin_delete_btn'),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: _removePin,
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('pin_delete_placeholder'),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    ListenableBuilder(
      listenable: notificationService,
      builder: (context, _) {
        final fsOn = notificationService.fullscreen;
        // Намерение пользователя и РЕАЛЬНОЕ системное право — разные вещи.
        final fsBlocked = fsOn && !notificationService.fullScreenGranted;
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.notificationsOf(context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                PressScale(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Translations.notificationsDescOf(context)),
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        notificationService.enabled
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        key: ValueKey(
                          'notif_icon_${notificationService.enabled}',
                        ),
                        color: notificationService.enabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () async {
                      final newVal = !notificationService.enabled;
                      await notificationService.setEnabled(newVal);
                      if (newVal) {
                        // Включили уведомления — реально перепланируем
                        // будильники и проверки реальности, иначе
                        // переключатель только ставил флаг.
                        await rescheduleAllNotifications();
                      }
                    },
                    trailing: VolumetricSwitch(
                      value: notificationService.enabled,
                      onChanged: (v) async {
                        await notificationService.setEnabled(v);
                        if (v) {
                          // Включили уведомления — реально перепланируем
                          // будильники и проверки реальности, иначе
                          // переключатель только ставил флаг.
                          await rescheduleAllNotifications();
                        }
                      },
                      activeColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
                PressScale(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(Translations.fullscreenNotifDescOf(context)),
                    // Переключатель выше — это НАМЕРЕНИЕ пользователя.
                    // Право же выдаёт система (app-op USE_FULL_SCREEN_INTENT),
                    // и с Android 14 оно по умолчанию ЗАПРЕЩЕНО: без него
                    // будильник приходит только шапкой уведомления, экран
                    // задачи поверх блокировки не появляется. Показываем это
                    // честно и ведём ровно на тот экран, где тумблер живёт.
                    subtitle: fsBlocked
                        ? Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              Translations.t(
                                'fullScreenGrantMissing',
                                context,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          )
                        : null,
                    leading: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.85,
                            end: 1,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        fsOn && !fsBlocked
                            ? Icons.fullscreen
                            : Icons.fullscreen_exit,
                        key: ValueKey('fullscreen_icon_${fsOn}_$fsBlocked'),
                        color: fsBlocked
                            ? theme.colorScheme.error
                            : fsOn
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onTap: () async {
                      if (fsBlocked) {
                        // Право не выдано → тап по строке ведёт на его выдачу.
                        await openFullScreenNotifSettings();
                        return;
                      }
                      await notificationService.setFullscreen(!fsOn);
                    },
                    trailing: VolumetricSwitch(
                      value: fsOn,
                      onChanged: (v) => notificationService.setFullscreen(v),
                      activeColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
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
              Translations.batteryOptimizationOf(context),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.battery_saver, color: Colors.green),
                title: Text(Translations.batteryOptDescOf(context)),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final batteryText = Translations.batteryOpenedOf(ctx);
                  final cantOpenText = Translations.t(
                    'settingsCantOpen',
                    ctx,
                  );
                  final opened = await openAppSettingsAndroid();
                  if (!ctx.mounted) return;
                  if (opened) {
                    showBeautifulSnackBar(ctx, message: batteryText);
                  } else {
                    showBeautifulSnackBar(
                      ctx,
                      message: cantOpenText,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
            ),
            const Divider(height: 1),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.power_settings_new,
                  color: Colors.orange,
                ),
                title: Text(Translations.t('autostart', context)),
                subtitle: Text(
                  Translations.t('autostartDesc', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final text = Translations.t('settingsCantOpen', ctx);
                  final opened = await openAutostartSettings();
                  if (!opened && ctx.mounted) {
                    showBeautifulSnackBar(
                      ctx,
                      message: text,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
            ),
            const Divider(height: 1),
            PressScale(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(
                  Icons.notifications_active,
                  color: Colors.red,
                ),
                title: Text(Translations.t('fullScreenNotifTitle', context)),
                subtitle: Text(
                  Translations.t('fullScreenNotifBody', context),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: const Icon(Icons.open_in_new, size: 20),
                onTap: () async {
                  final ctx = context;
                  final text = Translations.t('settingsCantOpen', ctx);
                  final opened = await openFullScreenNotifSettings();
                  if (!opened && ctx.mounted) {
                    showBeautifulSnackBar(
                      ctx,
                      message: text,
                      icon: Icons.error_outline,
                      iconColor: Colors.red,
                      duration: const Duration(seconds: 4),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 8),
    Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: PressScale(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(Translations.t('resetWarnings', context)),
            trailing: const Icon(Icons.restart_alt_outlined, size: 20),
            onTap: () async {
              await globalPrefs.setBool('welcome_dismissed', false);
              await globalPrefs.setBool('popup_warning_shown', false);
              await globalPrefs.setBool(
                'permission_warning_dismissed',
                false,
              );
              if (context.mounted) {
                showBeautifulSnackBar(
                  context,
                  message: Translations.t('warningsResetDone', context),
                );
              }
              if (context.mounted) {
                AgyshaApp.of(context).refreshApp();
              }
            },
          ),
        ),
      ),
    ),
  ];
}
