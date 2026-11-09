import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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

/// Итог установки, который система вернула после коммита сессии
/// `PackageInstaller` (значения `PackageInstaller.STATUS_*`).
class InstallOutcome {
  const InstallOutcome({required this.status, this.message});

  final int status;
  final String? message;

  /// Установка прошла — приложение обновилось.
  bool get isSuccess => status == 0;

  /// Пользователь отказался от установки (закрыл системный экран).
  bool get isAborted => status == 3;

  /// Система заблокировала установку (политика, Play Protect и т. п.).
  bool get isBlocked => status == 2;

  /// Любой провал, кроме «пользователь передумал»: показываем как ошибку.
  bool get isFailure => !isSuccess && !isAborted;
}

/// Тонкая обёртка над нативным каналом `com.wetidom.keramika/updater`.
///
/// Канал умеет ровно то, что нельзя сделать в Dart без лишних зависимостей:
///  * отдать versionCode/versionName установленного APK;
///  * отдать ABI устройства (какой APK качать из релиза);
///  * проверить и запустить установку скачанного APK через сессию
///    `PackageInstaller` (доверенное самообновление, а не сторонний
///    установщик — см. MainActivity.installViaSession);
///  * вернуть итог установки, который приходит асинхронно.
class Installer {
  Installer._();

  static const MethodChannel _channel = MethodChannel(
    'com.wetidom.keramika/updater',
  );

  static bool get _supported =>
      debugForceSupported || (!kIsWeb && Platform.isAndroid);

  /// Тестовый шов: в юнит-тестах нет Android, поэтому `_supported` иначе
  /// всегда false, и весь путь приёма итога установки остаётся непокрытым.
  @visibleForTesting
  static bool debugForceSupported = false;

  /// Тестовый шов: сбрасывает состояние между тестами (слушатель, поток).
  @visibleForTesting
  static void resetForTesting() {
    _listening = false;
    debugForceSupported = false;
    _outcomes = StreamController<InstallOutcome>.broadcast();
  }

  /// Поток итогов установки. Натив отдаёт их двумя путями: push-вызовом
  /// `onInstallResult` (приложение на экране) и pull-методом
  /// `consumeInstallResult` (процесс перезапустился после установки) —
  /// здесь оба сливаются в один поток для интерфейса.
  static StreamController<InstallOutcome> _outcomes =
      StreamController<InstallOutcome>.broadcast();

  static bool _listening = false;

  static Stream<InstallOutcome> get outcomes => _outcomes.stream;

  /// Начинает слушать итоги установки. Идемпотентно: повторный вызов ничего
  /// не делает. Первым делом забирает придержанный результат — он мог
  /// появиться до подписки (см. UpdaterBridge.consume на нативной стороне).
  static void listen() {
    if (_listening || !_supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onInstallResult') {
        _emit(_parse(call.arguments));
      }
    });
    // Не ждём ответа — если он есть, придёт тем же потоком.
    unawaited(consumePending());
  }

  /// Забирает придержанный нативной стороной результат (если был).
  static Future<void> consumePending() async {
    if (!_supported) return;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'consumeInstallResult',
      );
      if (map != null) _emit(_parse(map));
    } catch (_) {}
  }

  static InstallOutcome? _parse(dynamic raw) {
    if (raw is! Map) return null;
    final status = (raw['status'] as num?)?.toInt();
    if (status == null) return null;
    return InstallOutcome(
      status: status,
      message: raw['message'] as String?,
    );
  }

  static void _emit(InstallOutcome? outcome) {
    if (outcome == null || _outcomes.isClosed) return;
    _outcomes.add(outcome);
  }

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

  /// Запускает установку APK через сессию PackageInstaller (доверенное
  /// самообновление). [expectedSha256] (hex) — если задан, нативная сторона
  /// сверит хеш файла и откажет при несовпадении. Итог установки приходит
  /// асинхронно в [outcomes].
  static Future<bool> installApk(String path, {String? expectedSha256}) async {
    if (!_supported ||
        expectedSha256 == null ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(expectedSha256)) {
      return false;
    }
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
