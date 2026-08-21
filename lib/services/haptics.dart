import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Надёжная тактильная отдача по всему приложению.
///
/// На Android используем нативный канал `com.wetidom.keramika/haptics`,
/// который бьёт напрямую через системный Vibrator (VibrationEffect) — он
/// работает даже там, где системный `HapticFeedback` подавлен настройками
/// MIUI («обратная связь при касании»). На остальных платформах — фолбэк
/// на стандартный `HapticFeedback` из Flutter.
class Haptics {
  Haptics._();

  static const MethodChannel _channel = MethodChannel(
    'com.wetidom.keramika/haptics',
  );

  /// Лёгкий «клик» — выбор, отметка галочки.
  static Future<void> select() => _invoke('select');

  /// Лёгкий удар — обычная кнопка.
  static Future<void> light() => _invoke('light');

  /// Средний удар — переключения, ползунки.
  static Future<void> medium() => _invoke('medium');

  /// Сильный удар — ошибки, важные действия.
  static Future<void> heavy() => _invoke('heavy');

  static Future<void> _invoke(String kind) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>(kind);
    } catch (_) {
      // Канал не зарегистрирован (например, на iOS) — системный фолбэк.
      try {
        switch (kind) {
          case 'select':
            await HapticFeedback.selectionClick();
          case 'medium':
            await HapticFeedback.mediumImpact();
          case 'heavy':
            await HapticFeedback.heavyImpact();
          default:
            await HapticFeedback.lightImpact();
        }
      } catch (_) {}
    }
  }
}
