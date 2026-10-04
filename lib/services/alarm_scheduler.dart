import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';

class AlarmScheduler {
  static const _channel = MethodChannel('com.wetidom.keramika/alarm_scheduler');

  // defaultTargetPlatform безопасен на web (не бросает, как dart:io Platform).
  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> scheduleAlarmClock({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    required String soundName,
    required bool vibrate,
    required DateTime fireTime,
    required int hour,
    required int minute,
    String repeatDays = '',
    String payload = '',
    bool fullscreen = true,
    String? customSoundPath,
  }) async {
    if (!_isAndroid) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('scheduleAlarmClock', {
        'id': id,
        'title': title,
        'body': body,
        'channelId': channelId,
        'channelName': channelName,
        'soundName': soundName,
        'vibrate': vibrate,
        'fireTimestamp': fireTime.millisecondsSinceEpoch,
        'payload': payload,
        'fullscreen': fullscreen,
        'hour': hour,
        'minute': minute,
        'repeatDays': repeatDays,
        'customSoundPath': customSoundPath,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> cancelAlarmClock(int id) async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('cancelAlarmClock', {
        'id': id,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Когда по мнению системы должен сработать ближайший взведённый
  /// будильник (`AlarmManager.getNextAlarmClock`). 0 — не взведено ничего.
  /// Единственный способ из приложения проверить, что постановка реально
  /// дошла до AlarmManager.
  static Future<int> nextAlarmTime() async {
    if (!_isAndroid) return 0;
    try {
      final result = await _channel.invokeMethod<int>('nextAlarmTime');
      return result ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<bool> isAvailable() async {
    if (!_isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAlarmClockApiAvailable',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Запрашивает системное разрешение на полноэкранные уведомления
  /// (USE_FULL_SCREEN_INTENT, Android 14+). Без него fullScreenIntent
  /// тихо деградирует в обычное уведомление в шторке — будильник
  /// приходит, но экран блокировки не будит и не показывает WakeTask.
  ///
  /// Системного ДИАЛОГА для этого права нет (в отличие от обычных
  /// runtime-разрешений): нативный код открывает экран специального
  /// доступа, где пользователь включает тумблер. Если право уже выдано —
  /// ничего не открывает и возвращает false.
  /// На Android < 14 право выдаётся автоматически — диалог не нужен.
  /// На не-Android: возвращает true.
  static Future<bool> requestFullScreenIntent() async {
    if (!_isAndroid) return true;
    try {
      final result = await MethodChannel(
        'com.wetidom.keramika/fullscreen',
      ).invokeMethod<bool>('requestUseFullScreenIntent');
      return result ?? true;
    } catch (_) {
      // Канал не зарегистрирован (старый билд) — не блокируем планирование.
      return true;
    }
  }

  /// Проверяет, сняты ли ограничения на батарею (battery optimization выключен).
  /// true — ограничений нет, будильники не будут убиты в фоне.
  /// На не-Android возвращает true (проверять нечего).
  static Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Проверяет, дано ли системное разрешение на точные будильники
  /// (SCHEDULE_EXACT_ALARM). Работает на Android 12+ (API 31+).
  /// На старых версиях и на не-Android возвращает true (разрешение не требуется).
  static Future<bool> canScheduleExactAlarms() async {
    if (!_isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>(
        'canScheduleExactAlarms',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }
}
