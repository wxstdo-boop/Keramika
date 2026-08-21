import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import '../services/prefs.dart';

const _package = 'com.wetidom.keramika';

// Канал для скрытия содержимого приложения из «недавних» при установленном PIN.
const _secureChannel = MethodChannel('com.wetidom.keramika/secure');

// Канал проверки полноэкранных уведомлений (поверх блокировки).
const _fullscreenChannel = MethodChannel('com.wetidom.keramika/fullscreen');

// Слушатель смены PIN-режима: main.dart через него включает/выключает
// размытие содержимого в «недавних» (снимок экрана при уходе в фон).
void Function(bool secure)? _onSecureChanged;

/// Регистрирует слушатель смены PIN-режима. Вызывается один раз из
/// KeramikaAppState, чтобы размытие в «недавних» знало, когда PIN активен.
void setSecureChangedListener(void Function(bool secure) listener) {
  _onSecureChanged = listener;
}

/// Проверяет, выдано ли уже разрешение полноэкранных уведомлений
/// (full-screen notifications / поверх блокировки).
/// API 34+: NotificationManager.canUseFullScreenIntent().
/// Старые API / MIUI: Settings.canDrawOverlays() (SYSTEM_ALERT_WINDOW).
/// Если проверить не удалось — возвращаем false, чтобы настройки
/// открылись (консервативное поведение, как раньше).
Future<bool> canUseFullScreenIntent() async {
  if (!_isAndroid) return true;
  try {
    final ok = await _fullscreenChannel.invokeMethod<bool>(
      'canUseFullScreenIntent',
    );
    return ok ?? false;
  } catch (_) {
    return false;
  }
}

/// Включает/выключает PIN-режим (размытие содержимого в «недавних»).
/// При установленном PIN телефон в переключателе задач показывает красиво
/// размытый снимок приложения вместо содержимого или пустой заглушки.
/// Размытие делает сам Flutter (снимок + оверлей при уходе в фон), поэтому
/// на нативную сторону уходит только сигнал — там FLAG_SECURE больше
/// не ставится (он давал чёрную заглушку и блокировал скриншоты).
Future<void> setSecureWindow(bool secure) async {
  _onSecureChanged?.call(secure);
  if (!_isAndroid) return;
  try {
    await _secureChannel.invokeMethod('setSecure', {'secure': secure});
  } catch (_) {}
}

/// defaultTargetPlatform не бросает на web, в отличие от dart:io Platform,
/// поэтому проверка безопасна на всех платформах.
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Открывает НАСТРОЙКИ УВЕДОМЛЕНИЙ именно этого приложения
/// (НЕ батарею!). Используется, когда пользователю нужно включить
/// уведомления — например из диагностики «Тест уведомления».
Future<bool> openNotificationSettingsAndroid() async {
  if (!_isAndroid) return false;
  // Системный экран открыт — PIN-размытие в «недавних» не показываем,
  // чтобы оно не «прыгало» при переходе к системным настройкам.
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  try {
    await AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{
        'android.provider.extra.APP_PACKAGE': _package,
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false; // ни один интент не открылся — снимаем пометку
  return false;
}

/// Opens battery optimization settings.
Future<bool> openAppSettingsAndroid() async {
  if (!_isAndroid) return false;
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  try {
    await AndroidIntent(
      action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{
        'android.provider.extra.APP_PACKAGE': _package,
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false;
  return false;
}

/// Opens MIUI / HyperOS autostart settings.
Future<bool> openAutostartSettings() async {
  if (!_isAndroid) return false;
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  try {
    await AndroidIntent(
      action: 'miui.intent.action.OP_AUTO_START',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.autostart.AutoStartManagementActivity',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.huawei.systemmanager',
      componentName:
          'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false;
  return false;
}

/// Opens "Full-screen notifications" settings for MIUI / HyperOS.
/// This is the key setting that allows fullScreenIntent to work.
Future<bool> openFullScreenNotifSettings() async {
  if (!_isAndroid) return false;
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  // MIUI: Settings → Apps → [App] → Permissions → Full-screen notifications.
  try {
    await AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: <String, dynamic>{'extra_pkgname': _package},
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // MIUI: Settings → Apps → [App] → Permissions → Show pop-up windows.
  try {
    await AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: <String, dynamic>{
        'extra_pkgname': _package,
        'extra_permission': 'android.permission.SYSTEM_ALERT_WINDOW',
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // Standard Android: notification settings.
  try {
    await AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{
        'android.provider.extra.APP_PACKAGE': _package,
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // Fallback: app info → notifications.
  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false;
  return false;
}

/// Opens "Display over other apps" permission.
Future<bool> openOverlaySettings() async {
  if (!_isAndroid) return false;
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  try {
    await AndroidIntent(
      action: 'android.settings.MANAGE_OVERLAY_PERMISSION',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false;
  return false;
}

/// Открывает настройки точных будильников ДЛЯ ЭТОГО ПРИЛОЖЕНИЯ.
///
/// Цепочка fallback (по приоритету):
///   1. android.settings.REQUEST_SCHEDULE_EXACT_ALARM (API 31+) с
///      data: 'package:com.wetidom.keramika' — системный экран
///      «Будильники и напоминания» именно для нашего приложения.
///      Если пользователь уже отказал и permission denied — система
///      молча не откроет диалог; в этом случае идём дальше.
///   2. android.settings.APP_NOTIFICATION_SETTINGS с
///      android.provider.extra.APP_PACKAGE = наш пакет — это экран
///      уведомлений именно нашего приложения (там есть отдельный
///      подраздел «Будильники и напоминания»). Открывается НА Android
///      8+ надёжно, даже если первый шаг провалился.
///   3. android.settings.APPLICATION_DETAILS_SETTINGS с
///      data: 'package:com.wetidom.keramika' — ГАРАНТИРОВАННЫЙ финальный
///      fallback: открывает детали именно нашего приложения, не общий
///      список. Если ни один из верхних шагов не сработал — пользователь
///      хотя бы увидит карточку приложения в системных настройках.
///
/// Возвращает true, если удалось запустить хотя бы один из интентов —
/// тогда _askedAtKey можно безопасно проставлять. false — если всё
/// провалилось (тогда НЕ ставим метку, чтобы следующая попытка снова
/// попробовала открыть настройки).
Future<bool> openExactAlarmSettings() async {
  if (!_isAndroid) return false;
  systemUiActive = true;
  final n = [Flag.FLAG_ACTIVITY_NEW_TASK];

  // 1. Системный экран точных будильников именно для нашего пакета.
  //    Пробуем с data package — на Xiaomi/Redmi/HyperOS это часто
  //    единственный способ открыть переключатель для конкретного приложения.
  try {
    await AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // 1b. Без data (AOSP), если с data не сработало.
  try {
    await AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // 1c. Xiaomi/HyperOS: редактор разрешений приложения.
  try {
    await AndroidIntent(
      action: 'miui.intent.action.APP_PERM_EDITOR',
      package: 'com.miui.securitycenter',
      componentName:
          'com.miui.permcenter.permissions.PermissionsEditorActivity',
      arguments: <String, dynamic>{
        'extra_pkgname': _package,
        'extra_permission': 'android.permission.SCHEDULE_EXACT_ALARM',
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // 2. Настройки уведомлений именно нашего приложения.
  //    Здесь по Android 8+ всегда корректно открывается per-app экран,
  //    в котором есть подраздел «Будильники и напоминания».
  try {
    await AndroidIntent(
      action: 'android.settings.APP_NOTIFICATION_SETTINGS',
      arguments: <String, dynamic>{
        'android.provider.extra.APP_PACKAGE': _package,
      },
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  // 3. Детальные настройки приложения — ГАРАНТИРОВАННЫЙ fallback: точно
  //    откроется наша карточка приложения в системных настройках, а не
  //    какой-либо общий список.
  try {
    await AndroidIntent(
      action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
      data: 'package:$_package',
      flags: n,
    ).launch();
    return true;
  } catch (_) {}

  systemUiActive = false;
  return false;
}
