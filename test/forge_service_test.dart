import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keramika/services/forge_agent.dart';
import 'package:keramika/services/forge_service.dart';

/// Фейковый GitHub поверх реального http-клиента: проверяем настоящий
/// разбор ответов и настоящие HTTP-вызовы, а не заглушки сервиса.
///
/// `MockClient` — из пакета http, это его штатный способ подменить
/// транспорт; логика [ForgeService] при этом исполняется целиком.
class _FakeGitHub {
  _FakeGitHub({this.push = true});

  final bool push;
  final String requireToken = 'ghp_valid';
  final List<http.Request> requests = [];

  /// Содержимое по ветке. `main` — база, `forge/...` — рабочая ветка: агент
  /// пишет туда, и читать обязан оттуда же.
  final Map<String, Map<String, String>> branchFiles = {
    'main': {'lib/main.dart': 'void main() {}'},
  };
  final Map<String, String> commits = {};

  Map<String, String> files(String branch) =>
      branchFiles.putIfAbsent(branch, () => Map.of(branchFiles['main']!));

  MockClient get client => MockClient((request) async {
    requests.add(request);
    final auth = request.headers['Authorization'];
    if (auth == null || auth != 'Bearer $requireToken') {
      return http.Response(
        jsonEncode({'message': 'Bad credentials'}),
        401,
        headers: {'content-type': 'application/json'},
      );
    }
    final path = request.url.path;
    if (path == '/user') {
      return _json({'login': 'wxstdo-boop'});
    }
    if (path == '/repos/wxstdo-boop/Keramika' && request.method == 'GET') {
      return _json({
        'default_branch': 'main',
        'permissions': {'push': push},
      });
    }
    if (path.contains('/git/ref/heads/')) {
      return _json({
        'object': {'sha': 'base-sha'},
      });
    }
    // Создание рабочей ветки: она получает копию файлов базы.
    if (path == '/repos/wxstdo-boop/Keramika/git/refs' &&
        request.method == 'POST') {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      final ref = (payload['ref'] as String).replaceFirst('refs/heads/', '');
      files(ref);
      return _json({'ref': payload['ref']}, 201);
    }
    if (path.startsWith('/repos/wxstdo-boop/Keramika/contents/')) {
      final file = path.replaceFirst('/repos/wxstdo-boop/Keramika/contents/', '');
      final branch = request.url.queryParameters['ref'] ?? 'main';
      if (request.method == 'GET') {
        final content = files(branch)[file];
        if (content == null) return _json({'message': 'Not Found'}, 404);
        return _json({
          'path': file,
          'sha': 'sha-$file',
          'content': base64.encode(utf8.encode(content)),
        });
      }
      if (request.method == 'PUT') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final target = (payload['branch'] as String?) ?? 'main';
        files(target)[file] = utf8.decode(
          base64.decode(payload['content'] as String),
        );
        commits[file] = payload['message'] as String;
        return _json({'content': {'path': file}}, 201);
      }
    }
    if (path == '/repos/wxstdo-boop/Keramika/pulls' &&
        request.method == 'POST') {
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'html_url':
            'https://github.com/wxstdo-boop/Keramika/pull/1?head=${payload['head']}',
      }, 201);
    }
    return _json({'message': 'Unhandled $path'}, 404);
  });

  http.Response _json(Map<String, dynamic> body, [int code = 200]) =>
      http.Response(
        jsonEncode(body),
        code,
        headers: {'content-type': 'application/json'},
      );
}

/// Модель-скрипт: выдаёт заранее заданные ответы. Настоящая модель — внешний
/// сервис с платными лимитами, и детерминированно проверить цикл агента на
/// ней нельзя; за интерфейсом [ForgeChat] проверяем именно логику цикла.
class _ScriptedChat implements ForgeChat {
  _ScriptedChat(this.replies);

  final List<ForgeChatReply> replies;
  final List<List<Map<String, dynamic>>> seenMessages = [];
  int _index = 0;

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    seenMessages.add(messages.map(Map<String, dynamic>.from).toList());
    if (_index >= replies.length) {
      throw StateError('Модель вызвана больше раз, чем задано сценарием');
    }
    return replies[_index++];
  }
}

ForgeChatReply _call(String name, Map<String, dynamic> args) => ForgeChatReply(
  toolCalls: [
    ForgeToolCall(id: 'call_${name}_${args.hashCode}', name: name, arguments: args),
  ],
);

/// Сервис с токеном в памяти: агент читает токен через `loadToken`, и без
/// подставленного хранилища тест ушёл бы в реальный Keystore платформы.
Future<ForgeService> _serviceWithToken(http.Client client) async {
  final service = ForgeService(
    client: client,
    store: InMemoryForgeTokenStore(),
  );
  await service.saveToken('ghp_valid');
  return service;
}

void main() {
  group('ForgeService', () {
    test('токен сохраняется и читается из хранилища', () async {
      final store = InMemoryForgeTokenStore();
      final service = ForgeService(store: store);

      expect(await service.loadToken(), isNull);
      await service.saveToken('  ghp_secret  ');
      expect(await service.loadToken(), 'ghp_secret');
      await service.clearToken();
      expect(await service.loadToken(), isNull);
    });

    test('пустой токен не сохраняется, а стирается', () async {
      final store = InMemoryForgeTokenStore();
      final service = ForgeService(store: store);
      await service.saveToken('ghp_secret');
      await service.saveToken('   ');
      expect(await service.loadToken(), isNull);
    });

    test('verifyToken возвращает логин владельца', () async {
      final fake = _FakeGitHub();
      final service = ForgeService(client: fake.client);
      expect(await service.verifyToken('ghp_valid'), 'wxstdo-boop');
    });

    test('чужой токен отклоняется как ошибка авторизации', () async {
      final fake = _FakeGitHub();
      final service = ForgeService(client: fake.client);
      await expectLater(
        service.verifyToken('ghp_wrong'),
        throwsA(
          isA<ForgeException>().having((e) => e.isAuth, 'isAuth', isTrue),
        ),
      );
    });

    test('canPush отражает право записи репозитория', () async {
      final writable = ForgeService(client: _FakeGitHub().client);
      expect(await writable.canPush('wxstdo-boop', 'Keramika', token: 'ghp_valid'), isTrue);

      final readOnly = ForgeService(client: _FakeGitHub(push: false).client);
      expect(
        await readOnly.canPush('wxstdo-boop', 'Keramika', token: 'ghp_valid'),
        isFalse,
      );
    });

    test('readFile декодирует base64 с переводами строк', () async {
      final fake = _FakeGitHub();
      final service = ForgeService(client: fake.client);
      final file = await service.readFile(
        'wxstdo-boop',
        'Keramika',
        'lib/main.dart',
        token: 'ghp_valid',
      );
      expect(file, isNotNull);
      expect(file!.content, 'void main() {}');
      expect(file.sha, 'sha-lib/main.dart');
    });

    test('readFile отсутствующего файла возвращает null, не бросает', () async {
      final service = ForgeService(client: _FakeGitHub().client);
      final file = await service.readFile(
        'wxstdo-boop',
        'Keramika',
        'lib/nope.dart',
        token: 'ghp_valid',
      );
      expect(file, isNull);
    });

    test('writeFile отправляет содержимое и sha существующего файла', () async {
      final fake = _FakeGitHub();
      final service = ForgeService(client: fake.client);
      await service.writeFile(
        'wxstdo-boop',
        'Keramika',
        'lib/main.dart',
        content: 'void main() => runApp();',
        message: 'Кузница: правка',
        branch: 'forge/test',
        sha: 'sha-lib/main.dart',
        token: 'ghp_valid',
      );
      // Ветка генерируется в рантайме — ищем её по факту записи.
      final writtenBranch = fake.branchFiles.keys.firstWhere(
        (b) => b != 'main',
      );
      expect(
        fake.branchFiles[writtenBranch]!['lib/main.dart'],
        'void main() => runApp();',
      );
      final put = fake.requests.lastWhere((r) => r.method == 'PUT');
      final payload = jsonDecode(put.body) as Map<String, dynamic>;
      expect(payload['sha'], 'sha-lib/main.dart');
      expect(payload['branch'], 'forge/test');
    });

    test('createBranch не падает, если ветка уже существует', () async {
      final fake = _FakeGitHub();
      final service = ForgeService(client: fake.client);
      final branch = await service.createBranch(
        'wxstdo-boop',
        'Keramika',
        name: 'forge/test',
        from: 'main',
        token: 'ghp_valid',
      );
      expect(branch.name, 'forge/test');
      expect(branch.sha, 'base-sha');
    });
  });

  group('FreePoolForgeChat', () {
    test('падающий провайдер пропускается, работает следующий', () async {
      // Kilo отдаёт 429 — пул обязан перейти к Murakumo и не упасть.
      final hits = <String>[];
      final client = MockClient((request) async {
        final host = request.url.host;
        hits.add(host);
        if (host.contains('kilo')) {
          return http.Response('{"error":"rate limited"}', 429);
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'function': {
                        'name': 'write_file',
                        'arguments': jsonEncode({
                          'path': 'a.txt',
                          'content': 'x',
                        }),
                      },
                    },
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      String? used;
      final chat = FreePoolForgeChat(
        client: client,
        onProvider: (name) => used = name,
      );
      final reply = await chat.complete([
        {'role': 'user', 'content': 'сделай'},
      ], []);

      expect(used, 'Murakumo');
      expect(reply.toolCalls, hasLength(1));
      expect(reply.toolCalls.first.name, 'write_file');
      expect(reply.toolCalls.first.arguments['path'], 'a.txt');
      // Kilo пробовали дважды (обе модели) и только потом ушли дальше.
      expect(hits.where((h) => h.contains('kilo')).length, 2);
      expect(hits.last, contains('murakumo'));
    });

    test('когда все провайдеры недоступны — понятная ошибка', () async {
      final client = MockClient(
        (request) async => http.Response('<html>down</html>', 503),
      );
      final chat = FreePoolForgeChat(client: client);

      await expectLater(
        chat.complete([
          {'role': 'user', 'content': 'сделай'},
        ], []),
        throwsA(
          isA<ForgeException>().having(
            (e) => e.message,
            'message',
            contains('недоступны'),
          ),
        ),
      );
    });
  });

  group('ForgeAgent', () {
    test('полный цикл: читает файл, пишет правку, открывает PR', () async {
      final fake = _FakeGitHub();
      final chat = _ScriptedChat([
        _call('read_file', {'path': 'lib/main.dart'}),
        _call('write_file', {
          'path': 'lib/main.dart',
          'content': 'void main() => runApp(KeramikaApp());',
          'message': 'Кузница: точка входа',
        }),
        _call('finish', {'summary': 'Поправил точку входа'}),
      ]);
      final steps = <ForgeStep>[];
      final agent = ForgeAgent(
        service: await _serviceWithToken(fake.client),
        chat: chat,
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );

      final result = await agent.run(
        task: 'поправь точку входа',
        baseBranch: 'main',
        onStep: steps.add,
      );

      expect(result.filesChanged, 1);
      expect(result.pullRequestUrl, contains('/pull/1'));
      expect(result.branch, startsWith('forge/'));
      expect(steps.map((s) => s.tool), ['read_file', 'write_file']);
      expect(
        fake.branchFiles.values.any(
          (f) => (f['lib/main.dart'] ?? '').contains('KeramikaApp'),
        ),
        isTrue,
      );
      // Модель получила содержимое реального файла, а не пустую строку.
      expect(
        chat.seenMessages[1].any((m) => '${m['content']}'.contains('void main()')),
        isTrue,
      );
    });

    test('правки читаются из рабочей ветки, а не из main', () async {
      // Раньше чтения внутри прогона шли без ref, то есть в основную ветку.
      // На втором файле агент видел СВОЮ ЖЕ правку как отсутствующую и
      // перезаписывал её исходной версией.
      final fake = _FakeGitHub();
      final chat = _ScriptedChat([
        _call('write_file', {
          'path': 'lib/main.dart',
          'content': 'void main() => runApp(ForgeApp());',
        }),
        _call('read_file', {'path': 'lib/main.dart'}),
        _call('finish', {'summary': 'готово'}),
      ]);
      final agent = ForgeAgent(
        service: await _serviceWithToken(fake.client),
        chat: chat,
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );

      await agent.run(task: 'поправь точку входа', baseBranch: 'main');

      // Чтение после записи обязано вернуть версию агента.
      final readResult = chat.seenMessages
          .expand((m) => m)
          .where((m) => m['role'] == 'tool')
          .map((m) => '${m['content']}')
          .toList();
      expect(
        readResult.any((c) => c.contains('ForgeApp')),
        isTrue,
        reason: 'агент должен читать свою ветку, а не main',
      );
      // И запросы чтения обязаны нести ref рабочей ветки.
      final contentsGets = fake.requests.where(
        (r) => r.method == 'GET' && r.url.path.contains('/contents/'),
      );
      expect(
        contentsGets.every((r) => r.url.queryParameters['ref'] != null),
        isTrue,
      );
    });

    test('файлы секретов и подписи агенту закрыты', () async {
      final fake = _FakeGitHub();
      final chat = _ScriptedChat([
        _call('read_file', {'path': 'android/key.properties'}),
        _call('finish', {'summary': 'нет'}),
      ]);
      final agent = ForgeAgent(
        service: await _serviceWithToken(fake.client),
        chat: chat,
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );

      await expectLater(
        agent.run(task: 'покажи пароли', baseBranch: 'main'),
        throwsA(isA<ForgeException>()),
      );
      // Проверка стоит ДО сетевого вызова: файл секретов не должен быть
      // даже запрошен у GitHub.
      expect(
        fake.requests.any((r) => r.url.path.contains('key.properties')),
        isFalse,
      );
      expect(
        ForgeAgent.isBlockedPath('android/key.properties'),
        isTrue,
      );
      expect(ForgeAgent.isBlockedPath('release.jks'), isTrue);
      expect(ForgeAgent.isBlockedPath('../../etc/passwd'), isTrue);
      expect(ForgeAgent.isBlockedPath('lib/main.dart'), isFalse);
    });

    test('выход за пределы каталога запрещён', () async {
      final fake = _FakeGitHub();
      final chat = _ScriptedChat([
        _call('write_file', {
          'path': '../outside.dart',
          'content': 'x',
        }),
        _call('finish', {'summary': 'нет'}),
      ]);
      final agent = ForgeAgent(
        service: await _serviceWithToken(fake.client),
        chat: chat,
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );
      await expectLater(
        agent.run(task: 'выйди наружу', baseBranch: 'main'),
        throwsA(isA<ForgeException>()),
      );
    });

    test('прогон без правок не открывает пустой PR', () async {
      final chat = _ScriptedChat([
        ForgeChatReply(text: 'Мне нечего менять.'),
      ]);
      final agent = ForgeAgent(
        service: await _serviceWithToken(_FakeGitHub().client),
        chat: chat,
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );
      await expectLater(
        agent.run(task: 'ничего не делай', baseBranch: 'main'),
        throwsA(isA<ForgeException>()),
      );
    });

    test('превышение лимита правок останавливает агента', () async {
      final replies = <ForgeChatReply>[
        for (var i = 0; i < ForgeAgent.maxWrites + 1; i++)
          _call('write_file', {
            'path': 'lib/file$i.dart',
            'content': '// $i',
          }),
        _call('finish', {'summary': 'готово'}),
      ];
      final agent = ForgeAgent(
        service: await _serviceWithToken(_FakeGitHub().client),
        chat: _ScriptedChat(replies),
        owner: 'wxstdo-boop',
        repo: 'Keramika',
      );
      await expectLater(
        agent.run(task: 'перепиши всё', baseBranch: 'main'),
        throwsA(isA<ForgeException>()),
      );
    });
  });
}
