import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../utils/design_tokens.dart';

/// Единый построитель темы приложения.
///
/// Раньше это был приватный метод `_buildCachedTheme` внутри `KeramikaApp`.
/// Вынесен наружу, чтобы тесты и генератор скриншотов строили РОВНО ту же
/// тему, что и приложение: иначе «витрина» расходилась с реальным видом
/// (другие радиусы, шрифты, тултипы).
///
/// Кэш по-прежнему живёт в `KeramikaApp` — здесь только чистая сборка.
ThemeData buildKeramikaTheme(
  ColorScheme scheme, {
  required bool isDark,
  required bool isGrokStyle,
  String? fontFamily,
}) {
  final appFontFamily = fontFamily == 'caveat' ? 'Caveat' : null;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Вибро-отклик на тап по каждой кнопке/плитке/вкладке: Flutter по
    // умолчанию не вибрирует на кнопках, а на HyperOS системная отдача
    // подавлена. Плеск = только целевое нажатие, скролл не срабатывает.
    splashFactory: const TapHapticsSplash(InkSparkle.splashFactory),
    // ШРИФТ ЗАДАН В САМОЙ ТЕМЕ: ThemeData(fontFamily:) задаёт его как
    // базовый для ВСЕЙ иерархии — DefaultTextStyle, Text из theme.textTheme,
    // Material-виджеты (AppBar, капсулы, кнопки) и т.д. Это гарантирует,
    // что Caveat применится везде, а не только в виджетах, вытягивающих
    // стиль из textTheme. При обычном шрифте — null (системный Roboto).
    fontFamily: appFontFamily,
    // Лёгкая цветокоррекция «приятнее глазу» без смены палитр: чуть
    // больше воздуха в тексте, мягче тени и скругления карточек,
    // деликатный размытый фон вместо сплошного — глаза меньше устают.
    // Базовый textTheme: слегка крупнее стандарта, чтобы компенсировать
    // малую x-высоту Caveat (глобальный TextScaler больше не используем —
    // он не доходил до части виджетов). Здесь размеры применяются
    // безусловно.
    textTheme: Typography.material2021(platform: TargetPlatform.android).black
        .apply(
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
          // fontFamily ВО ВСЕХ стилях сразу (apply применяет его ко
          // всему TextTheme): иначе часть стилей (headline, display и
          // т.п.) остаётся с явным Roboto из .black и Caveat выглядит
          // «не подстроенным». При обычном шрифте — null, остаётся
          // системный Roboto. AnimatedTheme не интерполирует строку
          // fontFamily — смена мгновенная.
          fontFamily: appFontFamily,
        )
        .copyWith(
          // Для Caveat размеры чуть больше: у него маленькая x-высота,
          // иначе текст выглядит мельче Roboto. Обычный (не Caveat)
          // шрифт чуть уменьшен: в разделах (будильники/привычки/РП/
          // задачи) текст плотнее, слова не «уезжают» на новую строку
          // и не оставляют пустых мест при переносе.
          // Начертания — из шкалы Weights, а не «магические» w500/w600:
          // иерархия «чем важнее — тем жирнее» держится одним источником.
          titleMedium: TextStyle(
            fontSize: appFontFamily == null ? 16 : 21,
            fontWeight: Weights.semibold,
          ),
          titleSmall: TextStyle(
            fontSize: appFontFamily == null ? 14 : 19,
            fontWeight: Weights.semibold,
          ),
          // Время будильника (headlineSmall по умолчанию 24 — крупнее,
          // чем остальные разделы; на обычном шрифте чуть меньше).
          headlineSmall: TextStyle(
            fontSize: appFontFamily == null ? 22 : 26,
            fontWeight: Weights.bold,
          ),
          bodyLarge: TextStyle(
            fontSize: appFontFamily == null ? 13 : 18,
            fontWeight: Weights.medium,
          ),
          bodyMedium: TextStyle(
            fontSize: appFontFamily == null ? 11 : 16,
            fontWeight: Weights.medium,
          ),
          bodySmall: TextStyle(
            fontSize: appFontFamily == null ? 10 : 15,
            fontWeight: Weights.medium,
          ),
          labelSmall: TextStyle(
            fontSize: appFontFamily == null ? 9 : 14,
            fontWeight: Weights.medium,
          ),
          labelMedium: TextStyle(
            fontSize: appFontFamily == null ? 11 : 16,
            fontWeight: Weights.medium,
          ),
        ),
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      color: scheme.surfaceContainerLow,
      shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.30 : 0.12),
      surfaceTintColor: scheme.primary.withValues(alpha: isDark ? 0.03 : 0.025),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          isGrokStyle ? Radii.sm : Radii.xl,
        ),
      ),
    ),
    // Цветокоррекция: единый мягкий стиль для всех диалогов и боттом-
    // шитов (светлее/воздушнее, скругление как у карточек) — без смены
    // цветовых тем.
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          isGrokStyle ? Radii.md : Radii.xl,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(isGrokStyle ? Radii.md : Radii.xl),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            isGrokStyle ? Radii.xs : Radii.lg,
          ),
        ),
      ),
    ),
    // Тултипы (долгое зажатие кнопок — «Ада», «Будильники» и т.п.):
    // ЕДИНЫЙ стиль для ВСЕХ — как у плавного тултипа таблетки разделов:
    // светлая плашка на светлой теме, тёмная на тёмной, с мягкой обводкой.
    // Никакой тёмной «спеллчек»-плашки поверх светлого интерфейса.
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark
            ? scheme.surfaceContainerHigh
            : scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      textStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 13,
        height: 1.25,
        fontWeight: Weights.medium,
      ),
      waitDuration: const Duration(milliseconds: 350),
      showDuration: const Duration(seconds: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    textSelectionTheme: const TextSelectionThemeData(),
  );
}
