part of 'settings_screen.dart';

/// Меню выбора языка и шрифта: компактный квадрат, который появляется
/// мелким и плавно растёт в полный рост (scale + fade).
extension _SettingsLanguageFont on _SettingsScreenState {
  /// Название текущего языка для поля выбора.
  String _languageLabel(BuildContext context, String code) {
    switch (code) {
      case 'system':
        return Translations.followSystemOf(context);
      case 'en':
        return Translations.englishOf(context);
      case 'ru':
        return Translations.russianOf(context);
      case 'fr':
        return Translations.frenchOf(context);
      default:
        return Translations.followSystemOf(context);
    }
  }

  /// Меню выбора языка: компактный квадрат со скруглёнными углами, который
  /// появляется МЕЛКИМ и плавно растёт в полный рост (scale + fade),
  /// вместо стандартной анимации выпадашки.
  Future<void> _showLanguageMenu(
    BuildContext context,
    AgyshaAppState appState,
  ) async {
    // Язык выбирается БЕЗ закрытия окна: тап по пункту сразу переключает
    // язык и плавно обновляет фон/галочку, а само меню закрывается ТОЛЬКО
    // тапом вне квадрата (барьер). Раньше тап по пункту сразу «щёлкал»
    // окно закрытием и не давал попробовать другие языки подряд.
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final codes = ['system', 'en', 'ru', 'fr'];
        return StatefulBuilder(
          builder: (ctx, setState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                // Урезано по бокам: квадрат, а не растянутая лента.
                width: 230,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in codes)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          appState.setLanguageCode(code);
                          _refresh(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: code == appState.languageCode
                                ? cs.primary.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: code == appState.languageCode
                                        ? cs.primary
                                        : cs.onSurface,
                                    fontWeight: code == appState.languageCode
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  child: Text(_languageLabel(context, code)),
                                ),
                              ),
                              // Галочка плавно появляется/исчезает и
                              // «проскальзывает» при смене выбранного языка.
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                    ),
                                child: code == appState.languageCode
                                    ? Icon(
                                        Icons.check_rounded,
                                        key: const ValueKey('check'),
                                        size: 20,
                                        color: cs.primary,
                                      )
                                    : const SizedBox(
                                        key: ValueKey('no_check'),
                                        width: 20,
                                        height: 20,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      // Мелкий квадрат → плавный полный рост.
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  Future<void> _showFontMenu(
    BuildContext context,
    AgyshaAppState appState,
  ) async {
    // Шрифт выбирается ТАК ЖЕ, как язык: меню-квадрат с иконками и
    // плавной обводкой/галочкой, которое не закрывается при выборе —
    // только тапом вне квадрата.
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final fonts = [
          ('ordinary', Icons.font_download_outlined),
          ('caveat', Icons.draw_outlined),
        ];
        String fontLabel(String f) => f == 'caveat' ? 'Caveat' : 'Обычный';
        return StatefulBuilder(
          builder: (ctx, setState) => Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 230,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (f, icon) in fonts)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          appState.setFontFamily(f);
                          _refresh(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: f == appState.fontFamily
                                ? cs.primary.withValues(alpha: 0.16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: Icon(
                                  icon,
                                  key: ValueKey(icon),
                                  size: 20,
                                  color: f == appState.fontFamily
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  style: theme.textTheme.bodyLarge!.copyWith(
                                    color: f == appState.fontFamily
                                        ? cs.primary
                                        : cs.onSurface,
                                    fontWeight: f == appState.fontFamily
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                  child: Text(
                                    fontLabel(f),
                                    style: f == 'caveat'
                                        ? const TextStyle(
                                            fontFamily: 'Caveat',
                                            fontSize: 24,
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(
                                        opacity: anim,
                                        child: child,
                                      ),
                                    ),
                                child: f == appState.fontFamily
                                    ? Icon(
                                        Icons.check_rounded,
                                        key: const ValueKey('check'),
                                        size: 20,
                                        color: cs.primary,
                                      )
                                    : const SizedBox(
                                        key: ValueKey('no_check'),
                                        width: 20,
                                        height: 20,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      // Мелкий квадрат → плавный полный рост.
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.2, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }
}
