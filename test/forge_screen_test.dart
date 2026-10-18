import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/forge_screen.dart';
import 'package:keramika/services/forge_agent.dart';
import 'package:keramika/services/forge_service.dart';

/// Жалоба: «вставленный токен не сохраняется». Проверяем именно это —
/// токен, положенный в хранилище, при новом открытии экрана подставляется
/// в поле, а не теряется.
MockClient _okClient() => MockClient((request) async {
  final path = request.url.path;
  if (path == '/user') {
    return http.Response(
      jsonEncode({'login': 'wxstdo-boop'}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  if (path == '/repos/wxstdo-boop/Keramika') {
    return http.Response(
      jsonEncode({
        'default_branch': 'main',
        'permissions': {'push': true},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  // Ветки и PR: агент создаёт рабочую ветку, коммитит и открывает PR.
  if (path.contains('/git/ref/heads/')) {
    return http.Response(
      jsonEncode({
        'object': {'sha': 'base-sha'},
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  if (path == '/repos/wxstdo-boop/Keramika/git/refs') {
    return http.Response(
      jsonEncode({'ref': 'refs/heads/forge/x'}),
      201,
      headers: {'content-type': 'application/json'},
    );
  }
  if (path.startsWith('/repos/wxstdo-boop/Keramika/contents/')) {
    if (request.method == 'PUT') {
      return http.Response(
        jsonEncode({
          'content': {'path': 'a.txt'},
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{"message":"Not Found"}', 404, headers: {
      'content-type': 'application/json',
    });
  }
  if (path == '/repos/wxstdo-boop/Keramika/pulls') {
    return http.Response(
      jsonEncode({
        'html_url': 'https://github.com/wxstdo-boop/Keramika/pull/1',
      }),
      201,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('{}', 200, headers: {'content-type': 'application/json'});
});

Widget _wrap(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

/// Модель-скрипт: один вызов инструмента и завершение. Настоящий провайдер
/// — внешний сервис, в тесте ему не место.
class _ScriptedChat implements ForgeChat {
  _ScriptedChat();

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    if (messages.any((m) => m['role'] == 'tool')) {
      return const ForgeChatReply(
        toolCalls: [
          ForgeToolCall(
            id: 'c2',
            name: 'finish',
            arguments: {'summary': 'Готово'},
          ),
        ],
      );
    }
    return const ForgeChatReply(
      toolCalls: [
        ForgeToolCall(
          id: 'c1',
          name: 'write_file',
          arguments: {'path': 'a.txt', 'content': 'x'},
        ),
      ],
    );
  }
}

void main() {
  testWidgets('агент запускается без ключа ИИ — на бесплатном пуле', (
    tester,
  ) async {
    // Ключ ИИ в настройках не задан: раньше экран показывал «добавь ключ».
    // Экран высокий — разворачиваем поверхность, чтобы карточка результата
    // была видна без прокрутки.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.pumpWidget(
      _wrap(
        ForgeScreen(
          owner: 'wxstdo-boop',
          repo: 'Keramika',
          service: service,
          chatFactory: (apiKey) => _ScriptedChat(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'создай a.txt');
    final sendButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Отправить'),
    );
    // Чтение своего ключа — настоящий доступ к хранилищу, и поддельные часы
    // его не двигают: прогон запускаем в «живом» времени.
    await tester.runAsync(() async {
      sendButton.onPressed!();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (tester.any(find.textContaining('pull/1'))) break;
      }
    });
    await tester.pumpAndSettle();

    // Прогон дошёл до PR: значит ключ ИИ не потребовался.
    expect(find.textContaining('pull/1'), findsOneWidget);
    expect(find.textContaining('ключ ИИ'), findsNothing);
  });

  testWidgets('сохранённый токен подставляется при открытии экрана', (
    tester,
  ) async {
    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, 'ghp_saved_token');
    // Токен не показываем открытым текстом.
    expect(field.obscureText, isTrue);
  });

  testWidgets('поле токена скрыто и без «глазка»', (tester) async {
    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    final token = tester.widget<TextField>(find.byType(TextField).first);
    expect(token.obscureText, isTrue);
    // Глазка быть не должно: секрет не раскрывается на экране.
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
    // Значок удаления на месте.
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('ввод задачи печатается плавно и без лупы', (tester) async {
    final service = ForgeService(
      client: _okClient(),
      store: InMemoryForgeTokenStore(),
    );
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    // Поле задачи — второе: токен, затем задача.
    final task = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(task.magnifierConfiguration, isA<TextMagnifierConfiguration>());
    expect(task.contextMenuBuilder, isNotNull);
    expect(task.buildCounter, isNotNull);

    await tester.enterText(find.byType(TextField).at(1), 'поправь кнопку');
    // Анимация букв не должна «заедать»: после прокачки кадров текст на месте.
    await tester.pump(const Duration(milliseconds: 400));
    expect(task.controller?.text, 'поправь кнопку');
  });

  testWidgets('без сохранённого токена поле пустое', (tester) async {
    final service = ForgeService(
      client: _okClient(),
      store: InMemoryForgeTokenStore(),
    );
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, isEmpty);
  });

  testWidgets('кнопка «Забыть токен» очищает поле и хранилище', (tester) async {
    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
    await tester.pumpAndSettle();

    expect(await service.loadToken(), isNull);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, isEmpty);
  });
}
