import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Ответ GitHub с кодом != 2xx. Текст от GitHub информативнее любой
/// обёртки («Bad credentials», «Not Found»), поэтому показываем его как есть.
class ForgeException implements Exception {
  ForgeException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  /// Токен не подходит или отозван — UI подсвечивает поле токена,
  /// а не показывает общую сетевую ошибку.
  bool get isAuth => statusCode == 401;

  /// Не хватает прав: у fine-grained токена нет нужного доступа к репозиторию.
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;
}

class ForgeFile {
  const ForgeFile({
    required this.path,
    required this.content,
    required this.sha,
  });

  final String path;
  final String content;
  final String sha;
}

class ForgeEntry {
  const ForgeEntry({required this.path, required this.isDir});

  final String path;
  final bool isDir;
}

class ForgeBranch {
  const ForgeBranch({required this.name, required this.sha});

  final String name;
  final String sha;
}

/// Хранилище токена за интерфейсом: боевой путь кладёт его в Keystore,
/// тесты подставляют память — без моков плагина и без записи в реальный
/// Keystore при прогоне тестов.
abstract class ForgeTokenStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureForgeTokenStore implements ForgeTokenStore {
  static const _key = 'forge_github_token';

  // resetOnError: false — иначе плагин молча стирает токен при сбое
  // Keystore, и это выглядит как «токен не сохраняется».
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );

  const SecureForgeTokenStore();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

@visibleForTesting
class InMemoryForgeTokenStore implements ForgeTokenStore {
  String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async => _value = value;

  @override
  Future<void> delete() async => _value = null;
}

/// Правки репозитория из «Кузницы»: токен в защищённом хранилище плюс
/// минимальный набор операций GitHub REST, нужный агенту (чтение и запись
/// файлов, ветки, pull request).
class ForgeService {
  ForgeService({http.Client? client, ForgeTokenStore? store})
    : _client = client ?? http.Client(),
      _store = store ?? const SecureForgeTokenStore();

  static const api = 'https://api.github.com';

  /// Потолок размера файла, который тянем в контекст агента: содержимое
  /// уходит в промпт, и мегабайтные ассеты выжигают окно и лимиты.
  static const maxFileBytes = 200 * 1024;

  final http.Client _client;
  final ForgeTokenStore _store;

  Future<String?> loadToken() async {
    final raw = await _store.read();
    final trimmed = raw?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> saveToken(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _store.delete();
      return;
    }
    await _store.write(trimmed);
  }

  Future<void> clearToken() => _store.delete();

  /// Проверка токена и заодно логин владельца — показываем его в экране,
  /// чтобы было видно, чей токен вставлен.
  Future<String> verifyToken(String token) async {
    final body = await _get('/user', token: token);
    final login = (body as Map<String, dynamic>)['login'];
    return login is String && login.isNotEmpty ? login : 'unknown';
  }

  /// Токен с доступом на запись: GitHub отвечает `permissions.push`.
  Future<bool> canPush(String owner, String repo, {String? token}) async {
    final t = token ?? await loadToken();
    if (t == null) return false;
    final body =
        await _get('/repos/$owner/$repo', token: t) as Map<String, dynamic>;
    final perms = body['permissions'];
    if (perms is Map && perms['push'] == true) return true;
    // Права не отдаются для репозиториев, где токен лишь читатель, и для
    // части публичных репо: отсутствие push трактуем как «нельзя писать».
    return false;
  }

  Future<String> defaultBranch(String owner, String repo, {String? token}) async {
    final t = token ?? await loadToken();
    final body =
        await _get('/repos/$owner/$repo', token: t) as Map<String, dynamic>;
    return (body['default_branch'] as String?) ?? 'main';
  }

  Future<List<ForgeEntry>> listDirectory(
    String owner,
    String repo,
    String path, {
    String? ref,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final query = ref == null ? '' : '?ref=${Uri.encodeQueryComponent(ref)}';
    final clean = path.replaceAll(RegExp(r'^/+|/+$'), '');
    final body = await _get(
      '/repos/$owner/$repo/contents/$clean$query',
      token: t,
    );
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic> && item['path'] is String)
          ForgeEntry(
            path: item['path'] as String,
            isDir: item['type'] == 'dir',
          ),
    ];
  }

  Future<ForgeFile?> readFile(
    String owner,
    String repo,
    String path, {
    String? ref,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final query = ref == null ? '' : '?ref=${Uri.encodeQueryComponent(ref)}';
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    final body = await _get(
      '/repos/$owner/$repo/contents/$clean$query',
      token: t,
      allowNotFound: true,
    );
    if (body == null) return null;
    if (body is! Map<String, dynamic>) return null;
    final content = body['content'];
    if (content is! String) return null;
    // GitHub отдаёт base64 с переводами строк — декодер на них падает.
    final normalized = content.replaceAll(RegExp(r'\s'), '');
    final bytes = base64.decode(normalized);
    if (bytes.length > maxFileBytes) {
      throw ForgeException(
        413,
        'Файл больше ${maxFileBytes ~/ 1024} КБ — агент его не читает',
      );
    }
    return ForgeFile(
      path: (body['path'] as String?) ?? path,
      content: utf8.decode(bytes, allowMalformed: true),
      sha: (body['sha'] as String?) ?? '',
    );
  }

  /// Запись файла в ветку. `sha` нужен только при обновлении существующего
  /// файла — без него GitHub отвечает 409 на повторную запись.
  Future<void> writeFile(
    String owner,
    String repo,
    String path, {
    required String content,
    required String message,
    required String branch,
    String? sha,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final clean = path.replaceAll(RegExp(r'^/+'), '');
    await _send(
      'PUT',
      '/repos/$owner/$repo/contents/$clean',
      token: t,
      payload: {
        'message': message,
        'content': base64.encode(utf8.encode(content)),
        'branch': branch,
        if (sha != null && sha.isNotEmpty) 'sha': sha,
      },
    );
  }

  Future<ForgeBranch> branchHead(
    String owner,
    String repo,
    String branch, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body =
        await _get('/repos/$owner/$repo/git/ref/heads/$branch', token: t)
            as Map<String, dynamic>;
    final object = body['object'];
    final sha = object is Map ? object['sha'] as String? : null;
    if (sha == null) {
      throw ForgeException(500, 'Не удалось прочитать ветку $branch');
    }
    return ForgeBranch(name: branch, sha: sha);
  }

  /// Создание рабочей ветки от `from`. Уже существующая ветка — не ошибка:
  /// агент может продолжать работу в ней после повторного запуска.
  Future<ForgeBranch> createBranch(
    String owner,
    String repo, {
    required String name,
    required String from,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final base = await branchHead(owner, repo, from, token: t);
    try {
      await _send(
        'POST',
        '/repos/$owner/$repo/git/refs',
        token: t,
        payload: {'ref': 'refs/heads/$name', 'sha': base.sha},
      );
    } on ForgeException catch (e) {
      if (e.statusCode != 422) rethrow; // 422 = ветка уже есть
    }
    return branchHead(owner, repo, name, token: t);
  }

  Future<List<String>> listBranches(
    String owner,
    String repo, {
    String? token,
  }) async {
    final t = token ?? await loadToken();
    final body = await _get('/repos/$owner/$repo/branches', token: t);
    if (body is! List) return const [];
    return [
      for (final item in body)
        if (item is Map<String, dynamic> && item['name'] is String)
          item['name'] as String,
    ];
  }

  /// Открыть pull request. Если PR для этой пары веток уже есть, GitHub
  /// отвечает 422 — возвращаем существующий, чтобы повторный запуск
  /// агента не падал.
  Future<String> openPullRequest(
    String owner,
    String repo, {
    required String title,
    required String body,
    required String head,
    required String base,
    String? token,
  }) async {
    final t = token ?? await loadToken();
    try {
      final created =
          await _send(
                'POST',
                '/repos/$owner/$repo/pulls',
                token: t,
                payload: {
                  'title': title,
                  'body': body,
                  'head': head,
                  'base': base,
                },
              )
              as Map<String, dynamic>;
      return (created['html_url'] as String?) ?? '';
    } on ForgeException catch (e) {
      if (e.statusCode != 422) rethrow;
      final existing = await _get(
        '/repos/$owner/$repo/pulls?state=open&head=$owner:$head',
        token: t,
      );
      if (existing is List && existing.isNotEmpty) {
        final first = existing.first;
        if (first is Map<String, dynamic>) {
          return (first['html_url'] as String?) ?? '';
        }
      }
      rethrow;
    }
  }

  Map<String, String> _headers(String? token) => {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    // GitHub отвечает 403 без User-Agent.
    'User-Agent': 'Keramika-Forge',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> _get(
    String path, {
    String? token,
    bool allowNotFound = false,
  }) async {
    final resp = await _client
        .get(Uri.parse('$api$path'), headers: _headers(token))
        .timeout(const Duration(seconds: 25));
    return _decode(resp, allowNotFound: allowNotFound);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    required Map<String, dynamic> payload,
    String? token,
  }) async {
    final req = http.Request(method, Uri.parse('$api$path'))
      ..headers.addAll({..._headers(token), 'Content-Type': 'application/json'})
      ..body = jsonEncode(payload);
    final streamed = await _client
        .send(req)
        .timeout(const Duration(seconds: 25));
    final resp = await http.Response.fromStream(streamed);
    return _decode(resp);
  }

  dynamic _decode(http.Response resp, {bool allowNotFound = false}) {
    if (resp.statusCode == 404 && allowNotFound) return null;
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    if (ok) {
      if (resp.body.isEmpty) return null;
      return jsonDecode(utf8.decode(resp.bodyBytes));
    }
    String message = 'GitHub ${resp.statusCode}';
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      }
    } catch (_) {
      // Тело не JSON (страница ошибки прокси) — оставляем код.
    }
    throw ForgeException(resp.statusCode, message);
  }
}
