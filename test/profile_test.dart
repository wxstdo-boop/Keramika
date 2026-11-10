import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/models/task.dart';
import 'package:keramika/screens/profile_screen.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/profile_service.dart';
import 'package:keramika/services/task_service.dart';
import 'package:keramika/widgets/animated_blur_title.dart';
import 'package:keramika/widgets/online_dot.dart';
import 'package:keramika/widgets/profile_avatar.dart';

/// Профиль «керамика-юзера»: имя, аватарка, онлайн-статус, рейтинг, музыка
/// и события. Данные — локальные, поэтому тесты работают с реальным
/// хранилищем во временной папке, без моков сервиса.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    tmpDir = await Directory.systemTemp.createTemp('keramika_profile');
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
    // Профиль читается здесь, в настоящей async-зоне: внутри testWidgets
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

  test('имя, аватарка и друзья переживают перезагрузку профиля', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.setName('Керамик');
    await svc.setAvatarIndex(5);
    await svc.addFriend(name: 'Гончар', colorIndex: 2, score: 42);

    // Свежий разбор файла: значения должны прийти с диска, а не из памяти.
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    await svc.load();

    expect(svc.name, 'Керамик');
    expect(svc.avatarIndex, 5);
    expect(svc.friends.length, 1);
    expect(svc.friends.first.name, 'Гончар');
    expect(svc.friends.first.score, 42);
  });

  test('онлайн-статус сохраняется отдельно и переживает перезапуск', () async {
    final svc = ProfileService();
    await svc.load();
    expect(svc.online, isFalse);

    await svc.setOnline(true);
    expect(svc.online, isTrue);

    // Онлайн лежит в prefs, а не в файле профиля: читаем заново тем же
    // способом, каким его увидит шапка после перезапуска.
    expect(globalPrefs.getBool('profile_online'), isTrue);
  });

  test('рейтинг сортирует себя по очкам и считает свой счёт из активности', () async {
    // Реальная активность: привычка со стриком 10 и выполненная задача.
    await HabitService().load();
    for (final h in HabitService().habits.toList()) {
      await HabitService().remove(h.id);
    }
    await HabitService().add(
      Habit(
        id: 'h1',
        name: 'Зарядка',
        iconCodePoint: 57690,
        activeDays: const [1, 2, 3, 4, 5, 6, 7],
        streak: 10,
      ),
    );
    await TaskService().load();
    for (final t in TaskService().tasks.toList()) {
      await TaskService().remove(t.id);
    }
    await TaskService().add(Task(id: 't1', title: 'Дело', done: true));

    final svc = ProfileService();
    await svc.load();
    await svc.setName('Я');
    await svc.addFriend(name: 'Слабак', colorIndex: 1, score: 1);

    final board = svc.leaderboard();
    expect(board.first.id, 'me', reason: 'свой счёт должен быть выше');
    expect(svc.localScore(), greaterThanOrEqualTo(11));
    expect(board.last.name, 'Слабак');
  });

  testWidgets('кружок онлайна есть НАД «K» и открывает профиль по тапу', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: AnimatedBlurTitle(onOnlineTap: () => opened = true),
          ),
        ),
      ),
    );

    // Новогодней шапки больше нет — остаётся только кружок онлайна.
    expect(find.byType(OnlineDot), findsOneWidget);
    expect(find.textContaining('🎅'), findsNothing);

    // Кружок стоит НАД буквой «K»: его центр выше центра буквы.
    final dotCenter = tester.getCenter(find.byType(OnlineDot));
    final kCenter = tester.getCenter(find.text('K'));
    expect(
      dotCenter.dy,
      lessThan(kCenter.dy),
      reason: 'кружок должен быть сверху, а не под буквой',
    );

    await tester.tap(find.byType(OnlineDot));
    await tester.pump();
    expect(opened, isTrue, reason: 'тап по кружку должен открывать профиль');
  });

  group('шапка с именем юзера', () {
    // Имя ставим в setUp (реальная async-зона), а не внутри testWidgets:
    // запись профиля — файловый I/O, а он в fake-async виснет (см. AGENTS.md).
    setUp(() async {
      await ProfileService().load();
      await ProfileService().setName('Гончар');
    });
    tearDown(() async {
      await ProfileService().setName('');
    });

    testWidgets('в шапке вместо «Keramika» показывается имя юзера', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: AnimatedBlurTitle(onOnlineTap: () {})),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Гончар'), findsOneWidget);
      expect(find.text('K'), findsNothing);
      expect(find.text('eramika'), findsNothing);
      // Кружок онлайна остаётся — он висит над первой буквой имени.
      expect(find.byType(OnlineDot), findsOneWidget);
    });
  });

  test('короткое имя обрезается до 10 символов', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.setName('ОченьДлинноеИмя');
    expect(svc.name, 'ОченьДлинн');
    expect(svc.name.length, ProfileService.maxNameLength);

    // Пробелы по краям снимаются, внутри — сохраняются.
    await svc.setName('  Гончар  ');
    expect(svc.name, 'Гончар');
  });

  testWidgets('аватарка меняет цвет по индексу, вариантов достаточно', (
    tester,
  ) async {
    expect(profileAvatarVariants.length, greaterThan(20));
    expect(profileAvatarColors(0), isNot(equals(profileAvatarColors(1))));
    // Индекс не должен выходить за границы списка.
    expect(profileAvatarColors(profileAvatarVariants.length + 3), isNotEmpty);
  });

  testWidgets('экран профиля показывает все блоки', (tester) async {
    tester.view.physicalSize = const Size(411, 891) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(home: ProfileScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Профиль'), findsOneWidget);
    expect(find.text('Короткое имя'), findsOneWidget);
    expect(find.text('Онлайн-статус'), findsOneWidget);
    expect(find.text('Своя музыка'), findsOneWidget);

    // Остальные блоки ниже сгиба — доскролливаем, а не притворяемся, что
    // они на первом экране.
    await tester.dragUntilVisible(
      find.text('События keramika.ru'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Рейтинг друзей'), findsOneWidget);
    expect(find.text('События keramika.ru'), findsOneWidget);
    // Свой ник в рейтинге идёт первым, пока друзей нет.
    expect(find.text('Я'), findsOneWidget);
  });

  test('имя можно сохранить и оно появляется в шапке профиля', () async {
    await ProfileService().setName('Керамик');
    expect(ProfileService().displayName, 'Керамик');
  });
}
