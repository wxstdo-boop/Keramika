import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'installer.dart';
import 'prefs.dart';

/// Репозиторий, из релизов которого приложение берёт обновления.
const String kUpdateRepoOwner = 'wxstdo-boop';
const String kUpdateRepoName = 'Keramika';

/// Описание доступного обновления из последнего GitHub-релиза.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String downloadUrl;

  /// SHA-256 (hex, нижний регистр) — из поля `digest` ассета GitHub.
  final String sha256;
  final int size;
  final String notes;
}

/// Найденное обновление (или null): таблетка в Настройках слушает реактивно.
final ValueNotifier<UpdateInfo?> pendingUpdate = ValueNotifier<UpdateInfo?>(
  null,
);

/// Автообновление через GitHub Releases.
///
/// Источник истины — `releases/latest` публичного репозитория. GitHub сам
/// отдаёт aссеты, их размеры и SHA-256 (`digest`), поэтому отдельный манифест
/// не нужен. Тег релиза — `v<versionName>+<versionCode>` (как в pubspec).
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const Duration _minInterval = Duration(hours: 24);
  static const String _lastCheckKey = 'update_last_check_ms';

  /// Проверяет последний релиз на GitHub. Возвращает [UpdateInfo], только
  /// если версия в релизе строго новее [currentVersionCode].
  Future<UpdateInfo?> check({
    required String abi,
    required int currentVersionCode,
  }) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$kUpdateRepoOwner/$kUpdateRepoName/releases/latest',
    );
    final res = await http.get(
      uri,
      headers: const {
        // GitHub требует User-Agent, иначе отдаёт 403.
        'User-Agent': 'Keramika',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    // Тег релиза: `v1.6.46+37120` (versionName + versionCode).
    final match = RegExp(r'v?(\d+(?:\.\d+)*)\+(\d+)').firstMatch(tag);
    if (match == null) return null;
    final versionCode = int.tryParse(match.group(2)!) ?? 0;
    if (versionCode <= currentVersionCode) return null;

    final assets =
        (json['assets'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final abiLower = abi.toLowerCase();
    Map<String, dynamic>? apk;
    for (final a in assets) {
      final name = (a['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') && name.contains(abiLower)) {
        apk = a;
        break;
      }
    }
    // Если точного ABI нет — берём первый APK (например, universal-сборку).
    apk ??= assets.firstWhere(
      (a) => (a['name'] as String? ?? '').toLowerCase().endsWith('.apk'),
      orElse: () => const <String, dynamic>{},
    );
    final url = apk['browser_download_url'] as String?;
    if (url == null || url.isEmpty) return null;

    final digest = (apk['digest'] as String? ?? '').toLowerCase();
    final sha = digest.startsWith('sha256:')
        ? digest.substring('sha256:'.length)
        : '';

    return UpdateInfo(
      versionCode: versionCode,
      versionName: match.group(1) ?? tag,
      downloadUrl: url,
      sha256: sha,
      size: (apk['size'] as num?)?.toInt() ?? 0,
      notes: (json['body'] as String?) ?? '',
    );
  }

  /// Скачивает APK во временный каталог. Возвращает путь к файлу или null.
  Future<String?> download(
    UpdateInfo info, {
    ValueChanged<double>? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/keramika-${info.versionName}.apk');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(info.downloadUrl));
      req.headers['User-Agent'] = 'Keramika';
      final res = await client.send(req);
      if (res.statusCode != 200) return null;
      final total = res.contentLength ?? info.size;
      var received = 0;
      final sink = file.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress((received / total).clamp(0.0, 1.0));
        }
      }
      await sink.flush();
      await sink.close();
      return file.path;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Тихая проверка раз в сутки при старте: БЕЗ диалогов, только наполняет
  /// [pendingUpdate], чтобы таблетка в Настройках сразу знала про обновление.
  Future<void> silentDailyCheck() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = globalPrefs.getInt(_lastCheckKey) ?? 0;
      if (now - last < _minInterval.inMilliseconds) return;
      final info = await Installer.appInfo();
      if (info == null) return;
      final abi = await Installer.supportedAbi();
      final update = await check(abi: abi, currentVersionCode: info.versionCode);
      // Метку пишем даже при отсутствии обновления — иначе долбим API зря.
      await globalPrefs.setInt(_lastCheckKey, now);
      pendingUpdate.value = update;
    } catch (_) {
      // Нет сети / лимит API — молча выходим, повторим в следующий запуск.
    }
  }
}
