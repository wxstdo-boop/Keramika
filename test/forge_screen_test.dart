import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/l10n/translations.dart';
import 'package:keramika/screens/forge_screen.dart';
import 'package:keramika/services/forge_agent.dart';
import 'package:keramika/services/forge_chat_store.dart';
import 'package:keramika/services/forge_service.dart';
import 'package:keramika/services/json_file.dart';

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

/// Хранилище, которое «сломано»: так ведёт себя Keystore после смены
/// подписи или переустановки — запись осталась, а ключ шифрования потерян,
/// и чтение падает с исключением.
class _BrokenStore implements ForgeTokenStore {
  _BrokenStore({this.failRead = true, this.failWrite = false});

  final bool failRead;
  final bool failWrite;
  String? _value;

  @override
  Future<String?> read() async {
    if (failRead) throw Exception('Keystore: ключ шифрования не найден');
    return _value;
  }

  @override
  Future<void> write(String value) async {
    if (failWrite) throw Exception('Keystore: запись отклонена');
    _value = value;
  }

  @override
  Future<void> delete() async => _value = null;
}

/// Модель-скрипт: отвечает по заранее заданному сценарию. Настоящий
/// провайдер — внешний сервис, в тесте ему не место.
class _ScriptedChat implements ForgeChat {
  _ScriptedChat(this.replies);

  /// Сценарий: список ответов по порядку. Каждый следующий вызов берёт
  /// следующий ответ, последний повторяется.
  final List<ForgeChatReply> replies;
  final List<List<Map<String, dynamic>>> seen = [];
  int _i = 0;

  @override
  Future<ForgeChatReply> complete(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  ) async {
    seen.add(messages.map(Map<String, dynamic>.from).toList());
    final reply = replies[_i < replies.length ? _i : replies.length - 1];
    _i++;
    return reply;
  }
}

/// Ответ-правка: пишет файл. Затем [finish] завершает ход и открывает PR.
ForgeChatReply _write(String path) => ForgeChatReply(
  toolCalls: [
    ForgeToolCall(
      id: 'w1',
      name: 'write_file',
      arguments: {'path': path, 'content': 'x'},
    ),
  ],
);

const _finish = ForgeChatReply(
  toolCalls: [
    ForgeToolCall(id: 'f1', name: 'finish', arguments: {'summary': 'Готово'}),
  ],
);

/// Текст пузыря чата. Реплики рисуются через SelectableText, поэтому
/// обычный find.text их не находит — ищем по обоим типам.
Finder _chatText(String value) => find.byWidgetPredicate(
  (w) => w is Text
      ? (w.data ?? w.textSpan?.toPlainText() ?? '') == value
      : w is SelectableText
      ? (w.data ?? '') == value
      : false,
);

Finder _chatTextContaining(String part) => find.byWidgetPredicate(
  (w) => w is Text
      ? (w.data ?? w.textSpan?.toPlainText() ?? '').contains(part)
      : w is SelectableText
      ? (w.data ?? '').contains(part)
      : false,
);

/// Развернуть поверхность теста: история чата уезжает вниз, и без высокого
/// экрана ListView просто не строит пузыри — их не найти в дереве.
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Нажать «Отправить» и дождаться конца хода. Чтение своего ключа ИИ —
/// настоящий доступ к хранилищу, и поддельные часы теста его не двигают,
/// поэтому ход прогоняем в «живом» времени.
Future<void> _sendAndSettle(WidgetTester tester) async {
  final sendButton = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Отправить'),
  );
  await tester.runAsync(() async {
    sendButton.onPressed!();
    // Ход целиком идёт в «живом» времени (чтение ключа, шаги агента), а
    // поддельные часы теста его не двигают. Даём ему завершиться.
    await Future<void>.delayed(const Duration(seconds: 2));
    // Мигающий курсор живёт настоящим таймером: снимаем фокус ещё здесь,
    // иначе таймер сработает после конца теста, когда виджета уже нет.
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pumpAndSettle();
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 1));
    tmpDir = await Directory.systemTemp.createTemp('keramika_forge_chat');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });
  testWidgets('агент запускается без ключа ИИ — на бесплатном пуле', (
    tester,
  ) async {
    _tallSurface(tester);
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
          chatFactory: (apiKey) => _ScriptedChat([_write('a.txt'), _finish]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'создай a.txt');
    await _sendAndSettle(tester);

    // Ход дошёл до PR: значит ключ ИИ не потребовался.
    expect(_chatTextContaining('pull/1'), findsOneWidget);
    expect(_chatTextContaining('ключ ИИ'), findsNothing);
    // Вопрос пользователя остался в истории чата.
    expect(_chatText('создай a.txt'), findsOneWidget);
  });

  testWidgets('вопрос без правок не создаёт ветку и PR', (tester) async {
    _tallSurface(tester);
    // Раньше любой запуск сразу заводил ветку и требовал finish. Теперь
    // на вопрос агент просто отвечает текстом.
    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.pumpWidget(
      _wrap(
        ForgeScreen(
          owner: 'wxstdo-boop',
          repo: 'Keramika',
          service: service,
          chatFactory: (apiKey) => _ScriptedChat([
            const ForgeChatReply(text: 'Точка входа в lib/main.dart.'),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'где точка входа?');
    await _sendAndSettle(tester);

    expect(_chatText('Точка входа в lib/main.dart.'), findsOneWidget);
    expect(_chatTextContaining('pull/'), findsNothing);
  });

  testWidgets('история чата восстанавливается из хранилища', (tester) async {
    // Разговор хранится в зашифрованном файле: здесь он уже записан, а
    // экран должен его показать. Чтение файла — настоящий ввод-вывод,
    // поэтому открытие идёт в «живом» времени.
    _tallSurface(tester);
    await tester.runAsync(() async {
      await ForgeChatStore.save(const [
        ForgeChatMessage(isUser: true, text: 'привет', ts: 1),
        ForgeChatMessage(isUser: false, text: 'Отвечаю из истории.', ts: 2),
      ]);
    });

    final store = InMemoryForgeTokenStore();
    await store.write('ghp_saved_token');
    final service = ForgeService(client: _okClient(), store: store);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(_chatText('привет'), findsOneWidget);
    expect(_chatText('Отвечаю из истории.'), findsOneWidget);
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

  testWidgets('сбой чтения хранилища не блокирует кнопку сохранения', (
    tester,
  ) async {
    // Жалоба: «вставил токен, а кнопка не активируется». Причина — флаг
    // загрузки снимался только при успешном чтении: одно исключение из
    // Keystore оставляло экран навсегда в состоянии «идёт загрузка».
    final service = ForgeService(
      client: _okClient(),
      store: _BrokenStore(failRead: true),
    );
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_typed_token');
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.byIcon(Icons.verified_user_outlined),
        matching: find.byType(FilledButton),
      ),
    );
    expect(
      button.onPressed,
      isNotNull,
      reason: 'кнопка обязана ожить даже после сбоя хранилища',
    );
  });

  testWidgets('токен сохраняется в хранилище по нажатию кнопки', (
    tester,
  ) async {
    final store = InMemoryForgeTokenStore();
    final service = ForgeService(client: _okClient(), store: store);
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_typed_token');
    await tester.pump();

    final finder = find.ancestor(
      of: find.byIcon(Icons.verified_user_outlined),
      matching: find.byType(FilledButton),
    );
    await tester.runAsync(() async {
      tester.widget<FilledButton>(finder).onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // Кнопка действительно кладёт токен в хранилище — иначе «вставил, а он
    // не сохранился» повторялось бы после каждого перезапуска.
    expect(await store.read(), 'ghp_typed_token');
  });

  testWidgets('сбой сети не мешает сохранить токен', (tester) async {
    // Сеть отвалилась — проверка не прошла, но введённый токен обязан
    // остаться в хранилище: иначе после перезапуска поле снова пустое.
    final store = InMemoryForgeTokenStore();
    final service = ForgeService(
      client: MockClient((_) async => throw const SocketException('нет сети')),
      store: store,
    );
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ghp_typed_token');
    await tester.pump();

    final finder = find.ancestor(
      of: find.byIcon(Icons.verified_user_outlined),
      matching: find.byType(FilledButton),
    );
    await tester.runAsync(() async {
      tester.widget<FilledButton>(finder).onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(await store.read(), 'ghp_typed_token');
    // И кнопка снова активна — проверку можно повторить.
    expect(tester.widget<FilledButton>(finder).onPressed, isNotNull);
  });

  testWidgets('сбой записи в хранилище показывается пользователю', (
    tester,
  ) async {
    // Молча «сохранить» при недоступном Keystore нельзя: пользователь решит,
    // что токен записан, и будет ждать, почему агент не работает.
    final service = ForgeService(
      client: _okClient(),
      store: _BrokenStore(failRead: false, failWrite: true),
    );
    await tester.pumpWidget(
      _wrap(
        ForgeScreen(owner: 'wxstdo-boop', repo: 'Keramika', service: service),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ghp_typed_token');
    await tester.pump();

    final finder = find.ancestor(
      of: find.byIcon(Icons.verified_user_outlined),
      matching: find.byType(FilledButton),
    );
    await tester.runAsync(() async {
      tester.widget<FilledButton>(finder).onPressed!.call();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(
      find.text(Translations.t('forgeTokenSaveFailed', tester.element(
        find.byType(ForgeScreen),
      ))),
      findsOneWidget,
    );
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
