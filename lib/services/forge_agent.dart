import 'dart:convert';

import 'package:http/http.dart' as http;

import 'forge_service.dart';

/// Вызов инструмента, который вернула модель.
class ForgeToolCall {
  const ForgeToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// Ответ модели: либо текст, либо список вызовов инструментов.
class ForgeChatReply {
  const ForgeChatReply({this.text, this.toolCalls = const []});

  final String? text;
  final List<ForgeToolCall> toolCalls;
}

/// Диалог с моделью. Вынесен за интерфейс, чтобы цикл агента можно было
/// прогнать детерминированно: настоящая модель — внешний нестабильный
/// сервис, и проверять на ней логику цикла нельзя.
abstract class ForgeChat {
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  );
}

/// Шаг работы агента — для живого лога в экране.
class ForgeStep {
  const ForgeStep({required this.tool, required this.detail, this.ok = true});

  final String tool;
  final String detail;
  final bool ok;
}

class ForgeRunResult {
  const ForgeRunResult({
    required this.branch,
    required this.summary,
    this.pullRequestUrl,
    this.filesChanged = 0,
  });

  final String branch;
  final String summary;
  final String? pullRequestUrl;
  final int filesChanged;
}

/// ИИ-агент «Кузницы»: правит репозиторий настоящими коммитами.
///
/// Работает в отдельной ветке от базовой и открывает pull request — прямая
/// запись в `main` с телефона слишком легко ломает рабочее приложение, а PR
/// даёт возможность посмотреть diff и откатить.
class ForgeAgent {
  ForgeAgent({
    required this.service,
    required this.chat,
    required this.owner,
    required this.repo,
  });

  final ForgeService service;
  final ForgeChat chat;
  final String owner;
  final String repo;

  /// Потолок шагов: каждая итерация — это сетевой запрос к модели и к
  /// GitHub, а платим за это лимитами. Двенадцати хватает на «прочитал три
  /// файла, поправил два, открыл PR».
  static const maxSteps = 12;

  /// Сколько файлов агент может изменить за один прогон. Ограничение ловит
  /// разбушевавшуюся модель до того, как она перепишет весь проект.
  static const maxWrites = 8;

  /// Пути, которые агенту закрыты: секреты подписи и локальные настройки.
  /// Токен GitHub лежит в защищённом хранилище, но подписной ключ и пароли
  /// в репозитории — прямая утечка, а `.env`/`key.properties` в истории
  /// и так уже были проблемой.
  static bool isBlockedPath(String path) {
    final p = path.toLowerCase().replaceAll('\\', '/');
    if (p.contains('..')) return true;
    if (p.startsWith('/')) return true;
    const blocked = [
      'key.properties',
      '.jks',
      '.keystore',
      '.env',
      'id_rsa',
      '.p12',
      '.pem',
    ];
    return blocked.any(p.contains);
  }

  List<Map<String, dynamic>> _tools() => [
    {
      'type': 'function',
      'function': {
        'name': 'list_dir',
        'description': 'Показать файлы и папки каталога в репозитории.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Путь каталога, например lib/screens. Пусто — корень.',
            },
          },
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description': 'Прочитать файл из репозитория.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
          },
          'required': ['path'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_file',
        'description':
            'Записать файл в рабочую ветку. Указывай ПОЛНОЕ содержимое файла, не фрагмент.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'content': {
              'type': 'string',
              'description': 'Полное новое содержимое файла.',
            },
            'message': {
              'type': 'string',
              'description': 'Короткое сообщение коммита.',
            },
          },
          'required': ['path', 'content'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'finish',
        'description':
            'Закончить работу и открыть pull request. Вызывай, когда правки готовы.',
        'parameters': {
          'type': 'object',
          'properties': {
            'summary': {
              'type': 'string',
              'description': 'Что сделано — 1-3 предложения для описания PR.',
            },
            'title': {
              'type': 'string',
              'description': 'Заголовок pull request.',
            },
          },
          'required': ['summary'],
        },
      },
    },
  ];

  /// Прогон задачи. Возвращает результат либо бросает [ForgeException].
  Future<ForgeRunResult> run({
    required String task,
    required String baseBranch,
    String languageCode = 'ru',
    void Function(ForgeStep step)? onStep,
  }) async {
    final branch = 'forge/${_slug(task)}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    await service.createBranch(
      owner,
      repo,
      name: branch,
      from: baseBranch,
    );

    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(languageCode)},
      {'role': 'user', 'content': task},
    ];
    final tools = _tools();
    var writes = 0;
    final changed = <String>{};

    for (var step = 0; step < maxSteps; step++) {
      final reply = await chat.complete(messages, tools);
      if (reply.toolCalls.isEmpty) {
        // Модель ответила текстом, не позвав инструменты: если правки уже
        // есть — доводим до PR, иначе это пустой прогон.
        if (changed.isEmpty) {
          throw ForgeException(500, reply.text ?? 'Агент ничего не изменил');
        }
        return _openPr(
          branch: branch,
          base: baseBranch,
          task: task,
          summary: reply.text ?? 'Правки от Кузницы',
          files: changed,
        );
      }

      messages.add({
        'role': 'assistant',
        'content': reply.text,
        'tool_calls': [
          for (final call in reply.toolCalls)
            {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
      });

      for (final call in reply.toolCalls) {
        if (call.name == 'finish') {
          final summary = _str(call.arguments['summary']) ?? 'Правки от Кузницы';
          if (changed.isEmpty) {
            throw ForgeException(500, 'Агент завершил работу без правок');
          }
          return _openPr(
            branch: branch,
            base: baseBranch,
            task: task,
            title: _str(call.arguments['title']),
            summary: summary,
            files: changed,
          );
        }

        String result;
        var ok = true;
        // Предохранитель, а не подсказка модели: если она упорно пишет
        // сверх лимита, прогон останавливаем — иначе один запуск может
        // переписать весь проект.
        if (call.name == 'write_file' && writes >= maxWrites) {
          throw ForgeException(
            429,
            'Достигнут предел правок ($maxWrites) за прогон',
          );
        }
        try {
          result = await _execute(call, branch);
          if (call.name == 'write_file') {
            writes++;
            final p = _str(call.arguments['path']);
            if (p != null) changed.add(p);
          }
        } on ForgeException catch (e) {
          ok = false;
          result = 'Ошибка: ${e.message}';
        }
        onStep?.call(
          ForgeStep(
            tool: call.name,
            detail: _str(call.arguments['path']) ?? result,
            ok: ok,
          ),
        );
        messages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'content': result,
        });
      }
    }
    throw ForgeException(
      500,
      'Агент не уложился в $maxSteps шагов — задача слишком большая',
    );
  }

  Future<String> _execute(ForgeToolCall call, String branch) async {
    switch (call.name) {
      case 'list_dir':
        final path = _str(call.arguments['path']) ?? '';
        final entries = await service.listDirectory(
          owner,
          repo,
          path,
          ref: branch,
        );
        if (entries.isEmpty) return 'Каталог пуст или не найден';
        return entries
            .map((e) => e.isDir ? '${e.path}/' : e.path)
            .join('\n');
      case 'read_file':
        final path = _requirePath(call);
        final file = await service.readFile(owner, repo, path, ref: branch);
        if (file == null) return 'Файл не найден: $path';
        return file.content;
      case 'write_file':
        final path = _requirePath(call);
        final content = _str(call.arguments['content']);
        if (content == null) {
          throw ForgeException(400, 'write_file без content');
        }
        final existing = await service.readFile(owner, repo, path, ref: branch);
        await service.writeFile(
          owner,
          repo,
          path,
          content: content,
          message: _str(call.arguments['message']) ?? 'Кузница: правка $path',
          branch: branch,
          sha: existing?.sha,
        );
        return 'Записано: $path';
      default:
        return 'Неизвестный инструмент: ${call.name}';
    }
  }

  String _requirePath(ForgeToolCall call) {
    final path = _str(call.arguments['path']);
    if (path == null || path.trim().isEmpty) {
      throw ForgeException(400, 'Не указан path');
    }
    if (isBlockedPath(path)) {
      throw ForgeException(403, 'Путь закрыт для агента: $path');
    }
    return path;
  }

  Future<ForgeRunResult> _openPr({
    required String branch,
    required String base,
    required String task,
    required String summary,
    required Set<String> files,
    String? title,
  }) async {
    final url = await service.openPullRequest(
      owner,
      repo,
      title: title ?? _prTitle(task),
      body:
          '$summary\n\n'
          '---\n'
          'Задача: $task\n\n'
          'Изменённые файлы: ${files.join(', ')}\n\n'
          '_Изменения внесены ИИ-агентом «Кузница» из приложения Keramika._',
      head: branch,
      base: base,
    );
    return ForgeRunResult(
      branch: branch,
      summary: summary,
      pullRequestUrl: url.isEmpty ? null : url,
      filesChanged: files.length,
    );
  }

  String _systemPrompt(String languageCode) =>
      'Ты — «Кузница», агент-программист внутри приложения Keramika '
      '(Flutter/Dart, репозиторий $owner/$repo). '
      'Ты правишь код настоящими коммитами в отдельной ветке, затем открываешь pull request. '
      'Работай по шагам: сначала list_dir/read_file, чтобы увидеть реальный код, '
      'затем write_file с ПОЛНЫМ содержимым файла, затем finish. '
      'Не выдумывай код, которого не видел. Не трогай секреты и файлы подписи. '
      'Держись стиля проекта: комментарии по-русски, без лишних слов. '
      'Отвечай на языке: ${languageCode == 'ru' ? 'русском' : languageCode}.';

  String _prTitle(String task) {
    final oneLine = task.replaceAll(RegExp(r'\s+'), ' ').trim();
    final short = oneLine.length <= 60 ? oneLine : '${oneLine.substring(0, 60)}…';
    return 'Кузница: $short';
  }

  static String _slug(String task) {
    final lower = task.toLowerCase();
    final ascii = StringBuffer();
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      if (RegExp(r'[a-z0-9]').hasMatch(ch)) {
        ascii.write(ch);
      } else if (ascii.isNotEmpty && !ascii.toString().endsWith('-')) {
        ascii.write('-');
      }
      if (ascii.length >= 24) break;
    }
    final slug = ascii.toString().replaceAll(RegExp(r'-+$'), '');
    return slug.isEmpty ? 'task' : slug;
  }

  static String? _str(dynamic value) => value is String ? value : null;
}

/// OpenAI-совместимый диалог: Poolside/Laguna напрямую либо через
/// OpenRouter, если ключ начинается с `sk-or-`.
class OpenAiForgeChat implements ForgeChat {
  OpenAiForgeChat({required this.apiKey, http.Client? client})
    : _client = client ?? http.Client();

  static const _poolsideUrl =
      'https://inference.poolside.ai/v1/chat/completions';
  static const _openrouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _poolsideModel = 'poolside/laguna-s-2.1';
  static const _openrouterModel = 'poolside/laguna-s-2.1:free';

  final String apiKey;
  final http.Client _client;

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    final viaOpenRouter = apiKey.startsWith('sk-or-');
    final resp = await _client
        .post(
          Uri.parse(viaOpenRouter ? _openrouterUrl : _poolsideUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode({
            'model': viaOpenRouter ? _openrouterModel : _poolsideModel,
            'messages': messages,
            'tools': tools,
            // Агенту нужно писать целые файлы: 500 токенов хватало чату,
            // но обрезало бы любой файл на середине.
            'max_tokens': 8000,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw ForgeException(resp.statusCode, 'Ключ ИИ отклонён (${resp.statusCode})');
    }
    if (resp.statusCode != 200) {
      throw ForgeException(
        resp.statusCode,
        'ИИ-провайдер ответил ${resp.statusCode}',
      );
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map<String, dynamic>) {
      throw ForgeException(500, 'Пустой ответ ИИ');
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw ForgeException(500, 'Пустой ответ ИИ');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    if (message is! Map) throw ForgeException(500, 'Пустой ответ ИИ');

    final calls = <ForgeToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (var i = 0; i < rawCalls.length; i++) {
        final item = rawCalls[i];
        if (item is! Map) continue;
        final fn = item['function'];
        if (fn is! Map) continue;
        final name = fn['name'];
        if (name is! String) continue;
        calls.add(
          ForgeToolCall(
            id: (item['id'] as String?) ?? 'call_$i',
            name: name,
            arguments: _decodeArgs(fn['arguments']),
          ),
        );
      }
    }
    final text = message['content'];
    return ForgeChatReply(
      text: text is String && text.trim().isNotEmpty ? text : null,
      toolCalls: calls,
    );
  }

  static Map<String, dynamic> _decodeArgs(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {
        // Модель иногда отдаёт невалидный JSON — считаем, что аргументов нет.
      }
    }
    return const {};
  }
}
