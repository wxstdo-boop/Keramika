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

/// Реплика в чате «Кузницы». Хранит не только текст, но и шаги агента с
/// ссылкой на PR — по ним видно, что именно он сделал в проекте.
class ForgeChatMessage {
  const ForgeChatMessage({
    required this.isUser,
    required this.text,
    this.steps = const [],
    this.pullRequestUrl,
    this.branch,
    this.ts,
  });

  final bool isUser;
  final String text;
  final List<ForgeStep> steps;
  final String? pullRequestUrl;
  final String? branch;
  final int? ts;

  Map<String, dynamic> toJson() => {
    'isUser': isUser,
    'text': text,
    'ts': ts,
    'branch': branch,
    'pullRequestUrl': pullRequestUrl,
    'steps': [
      for (final step in steps)
        {'tool': step.tool, 'detail': step.detail, 'ok': step.ok},
    ],
  };

  factory ForgeChatMessage.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    return ForgeChatMessage(
      isUser: json['isUser'] == true,
      text: json['text'] as String? ?? '',
      ts: (json['ts'] as num?)?.toInt(),
      branch: json['branch'] as String?,
      pullRequestUrl: json['pullRequestUrl'] as String?,
      steps: rawSteps is List
          ? [
              for (final item in rawSteps)
                if (item is Map)
                  ForgeStep(
                    tool: item['tool'] as String? ?? '',
                    detail: item['detail'] as String? ?? '',
                    ok: item['ok'] != false,
                  ),
            ]
          : const [],
    );
  }
}

/// Итог одного хода диалога: ответ модели плюс след в проекте.
class ForgeTurnResult {
  const ForgeTurnResult({
    required this.text,
    this.branch,
    this.pullRequestUrl,
    this.filesChanged = 0,
    this.steps = const [],
  });

  final String text;
  final String? branch;
  final String? pullRequestUrl;
  final int filesChanged;
  final List<ForgeStep> steps;

  bool get madeChanges => filesChanged > 0;
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
    this.baseBranch = 'main',
  });

  final ForgeService service;
  final ForgeChat chat;
  final String owner;
  final String repo;

  /// Ветка, от которой агент отвечает. Обычно основная.
  final String baseBranch;

  /// Рабочая ветка текущего диалога. Создаётся ЛЕНИВО — при первой правке,
  /// а не при первом вопросе: на вопрос «как устроен этот файл» ветка и PR
  /// не нужны, и создавать их было бы мусором в репозитории.
  String? _branch;

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
        'name': 'search_code',
        'description':
            'Найти файлы по тексту или имени. Быстрее, чем обходить каталоги.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Что искать, например class ForgeAgent.',
            },
          },
          'required': ['query'],
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
        'name': 'delete_file',
        'description': 'Удалить файл в рабочей ветке.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {'type': 'string', 'description': 'Путь файла.'},
            'message': {
              'type': 'string',
              'description': 'Короткое сообщение коммита.',
            },
          },
          'required': ['path'],
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

  /// Один ход диалога: ответ на реплику и, если попросили, правки проекта.
  ///
  /// Работает как настоящий чат: `history` — предыдущие реплики, `task` —
  /// новая. Модель может просто ответить текстом (тогда ветка и PR не
  /// создаются), а может править файлы — тогда агент заводит рабочую ветку,
  /// коммитит и открывает pull request.
  Future<ForgeTurnResult> respond({
    required List<ForgeChatMessage> history,
    required String task,
    String baseBranch = 'main',
    String languageCode = 'ru',
    void Function(ForgeStep step)? onStep,
  }) async {
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt(languageCode)},
      for (final m in history)
        if (m.text.trim().isNotEmpty)
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
      {'role': 'user', 'content': task},
    ];
    final tools = _tools();
    final steps = <ForgeStep>[];
    var writes = 0;
    // Правки хода: записанные и удалённые файлы. Удаление — такая же правка,
    // как запись: без него PR не открывался бы на чистом удалении.
    final written = <String>{};
    final deleted = <String>{};
    String? lastText;

    for (var step = 0; step < maxSteps; step++) {
      final reply = await chat.complete(messages, tools);
      if (reply.text != null && reply.text!.trim().isNotEmpty) {
        lastText = reply.text;
      }

      if (reply.toolCalls.isEmpty) {
        // Модель ответила текстом. Без правок это обычный ответ в чате —
        // никаких веток и PR. С правками — доводим работу до PR.
        return _conclude(
          branch: _branch,
          base: baseBranch,
          task: task,
          text: reply.text ?? lastText ?? '',
          files: _netChanged(written, deleted),
          steps: steps,
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
          final summary = _str(call.arguments['summary']) ?? lastText ?? '';
          return _conclude(
            branch: _branch,
            base: baseBranch,
            task: task,
            text: summary.isEmpty ? (lastText ?? 'Готово') : summary,
            title: _str(call.arguments['title']),
            files: _netChanged(written, deleted),
            steps: steps,
          );
        }

        String result;
        var ok = true;
        // Предохранитель, а не подсказка модели: если она упорно пишет
        // сверх лимита, прогон останавливаем — иначе один запуск может
        // переписать весь проект.
        if (_isWrite(call.name) && writes >= maxWrites) {
          throw ForgeException(
            429,
            'Достигнут предел правок ($maxWrites) за один ход',
          );
        }
        try {
          // Ветку заводим ТОЛЬКО под правку. Вопрос по коду читает базовую
          // ветку и не оставляет после себя ни ветки, ни PR.
          final branch = _isWrite(call.name)
              ? await _ensureBranch(task, baseBranch)
              : (_branch ?? baseBranch);
          result = await _execute(call, branch);
          if (_isWrite(call.name)) {
            writes++;
            final p = _str(call.arguments['path']);
            if (p != null) {
              if (call.name == 'delete_file') {
                deleted.add(p);
              } else {
                written.add(p);
              }
            }
          }
        } on ForgeException catch (e) {
          ok = false;
          result = 'Ошибка: ${e.message}';
        }
        final step_ = ForgeStep(
          tool: call.name,
          detail: _str(call.arguments['path']) ?? result,
          ok: ok,
        );
        steps.add(step_);
        onStep?.call(step_);
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

  /// Прогон одиночной задачи (совместимость и «сделай и открой PR»).
  /// Без правок — ошибка: этот вход просили именно изменить проект.
  Future<ForgeRunResult> run({
    required String task,
    required String baseBranch,
    String languageCode = 'ru',
    void Function(ForgeStep step)? onStep,
  }) async {
    final turn = await respond(
      history: const [],
      task: task,
      baseBranch: baseBranch,
      languageCode: languageCode,
      onStep: onStep,
    );
    if (!turn.madeChanges) {
      throw ForgeException(500, turn.text.isEmpty ? 'Агент ничего не изменил' : turn.text);
    }
    return ForgeRunResult(
      branch: turn.branch ?? '',
      summary: turn.text,
      pullRequestUrl: turn.pullRequestUrl,
      filesChanged: turn.filesChanged,
    );
  }

  static bool _isWrite(String tool) =>
      tool == 'write_file' || tool == 'delete_file';

  /// Итоговый набор изменённых файлов. Файл, записанный и затем удалённый в
  /// одном ходе, к результату не относится — его из набора убираем.
  static Set<String> _netChanged(Set<String> written, Set<String> deleted) =>
      {...written.difference(deleted), ...deleted.difference(written)};

  /// Рабочая ветка диалога: создаётся при первой правке и дальше живёт до
  /// конца сессии — так правки одного диалога ложатся в один PR.
  Future<String> _ensureBranch(String task, String base) async {
    final existing = _branch;
    if (existing != null) return existing;
    final name =
        'forge/${_slug(task)}-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    await service.createBranch(owner, repo, name: name, from: base);
    _branch = name;
    return name;
  }

  /// Завершение хода: с правками — PR, без правок — просто ответ в чате.
  Future<ForgeTurnResult> _conclude({
    required String? branch,
    required String base,
    required String task,
    required String text,
    required Set<String> files,
    required List<ForgeStep> steps,
    String? title,
  }) async {
    if (files.isEmpty || branch == null) {
      return ForgeTurnResult(text: text, steps: steps);
    }
    final url = await service.openPullRequest(
      owner,
      repo,
      title: title ?? _prTitle(task),
      body:
          '$text\n\n'
          '---\n'
          'Задача: $task\n\n'
          'Изменённые файлы: ${files.join(', ')}\n\n'
          '_Изменения внесены ИИ-агентом «Кузница» из приложения Keramika._',
      head: branch,
      base: base,
    );
    return ForgeTurnResult(
      text: text,
      branch: branch,
      pullRequestUrl: url.isEmpty ? null : url,
      filesChanged: files.length,
      steps: steps,
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
      case 'search_code':
        final query = _str(call.arguments['query'])?.trim() ?? '';
        if (query.isEmpty) {
          throw ForgeException(400, 'search_code без query');
        }
        final hits = await service.searchCode(owner, repo, query);
        if (hits.isEmpty) return 'Ничего не найдено по запросу: $query';
        return hits.join('\n');
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
      case 'delete_file':
        final path = _requirePath(call);
        await service.deleteFile(
          owner,
          repo,
          path,
          message: _str(call.arguments['message']) ?? 'Кузница: удаление $path',
          branch: branch,
        );
        return 'Удалено: $path';
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

  String _systemPrompt(String languageCode) =>
      'Ты — «Кузница», ИИ-агент-программист внутри приложения Keramika '
      '(Flutter/Dart, репозиторий $owner/$repo). Ты ведёшь ЖИВОЙ ДИАЛОГ с '
      'разработчиком и по его просьбе правишь код настоящими коммитами в '
      'отдельной ветке, затем открываешь pull request.\n'
      'Как вести себя:\n'
      '— На вопрос о коде отвечай текстом, опираясь на реальные файлы: '
      'сначала list_dir/read_file, потом ответ. Для ответа НЕ вызывай '
      'finish и не правь файлы — ветка и PR на вопросы не создаются.\n'
      '— Когда просят что-то изменить: прочитай нужные файлы, вызови '
      'write_file с ПОЛНЫМ содержимым файла (не фрагмент), при необходимости '
      'delete_file, и заверши вызовом finish с кратким summary.\n'
      '— Помни предыдущие реплики диалога и продолжай начатую работу, не '
      'начиная всё заново.\n'
      'Не выдумывай код, которого не видел. Не трогай секреты и файлы '
      'подписи. Держись стиля проекта: комментарии по-русски, без лишних '
      'слов. Пиши по делу и коротко.\n'
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

/// Пул бесплатных OpenAI-совместимых провайдеров — тот же набор, на котором
/// работает Ада в приложении. Ключ не нужен, поэтому «Кузница» работает
/// «из коробки».
///
/// Вызов инструментов проверен вживую на всех трёх: модель возвращает
/// `tool_calls`, понимает результат инструмента и продолжает цикл.
/// Провайдеры перебираются по очереди: бесплатные площадки часто отдают 429,
/// и один упавший не должен останавливать прогон.
class FreePoolForgeChat implements ForgeChat {
  FreePoolForgeChat({http.Client? client, this.apiKey = '', this.onProvider})
    : _client = client ?? http.Client();

  /// Необязательный свой ключ ИИ (Poolside/Laguna или OpenRouter). Если он
  /// задан, пробуется первым; при отказе пул всё равно продолжит работу.
  final String apiKey;

  /// Имя сработавшего провайдера — для журнала агента.
  final void Function(String name)? onProvider;

  final http.Client _client;

  /// Дольше ждать бессмысленно: прогон агента делает много шагов, и один
  /// зависший провайдер съел бы весь бюджет времени. Упавший — пропускаем.
  static const _timeout = Duration(seconds: 45);

  static const _poolsideUrl =
      'https://inference.poolside.ai/v1/chat/completions';
  static const _openrouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  static const _poolsideModel = 'poolside/laguna-s-2.1';
  static const _openrouterModel = 'poolside/laguna-s-2.1:free';

  static const _kiloUrl = 'https://api.kilo.ai/api/gateway/chat/completions';
  static const _murakumoUrl = 'https://api.murakumo.cloud/v1/chat/completions';
  static const _ovhUrl =
      'https://oai.endpoints.kepler.ai.cloud.ovh.net/v1/chat/completions';

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    final failures = <String>[];

    for (final provider in _providers()) {
      try {
        final reply = await _ask(provider, messages, tools);
        onProvider?.call(provider.label);
        return reply;
      } on ForgeException {
        rethrow; // осмысленный отказ провайдера — не глотаем
      } catch (e) {
        failures.add('${provider.label}: $e');
      }
    }

    throw ForgeException(
      502,
      'Бесплатные ИИ-провайдеры недоступны. Попробуй ещё раз позже.'
      '${failures.isEmpty ? '' : ' (${failures.join('; ')})'}',
    );
  }

  List<_FreeProvider> _providers() => [
    if (apiKey.isNotEmpty)
      // Свой ключ — первым: он надёжнее бесплатных площадок. Если откажет,
      // пул молча продолжит на бесплатных.
      if (apiKey.startsWith('sk-or-'))
        _FreeProvider(
          label: 'OpenRouter',
          url: _openrouterUrl,
          model: _openrouterModel,
          apiKey: apiKey,
        )
      else
        _FreeProvider(
          label: 'Poolside',
          url: _poolsideUrl,
          model: _poolsideModel,
          apiKey: apiKey,
        ),
    // Основной: анонимно до 200 запросов/час на IP, отвечает сильной
    // бесплатной моделью и держит целые файлы (проверено: 300 строк без
    // обрезки при max_tokens 8000).
    const _FreeProvider(
      label: 'Kilo',
      url: _kiloUrl,
      model: 'openrouter/free',
      userAgent: 'KeramikaApp/1.6.0',
    ),
    const _FreeProvider(
      label: 'Kilo',
      url: _kiloUrl,
      model: 'kilo-auto/free',
      userAgent: 'KeramikaApp/1.6.0',
    ),
    const _FreeProvider(
      label: 'Murakumo',
      url: _murakumoUrl,
      model: 'murakumo/free',
    ),
    const _FreeProvider(
      label: 'OVHcloud',
      url: _ovhUrl,
      model: 'Mistral-Nemo-Instruct-2407',
      userAgent: 'KeramikaApp/1.6.0',
    ),
  ];

  Future<ForgeChatReply> _ask(
    _FreeProvider provider,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (provider.userAgent != null) {
      headers['User-Agent'] = provider.userAgent!;
    }
    if (provider.apiKey != null) {
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    final resp = await _client
        .post(
          Uri.parse(provider.url),
          headers: headers,
          body: jsonEncode({
            'model': provider.model,
            'messages': messages,
            'tools': tools,
            // Агенту нужно писать целые файлы, а не реплики чата.
            'max_tokens': 8000,
          }),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final raw = utf8.decode(resp.bodyBytes).trim();
    // Некоторые площадки отдают HTML-страницу вместо JSON.
    if (raw.isEmpty || raw.startsWith('<')) {
      throw Exception('не JSON');
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map) throw Exception('не JSON-объект');
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) throw Exception('пустой ответ');
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    if (message is! Map) throw Exception('пустой ответ');

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
}

class _FreeProvider {
  const _FreeProvider({
    required this.label,
    required this.url,
    required this.model,
    this.userAgent,
    this.apiKey,
  });

  final String label;
  final String url;
  final String model;
  final String? userAgent;
  final String? apiKey;
}

/// Аргументы инструмента приходят строкой JSON (иногда невалидной).
Map<String, dynamic> _decodeArgs(dynamic value) {
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
