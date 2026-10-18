import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/forge_screen.dart';
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
  return http.Response('{}', 200, headers: {'content-type': 'application/json'});
});

Widget _wrap(Widget child) => LocaleProvider(
  locale: const Locale('ru'),
  child: MaterialApp(home: child),
);

void main() {
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
