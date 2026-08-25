import 'package:flutter/services.dart';

import 'prefs.dart';

/// Мост к нативному [ScreenReaderService] (Android AccessibilityService).
///
/// Зачем: когда мини-окно Ады открыто поверх мессенджера, Ада должна
/// «видеть» переписку на экране и уметь подсказать ответ собеседнику.
/// Сервис читает ТЕКСТ активного окна другого приложения и держит свежий
/// снимок в памяти. Ничего не пишется на диск и никуда не отправляется
/// само по себе — текст уходит только в промпт при отправке сообщения.
abstract final class ScreenReaderService {
  static const MethodChannel _ch = MethodChannel(
    'com.wetidom.keramika/screen_reader',
  );

  /// Выключатель в настройках. Сохраняется отдельно от системного
  /// разрешения: выдача/отзыв разрешения не сбрасывает пользовательский
  /// выбор. Без разрешения функция просто временно не читает экран.
  static const String prefKey = 'setting_screen_aware';

  static bool? _hasPermCache;

  static void clearPermissionCache() => _hasPermCache = null;

  static Future<bool> isEnabledPref() async =>
      globalPrefs.getBool(prefKey) ?? false;

  static Future<void> setEnabledPref(bool value) async {
    await globalPrefs.setBool(prefKey, value);
    _hasPermCache = null;
  }

  /// Выдано ли системное разрешение «Специальные возможности».
  static Future<bool> hasPermission() async {
    if (_hasPermCache != null) return _hasPermCache!;
    try {
      _hasPermCache = await _ch.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      _hasPermCache = false;
    }
    return _hasPermCache!;
  }

  /// Открывает системный экран «Специальные возможности».
  static Future<void> openSystemSettings() async {
    try {
      await _ch.invokeMethod('openAccessibilitySettings');
      // Разрешение могло появиться/исчезнуть — сбрасываем кэш.
      _hasPermCache = null;
    } catch (_) {}
  }

  /// Свежий снимок текста экрана ('' — если нет разрешения/выключено/
  /// снимок устарел или пуст). Данные давностью больше ~10 минут считаем
  /// неактуальными: лучше без контекста, чем с чужим старым текстом.
  static Future<String> snapshot({int maxChars = 3200}) async {
    try {
      if (!(await isEnabledPref())) return '';
      if (!(await hasPermission())) return '';
      final res = await _ch.invokeMethod<Map<Object?, Object?>>(
        'getScreenText',
      );
      if (res == null) return '';
      final at = (res['at'] as num?)?.toInt() ?? 0;
      final ageMs = DateTime.now().millisecondsSinceEpoch - at;
      if (ageMs < 0 || ageMs > 10 * 60 * 1000) return '';
      final text = (res['text'] as String?) ?? '';
      if (text.isEmpty) return '';
      return text.length <= maxChars ? text : text.substring(0, maxChars);
    } catch (_) {
      // Канал недоступен (web/ошибки движка) — просто работаем без контекста.
      return '';
    }
  }
}
