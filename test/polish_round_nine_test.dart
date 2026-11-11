import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/screens/profile_screen.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/profile_service.dart';

/// Регрессы полировки девятого круга:
///  * рейтинг ограничен 50 друзьями — дальше `addFriend` отказывает, а кнопка
///    добавления гаснет;
///  * строки рейтинга живут в общем «слое» и переезжают при смене очков
///    (`AnimatedPositioned` по ключу друга), а не переставляются мгновенно.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
    tmpDir = await Directory.systemTemp.createTemp('keramika_round_nine');
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
    // Профиль читается в настоящей async-зоне: внутри testWidgets
    // (fake-async) реальный файловый I/O виснет — см. AGENTS.md.
    await ProfileService().load();
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

  test('в рейтинг влезает ровно 50 друзей, 51-й не добавляется', () async {
    final svc = ProfileService();
    for (var i = 0; i < ProfileService.maxFriends; i++) {
      final ok = await svc.addFriend(
        name: 'Друг $i',
        colorIndex: i % 4,
        score: i,
      );
      expect(ok, isTrue, reason: 'друг №${i + 1} должен добавляться');
    }
    expect(svc.friends.length, ProfileService.maxFriends);
    expect(svc.canAddFriend, isFalse);

    final overflow = await svc.addFriend(
      name: 'Лишний',
      colorIndex: 0,
      score: 999,
    );
    expect(overflow, isFalse);
    expect(svc.friends.length, ProfileService.maxFriends);
    expect(svc.friends.any((f) => f.name == 'Лишний'), isFalse);
  });

  testWidgets('строки рейтинга переезжают при смене очков, а не щёлкают', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final svc = ProfileService();
    // Друзья создаются в реальной async-зоне: внутри fake-async запись файла
    // виснет (см. AGENTS.md).
    await tester.runAsync(() async {
      await svc.addFriend(name: 'Низ', colorIndex: 0, score: 1);
      await svc.addFriend(name: 'Верх', colorIndex: 1, score: 500);
    });

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Строки живут в общем слое и анимируют `top`.
    expect(find.byType(AnimatedPositioned), findsWidgets);

    final lowBefore = tester.getTopLeft(find.text('Низ')).dy;
    final topBefore = tester.getTopLeft(find.text('Верх')).dy;
    expect(topBefore, lessThan(lowBefore), reason: '«Верх» стоит выше «Низа»');

    // Меняем очки — места должны меняться АНИМАЦИЕЙ, а не мгновенно.
    final top = svc.friends.firstWhere((f) => f.name == 'Верх');
    await tester.runAsync(() async {
      await svc.updateFriend(top.copyWith(score: 0));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // В середине анимации строка ещё не на конечном месте.
    expect(
      tester.getTopLeft(find.text('Низ')).dy,
      isNot(closeTo(lowBefore, 0.5)),
    );

    await tester.pumpAndSettle();
    final lowAfter = tester.getTopLeft(find.text('Низ')).dy;
    final topAfter = tester.getTopLeft(find.text('Верх')).dy;
    expect(lowAfter, lessThan(topAfter), reason: '«Низ» уехал наверх');
  });
}
