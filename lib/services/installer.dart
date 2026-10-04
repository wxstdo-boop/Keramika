import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// Информация о собственной сборке — версия из Android-манифеста.
class InstalledAppInfo {
  const InstalledAppInfo({
    required this.versionCode,
    required this.versionName,
  });

  final int versionCode;
  final String versionName;
}

/// Тонкая обёртка над нативным каналом `com.wetidom.keramika/updater`.
///
/// Канал умеет ровно то, что нельзя сделать в Dart без лишних зависимостей:
///  * отдать versionCode/versionName установленного APK;
///  * отдать ABI устройства (какой APK качать из релиза);
///  * проверить и запустить установку скачанного APK (FileProvider + интент).
class Installer {
  Installer._();

  static const MethodChannel _channel = MethodChannel(
    'com.wetidom.keramika/updater',
  );

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Версия установленного приложения. На не-Android — null.
  static Future<InstalledAppInfo?> appInfo() async {
    if (!_supported) return null;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('appInfo');
      if (map == null) return null;
      return InstalledAppInfo(
        versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
        versionName: map['versionName'] as String? ?? '0',
      );
    } catch (_) {
      return null;
    }
  }

  /// ABI устройства, например `arm64-v8a`. По нему выбирается APK релиза.
  static Future<String> supportedAbi() async {
    if (!_supported) return 'arm64-v8a';
    try {
      return await _channel.invokeMethod<String>('supportedAbi') ??
          'arm64-v8a';
    } catch (_) {
      return 'arm64-v8a';
    }
  }

  /// Разрешена ли установка приложений из этого источника (Android 8+).
  static Future<bool> canInstall() async {
    if (!_supported) return true;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Открывает системные настройки «Установка неизвестных приложений».
  static Future<void> openInstallSettings() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } catch (_) {}
  }

  /// Запускает системную установку APK. [expectedSha256] (hex) — если задан,
  /// нативная сторона сверит хеш файла и откажет при несовпадении.
  static Future<bool> installApk(String path, {String? expectedSha256}) async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('installApk', {
            'path': path,
            'sha256': expectedSha256,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
