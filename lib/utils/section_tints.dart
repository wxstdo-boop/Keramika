import 'package:flutter/material.dart';

/// Цвета полок и секций списков — единый источник правды.
///
/// «Активные» (задачи) и «Полезные» (привычки) — ОДИН и тот же зелёный:
/// раньше задачи красили полку своим зелёным, а привычки — Material `green`,
/// и два раздела читались как из разных приложений. «Выполненные» —
/// приглушённый сине-серый (спокойнее активных), «Вредные» — красный.
///
/// Цвета адаптивны к теме: на тёмном фоне насыщенный зелёный/синий теряет
/// контраст, поэтому там берётся осветлённый оттенок.
abstract final class SectionTints {
  SectionTints._();

  static const Color _activeLight = Color(0xFF2E7D32);
  static const Color _activeDark = Color(0xFF7BD88F);
  static const Color _completedLight = Color(0xFF546E7A);
  static const Color _completedDark = Color(0xFF9FB2C4);

  /// Полка «Активные» (задачи) и секция «Полезные» (привычки) — одна и та же.
  static Color active(ThemeData theme) =>
      theme.brightness == Brightness.dark ? _activeDark : _activeLight;

  /// Полка «Выполненные» — спокойнее активных.
  static Color completed(ThemeData theme) =>
      theme.brightness == Brightness.dark ? _completedDark : _completedLight;

  /// Секция «Вредные» (привычки) — красный.
  static Color harmful(ThemeData theme) => Colors.red;
}
