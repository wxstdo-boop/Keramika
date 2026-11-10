import 'package:flutter/material.dart';

/// Цвета полок и секций списков — единый источник правды.
///
/// «Полезные» (привычки) и активные задачи — ОДИН и тот же зелёный: раньше
/// задачи красили свой список зелёным, а привычки — Material `green`, и два
/// раздела читались как из разных приложений. Архив задач и «Вредные» —
/// свои тона: приглушённый сине-серый и красный.
///
/// Цвета адаптивны к теме: на тёмном фоне насыщенный зелёный/синий теряет
/// контраст, поэтому там берётся осветлённый оттенок.
abstract final class SectionTints {
  SectionTints._();

  static const Color _activeLight = Color(0xFF2E7D32);
  static const Color _activeDark = Color(0xFF7BD88F);
  static const Color _completedLight = Color(0xFF546E7A);
  static const Color _completedDark = Color(0xFF9FB2C4);

  /// Секция «Полезные» (привычки) и активные задачи — один и тот же тон.
  static Color active(ThemeData theme) =>
      theme.brightness == Brightness.dark ? _activeDark : _activeLight;

  /// Архивная полка задач — спокойнее активных.
  static Color completed(ThemeData theme) =>
      theme.brightness == Brightness.dark ? _completedDark : _completedLight;

  /// Секция «Вредные» (привычки) — красный.
  static Color harmful(ThemeData theme) => Colors.red;
}
