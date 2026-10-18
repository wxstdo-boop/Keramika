// ignore_for_file: avoid_print
//
// РУЧНОЙ тест: в CI пропускается (нужен FORGE_LIVE=1), потому что создаёт
// настоящую ветку и pull request в реальном репозитории.
//
// ЖИВАЯ проверка «Кузницы»: настоящий GitHub (реальные ветки, коммиты, PR),
// подменена ТОЛЬКО модель — ключа ИИ в этом окружении нет, а цикл агента и
// вся работа с GitHub-API проверяются целиком.
//
// ВНИМАНИЕ: создаёт временную ветку и черновик PR в wxstdo-boop/Keramika.
// Запускать вручную: flutter test test/live_forge_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:keramika/services/forge_agent.dart';
import 'package:keramika/services/forge_service.dart';

class _ScriptedChat implements ForgeChat {
  _ScriptedChat(this.replies);
  final List<ForgeChatReply> replies;
  final List<List<Map<String, dynamic>>> seen = [];
  int _i = 0;

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    seen.add(messages.map(Map<String, dynamic>.from).toList());
    return replies[_i++];
  }
}

void main() {
  // Второй живой прогон: агент ведут НАСТОЯЩИЕ бесплатные провайдеры
  // (FreePoolForgeChat), без скрипта и без ключа. Это проверка того, что
  // «Кузница» действительно работает «из коробки».
  test('LIVE: бесплатный провайдер сам ведёт агента до PR', () async {
    final token = Platform.environment['GITHUB_TOKEN'];
    expect(token, isNotNull, reason: 'нужен GITHUB_TOKEN');
    const owner = 'wxstdo-boop';
    const repo = 'Keramika';

    final service = ForgeService(store: InMemoryForgeTokenStore());
    await service.saveToken(token!);

    final agent = ForgeAgent(
      service: service,
      chat: FreePoolForgeChat(
        onProvider: (name) => print('LIVE-FREE: провайдер=$name'),
      ),
      owner: owner,
      repo: repo,
    );

    final result = await agent.run(
      task:
          'Создай файл FORGE_FREE_CHECK.md с заголовком «Проверка бесплатного '
          'провайдера» и одной строкой текста. Ничего другого не меняй.',
      baseBranch: 'main',
      onStep: (s) => print('LIVE-FREE шаг: ${s.tool} — ${s.detail}'),
    );

    print('LIVE-FREE: ветка=${result.branch}');
    print('LIVE-FREE: файлов=${result.filesChanged}');
    print('LIVE-FREE: PR=${result.pullRequestUrl}');

    expect(result.filesChanged, greaterThanOrEqualTo(1));
    expect(result.pullRequestUrl, isNotNull);

    final fromBranch = await service.readFile(
      owner,
      repo,
      'FORGE_FREE_CHECK.md',
      ref: result.branch,
    );
    print('LIVE-FREE: файл в ветке=${fromBranch != null}');
    expect(fromBranch, isNotNull);

    final fromMain = await service.readFile(
      owner,
      repo,
      'FORGE_FREE_CHECK.md',
      ref: 'main',
    );
    expect(fromMain, isNull, reason: 'main не должен быть тронут');

    final prNumber = RegExp(
      r'/pull/(\d+)',
    ).firstMatch(result.pullRequestUrl!)![1];
    await http.patch(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$prNumber'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      },
      body: jsonEncode({'state': 'closed'}),
    );
    final del = await http.delete(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/refs/heads/${result.branch}',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('LIVE-FREE: cleanup PR=closed, ветка удалена (${del.statusCode})');
    expect(del.statusCode, 204);
  },
      timeout: const Timeout(Duration(minutes: 8)),
      skip: Platform.environment['FORGE_LIVE'] != '1');

  test('LIVE: агент правит репозиторий и открывает PR', () async {
    final token = Platform.environment['GITHUB_TOKEN'];
    expect(token, isNotNull, reason: 'нужен GITHUB_TOKEN');
    const owner = 'wxstdo-boop';
    const repo = 'Keramika';

    final service = ForgeService(store: InMemoryForgeTokenStore());
    await service.saveToken(token!);

    // 1) Токен действительно рабочий.
    final login = await service.verifyToken(token);
    print('LIVE: токен валиден, логин=$login');
    expect(login, isNotEmpty);

    // 2) Право записи в репозиторий.
    final push = await service.canPush(owner, repo, token: token);
    print('LIVE: canPush=$push');
    expect(push, isTrue);

    // 3) Реальное чтение файла из main.
    final readme = await service.readFile(owner, repo, 'README.md');
    print('LIVE: README.md прочитан, длина=${readme?.content.length}');
    expect(readme, isNotNull);

    // 4) Полный цикл агента: создать ветку, прочитать, записать, открыть PR.
    final chat = _ScriptedChat([
      ForgeChatReply(
        toolCalls: [
          ForgeToolCall(
            id: 'c1',
            name: 'read_file',
            arguments: {'path': 'README.md'},
          ),
        ],
      ),
      ForgeChatReply(
        toolCalls: [
          ForgeToolCall(
            id: 'c2',
            name: 'write_file',
            arguments: {
              'path': 'FORGE_LIVE_CHECK.md',
              'content':
                  '# Живая проверка Кузницы\n\n'
                  'Этот файл создан агентом «Кузница» при живой проверке.\n',
              'message': 'Кузница: живая проверка',
            },
          ),
        ],
      ),
      const ForgeChatReply(
        toolCalls: [
          ForgeToolCall(id: 'c3', name: 'finish', arguments: {}),
        ],
      ),
    ]);

    final agent = ForgeAgent(
      service: service,
      chat: chat,
      owner: owner,
      repo: repo,
    );
    final result = await agent.run(
      task: 'Живая проверка: создай файл FORGE_LIVE_CHECK.md',
      baseBranch: 'main',
      onStep: (s) => print('LIVE шаг: ${s.tool} — ${s.detail}'),
    );

    print('LIVE: ветка=${result.branch}');
    print('LIVE: файлов=${result.filesChanged}');
    print('LIVE: PR=${result.pullRequestUrl}');
    expect(result.filesChanged, 1);
    expect(result.pullRequestUrl, isNotNull);

    // 5) Файл реально существует в рабочей ветке на GitHub.
    final fromBranch = await service.readFile(
      owner,
      repo,
      'FORGE_LIVE_CHECK.md',
      ref: result.branch,
    );
    print('LIVE: файл в ветке прочитан=${fromBranch != null}');
    expect(fromBranch?.content, contains('Живая проверка Кузницы'));

    // 6) В main файла НЕТ — основная ветка не тронута.
    final fromMain = await service.readFile(
      owner,
      repo,
      'FORGE_LIVE_CHECK.md',
      ref: 'main',
    );
    expect(fromMain, isNull);

    // 7) PR действительно открыт на GitHub.
    final prNumber = RegExp(r'/pull/(\d+)').firstMatch(result.pullRequestUrl!)![1];
    final prResp = await http.get(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$prNumber'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      },
    );
    final pr = jsonDecode(prResp.body) as Map<String, dynamic>;
    print('LIVE: PR #$prNumber state=${pr['state']} head=${pr['head']?['ref']}');
    expect(pr['state'], anyOf('open', 'closed'));
    expect('${pr['head']?['ref']}', result.branch);

    // 8) Убираем за собой: закрываем PR и удаляем ветку.
    await http.patch(
      Uri.parse('https://api.github.com/repos/$owner/$repo/pulls/$prNumber'),
      headers: {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
      },
      body: jsonEncode({'state': 'closed'}),
    );
    final del = await http.delete(
      Uri.parse(
        'https://api.github.com/repos/$owner/$repo/git/refs/heads/${result.branch}',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    print('LIVE: cleanup PR=closed, ветка удалена (${del.statusCode})');
    expect(del.statusCode, 204);
  },
      timeout: const Timeout(Duration(minutes: 3)),
      skip: Platform.environment['FORGE_LIVE'] != '1');
}
