part of 'settings_screen.dart';

/// Горизонтальная карусель тем и её плитка.
extension _SettingsThemeCarousel on _SettingsScreenState {
  /// Красивая горизонтальная карусель тем: текущая тема по центру,
  /// соседние видны по краям (viewportFraction 0.55). Листается плавно,
  /// при остановке на новой странице тема переключается штатной
  /// анимацией MaterialApp — без вспышек и размытий.
  Widget _buildThemeCarousel(BuildContext context) {
    final appState = AgyshaApp.of(context);
    final entries = <_ThemeEntry>[
      // MUTILATED — САМАЯ ПЕРВАЯ тема, не переводится.
      const _ThemeEntry(
        'mutilated',
        'MUTILATED',
        Icons.bloodtype_outlined,
        specialMutilated: true,
      ),
      _ThemeEntry('light', Translations.lightOf(context), Icons.light_mode),
      _ThemeEntry('dark', Translations.darkOf(context), Icons.dark_mode),
      _ThemeEntry(
        'oled',
        Translations.t('themeOled', context, 'OLED Black'),
        Icons.brightness_2_outlined,
      ),
      _ThemeEntry(
        'system',
        Translations.systemOf(context),
        Icons.brightness_auto,
      ),
      _ThemeEntry(
        'systemLight',
        Translations.t('themeSystemLight', context),
        Icons.palette_outlined,
      ),
      _ThemeEntry('rose', Translations.roseOf(context), Icons.favorite_outline),
      _ThemeEntry(
        'peach',
        Translations.peachOf(context),
        Icons.local_florist_outlined,
      ),
      const _ThemeEntry('grok', 'Grok', Icons.auto_awesome),
      const _ThemeEntry('darkGrok', 'Grok Dark', Icons.dark_mode),
      // «Метель» — подарок 12-го дня ивента: в карусели появляется только
      // после его получения и пропадает вместе со сбросом события.
      if (NewYearEventService().prizeGranted)
        _ThemeEntry('metel', Translations.t('metel', context), Icons.snowing),
    ];
    final currentIndex = entries.indexWhere((e) => e.key == appState.themeKey);
    _themePageCtrl ??= PageController(
      viewportFraction: 0.55,
      initialPage: currentIndex < 0 ? 0 : currentIndex,
    );
    return SizedBox(
      height: 124,
      child: PageView.builder(
        controller: _themePageCtrl,
        itemCount: entries.length,
        onPageChanged: (i) {
          final key = entries[i].key;
          if (key != appState.themeKey) appState.setThemeMode(key);
        },
        itemBuilder: (context, i) {
          final e = entries[i];
          return Center(
            child: _themePill(
              context,
              e.key,
              e.label,
              e.icon,
              specialMutilated: e.specialMutilated,
              // Тап по соседней теме прокручивает карусель к ней.
              extraOnSelected: () {
                final ctrl = _themePageCtrl;
                if (ctrl != null && ctrl.hasClients && ctrl.page != i) {
                  ctrl.animateToPage(
                    i,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  Widget _themePill(
    BuildContext context,
    String key,
    String label,
    IconData icon, {
    bool specialMutilated = false,
    VoidCallback? extraOnSelected,
  }) {
    final appState = AgyshaApp.of(context);
    final isSelected = appState.themeKey == key;
    // Для MUTILATED — зажатие 10 секунд показывает плашную «Вы элегант?»
    // с переводами. Плавно появляется, держится 3 секунды, плавно уходит.
    // ТОНКАЯ обводка (1px) с НАСТОЯЩЕЙ анимацией: begin всегда 0,
    // end = 1 для выбранного / 0 для остальных. TweenAnimationBuilder
    // сам анимирует переход (текущее значение → end) при каждом
    // rebuild, поэтому при выборе линия плавно «проявляется» (0→1),
    // при снятии — плавно «гаснет» (1→0). ВАЖНО: begin фиксирован —
    // одинаковые begin/end давали мгновенный скачок.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: isSelected ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      builder: (context2, alphaBorder, _) {
        final themeLocal = Theme.of(context2);
        final chip = ChoiceChip(
          // Крупные названия: в карусели у каждой темы много места, длинные
          // имена (MUTILATED, System Light) масштабируются вниз.
          label: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          // Галочка выбранной темы появляется плавно.
          avatar: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              isSelected ? Icons.check_circle : icon,
              key: ValueKey('pill_${key}_$isSelected'),
              size: 14,
            ),
          ),
          selected: isSelected,
          showCheckmark: false,
          onSelected: (selected) {
            Haptics.select();
            if (key == 'peach' && appState.themeKey == 'peach') {
              appState.togglePeachDark();
            } else {
              appState.setThemeMode(key);
            }
            extraOnSelected?.call();
          },
          // Обводка тонкая (1px) и АНИМИРУЕТСЯ по alpha каждый кадр.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: themeLocal.colorScheme.primary.withValues(
                alpha: alphaBorder,
              ),
              width: 1,
            ),
          ),
        );
        if (!specialMutilated) return Center(child: chip);
        return Center(
          child: _LongPressChip(
            duration: const Duration(seconds: 10),
            onLongPress: () {
              showBeautifulSnackBar(
                context,
                message:
                    'Вы элегантны? 🥀 — Are you elegant? — Êtes-vous élégant·e ?',
                icon: Icons.diamond_outlined,
                iconColor: const Color(0xFFFFD166),
                duration: const Duration(seconds: 3),
              );
            },
            child: chip,
          ),
        );
      },
    );
  }
}
