import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Мягкие системные звуки на подтверждениях — «звуковой дизайн» приложения.
///
/// Парный к [Haptics] слой: там тактильная отдача, здесь короткий тихий
/// отклик системы. Используем штатные [SystemSound] Flutter, а не свои
/// файлы: они мгновенны (не требуют загрузки ассета и плеера), вписаны в
/// системную громкость «касаний» и не звучат чужеродно рядом с другими
/// приложениями. По умолчанию ВЫКЛЮЧЕНЫ: звук — навязчивее вибрации, его
/// должен включить сам человек.
///
/// Звуки сознательно не используются для будильников и уведомлений — там
/// свой громкий канал (см. `NotificationService`), и смешивать их нельзя.
class Sounds {
  Sounds._();

  /// Включены ли подтверждающие звуки. Выключатель в настройках гасит ВСЕ
  /// вызовы; по умолчанию — выключено.
  static bool enabled = false;

  static DateTime? _lastFire;

  /// Лёгкий «клик» — выбор, отметка галочки, переключение.
  static Future<void> click() => _play(SystemSoundType.click);

  /// Мягкое завершение — успешно сохранено, задача закрыта.
  ///
  /// На Android системного «успеха» нет, поэтому опираемся на «клик»: он
  /// короткий и не раздражает. Вынесено отдельным методом, чтобы смена
  /// звука «успеха» была правкой в одном месте.
  static Future<void> success() => _play(SystemSoundType.click);

  static Future<void> _play(SystemSoundType type) async {
    if (kIsWeb || !enabled) return;
    // Троттл как у [Haptics]: один тап не должен давать два звука
    // (тап-даун плеска + тап-ап виджета).
    final now = DateTime.now();
    if (_lastFire != null &&
        now.difference(_lastFire!) < const Duration(milliseconds: 90)) {
      return;
    }
    _lastFire = now;
    try {
      await SystemSound.play(type);
    } catch (_) {
      // Платформа без звукового канала — молча пропускаем.
    }
  }
}
