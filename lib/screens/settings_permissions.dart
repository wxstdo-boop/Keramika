part of 'settings_screen.dart';

/// Проверка и выдача разрешений: уведомления, полноэкранные уведомления,
/// автозапуск, плашка «Разрешения не выданы» и её выдача.
extension _SettingsPermissions on _SettingsScreenState {
  Future<void> _checkNotificationsEnabled() async {
    // Проверяем один раз и кэшируем. БЕЗ setState внутри: вызывается из
    // _loadInitialState (один общий setState в конце) — иначе вход в
    // настройки дёргается повторной перестройкой посреди перехода.
    if (_notificationsEnabled == null) {
      final enabled = await notificationService.areNotificationsEnabled();
      _notificationsEnabled = enabled;
    }
  }

  void _onNotificationChanged() {
    // При изменении состояния уведомлений — сбрасываем кэш, чтобы при следующей проверке было актуальное значение
    if (mounted) {
      _notificationsEnabled = null;
      _checkNotificationsEnabled().then((_) {
        if (mounted) _refresh(() {});
      });
    }
  }

  Future<void> _checkPermissionWarning() async {
    final dismissed =
        globalPrefs.getBool('permission_warning_dismissed') ?? false;
    _permissionWarningDismissed = dismissed;
  }

  void _dismissPermissionWarning() async {
    await globalPrefs.setBool('permission_warning_dismissed', true);
    if (mounted) _refresh(() => _permissionWarningDismissed = true);
  }

  Widget _buildPermissionWarning(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // На светлых темах — мягкий розово-красный, на тёмных — глубокий
    // винный градиент с хорошим контрастом текста.
    final cardGradient = dark
        ? const [Color(0xFF4A0E1F), Color(0xFF7A1626)]
        : const [Color(0xFFFFE4EA), Color(0xFFFFD6DF)];
    final textColor = dark ? Colors.white : const Color(0xFF8C1D36);
    final subColor = dark
        ? Colors.white.withValues(alpha: 0.75)
        : const Color(0xFF8C1D36).withValues(alpha: 0.8);
    final iconBg = dark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.75);
    final btnGradient = dark
        ? const [Color(0xFFFF5C8A), Color(0xFFD81B60)]
        : const [Color(0xFFE91E63), Color(0xFFC2185B)];

    return Card(
      key: const ValueKey('warn_card'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: dark
              ? Colors.white.withValues(alpha: 0.10)
              : cs.error.withValues(alpha: 0.25),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: cardGradient,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
        child: Row(
          children: [
            // Иконка в кружке — не «жёстко красная», а на подложке.
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: iconBg),
              child: Icon(
                Icons.warning_amber_rounded,
                color: textColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Разрешения не выданы',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Будильники и уведомления не будут работать',
                    style: TextStyle(
                      color: subColor,
                      fontSize: 12.5,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Объёмная кнопка «Выдать» — градиент, ripple, плавное нажатие.
            // Material + InkWell дают настоящую «волну» при тапе (белая
            // вспышка расходится от пальца), AnimatedScale — мягкое
            // «продавливание» кнопки, тень-свечение — глубину.
            TweenAnimationBuilder<double>(
              tween: Tween(end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.scale(scale: t, child: child),
              ),
              child: AnimatedScale(
                scale: _grantPressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: btnGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFD81B60,
                          ).withValues(alpha: _grantPressed ? 0.42 : 0.5),
                          blurRadius: _grantPressed ? 12 : 14,
                          spreadRadius: 1,
                          offset: Offset(0, _grantPressed ? 4 : 5),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      splashColor: Colors.white.withValues(alpha: 0.35),
                      highlightColor: Colors.white.withValues(alpha: 0.12),
                      onTapDown: (_) => _refresh(() => _grantPressed = true),
                      onTapUp: (_) {
                        _refresh(() => _grantPressed = false);
                        _grantPermissions();
                      },
                      onTapCancel: () => _refresh(() => _grantPressed = false),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              size: 15,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Выдать',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                                letterSpacing: 0.4,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _grantPermissions() async {
    // Сначала плавно скрываем карточку (fade 300ms), и только потом
    // запрашиваем разрешения — иначе системный экран уводит приложение
    // в фон и анимация исчезания не видна.
    _dismissPermissionWarning();
    // Сбрасываем кэш статуса, чтобы при следующем открытии настроек проверили заново
    notificationService.resetNotificationStatusCache();
    await Future.delayed(const Duration(milliseconds: 350));
    // Запрашиваем разрешения: системный диалог на уведомления +
    // разрешение на точные будильники.
    await notificationService.requestPermissions();
  }
}
