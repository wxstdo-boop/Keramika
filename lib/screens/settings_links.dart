part of 'settings_screen.dart';

/// Внешние ссылки, окно поддержки, пасхалка версии и очистка кэша.
extension _SettingsLinks on _SettingsScreenState {
  String get _boostyUrl =>
      globalPrefs.getString('boosty_url') ?? 'https://boosty.to/larafut';

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Окно снизу с выбором способа поддержки: крупные градиентные кнопки
  /// CloudTips и Boosty, каждая открывает свою страницу оплаты. Оформление
  /// строится на цветах ТЕКУЩЕЙ темы — тёмные/светлые темы окно
  /// подхватывает само.
  void _showSupportSheet() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = cs.primary;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: false,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Ручка-индикатор сверху.
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    // Иконка-«сердце» в мягком градиентном кружке в цвете
                    // темы (primary вместо розового).
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.22),
                            accent.withValues(alpha: 0.10),
                          ],
                        ),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(Icons.favorite, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        Translations.t('support', context, 'Support'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.15,
                        ),
                      ),
                    ),
                    // Крестик — закрыть окно.
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: cs.onSurfaceVariant,
                        size: 22,
                      ),
                      visualDensity: VisualDensity.compact,
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
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                // Способы оплаты — большие кнопки-«таблетки» В ЦВЕТАХ ТЕМЫ
                // с уникальными значками: красная сумка у Ozon — плашка SOON
                // сохранена, но зажимается ТАКЖЕ плавно, как Boosty (340 мс).
                _SupportPill(
                  label: 'Ozon',
                  icon: Icons.shopping_bag_rounded,
                  badge: 'SOON',
                  subtitle: Translations.t('supportOzonSubtitle', context),
                  gradient: const [
                    Color(0xFFFF5A6E),
                    Color(0xFFE8263C),
                    Color(0xFFB3152E),
                  ],
                  glow: const Color(0xFFE8263C),
                  onTap: () {
                    showBeautifulSnackBar(
                      context,
                      message: Translations.t(
                        'supportSoonToast',
                        context,
                        'Ozon is coming soon. Stay tuned!',
                      ),
                      icon: Icons.hourglass_top_rounded,
                    );
                  },
                ),
                const SizedBox(height: 10),
                _SupportPill(
                  label: 'Boosty',
                  icon: Icons.rocket_launch_rounded,
                  subtitle: Translations.t('supportBoostySubtitle', context),
                  gradient: [
                    Color.lerp(cs.tertiary, Colors.white, 0.30)!,
                    cs.tertiary,
                    Color.lerp(cs.tertiary, Colors.black, 0.16)!,
                  ],
                  glow: cs.tertiary,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _openLink(_boostyUrl);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Пасхалка по долгому нажатию на номер версии: тяжёлый тактильный
  /// отклик, залп конфетти в цветах текущей темы и тост.
  void _onVersionLongPress() {
    Haptics.heavy();
    showConfettiBurst(context);
    showBeautifulSnackBar(
      context,
      message: 'Ты нашёл пасхалку. Agysha — свободное приложение.',
      icon: Icons.celebration_outlined,
      duration: const Duration(milliseconds: 2600),
    );
  }

  Future<void> _openChangelog() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangelogScreen()));
  }

  Future<void> _openGitHub() async {
    await _openLink('https://github.com/wxstdo-boop/agysha');
  }

  Future<void> _openGitLab() async {
    await _openLink('https://gitlab.com/wxstdo/keramika');
  }

  Future<void> _clearCache() async {
    try {
      // Clear in-memory Flutter image cache.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        for (final entity in tempDir.listSync()) {
          try {
            if (entity is File) {
              entity.deleteSync();
            } else if (entity is Directory) {
              entity.deleteSync(recursive: true);
            }
          } catch (_) {}
        }
      }
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('clearCacheDone', context),
        );
      }
    } catch (_) {
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('diagError', context),
          icon: Icons.error_outline,
          iconColor: Colors.red,
        );
      }
    }
  }
}
