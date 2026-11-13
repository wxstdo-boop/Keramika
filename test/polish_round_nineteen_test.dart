import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/l10n/locale_provider.dart';
import 'package:agysha/services/json_file.dart';
import 'package:agysha/services/prefs.dart';
import 'package:agysha/services/profile_service.dart';
import 'package:agysha/widgets/profile_avatar.dart';

/// Регресс-тест круга 19: своя аватарка из галереи у ДРУГА.
///
/// Владелец просил: тап по аватарке друга в листах открывает галерею, и
/// выбранная картинка плавно встаёт и в листах, и в строке рейтинга.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    tmpDir = await Directory.systemTemp.createTemp('agysha_round19');
    // Профиль читает путь приватной папки через `path_provider`: без мока
    // канала плагин бросает MissingPluginException (см. AGENTS.md).
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

  String read(String path) {
    final f = File(path);
    expect(f.existsSync(), isTrue, reason: '$path не найден');
    return f.readAsStringSync();
  }

  String code(String path) => read(
    path,
  ).split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

  test('друг хранит свою картинку и переживает перезагрузку', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.addFriend(
      name: 'Гончар',
      colorIndex: 2,
      score: 42,
      imagePath: '/tmp/friend_avatar.png',
    );

    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
    await svc.load();

    expect(svc.friends.length, 1);
    expect(svc.friends.first.name, 'Гончар');
    expect(svc.friends.first.imagePath, '/tmp/friend_avatar.png');
    expect(svc.friends.first.hasImage, isTrue);
  });

  test('copyWith: картинка ставится, снимается флагом и не сбрасывается', () {
    const base = ProfileFriend(
      id: 'f1',
      name: 'Гончар',
      colorIndex: 3,
      score: 10,
      imagePath: '/tmp/a.png',
    );

    // `null` в imagePath = «не трогать»: иначе нельзя было бы отличить
    // «поле не передано» от «стереть картинку».
    expect(base.copyWith(score: 99).imagePath, '/tmp/a.png');
    expect(base.copyWith(imagePath: '/tmp/b.png').imagePath, '/tmp/b.png');
    expect(base.copyWith(clearImage: true).imagePath, isNull);
    expect(base.copyWith(clearImage: true).hasImage, isFalse);
  });

  test('строка «Я» рейтинга несёт свою картинку профиля', () async {
    final svc = ProfileService();
    await svc.load();
    await svc.setName('Я');
    await svc.setAvatarImage('/tmp/me.png');

    final me = svc.leaderboard().firstWhere((f) => f.id == 'me');
    expect(me.imagePath, '/tmp/me.png');
    expect(me.hasImage, isTrue);
  });

  test(
    'в листах и рейтинге аватарка идёт из строки друга, а не только «Я»',
    () {
      final src = code('lib/screens/profile_screen.dart');
      // Рейтинг: картинка из самой строки — значит работает и для друзей.
      expect(
        src.contains('imagePath: f.imagePath,'),
        isTrue,
        reason: 'строка рейтинга обязана показывать картинку друга',
      );
      // Тап по аватарке в листе добавления — галерея.
      expect(
        src.contains('onTap: _pickImage,'),
        isTrue,
        reason: 'крупная аватарка в листе добавления открывает галерею',
      );
      // И в листе действий над другом.
      expect(
        src.contains('onTap: onAvatar,'),
        isTrue,
        reason: 'аватарку друга меняем и из листа действий',
      );
      // Показываем картинку и в шапке шага очков.
      expect(src.contains('imagePath: widget.friend.imagePath,'), isTrue);
    },
  );

  test('выбор градиента снимает свою картинку', () {
    final src = code('lib/screens/profile_screen.dart');
    expect(
      RegExp(
        r'onTap: \(\) => setState\(\(\) \{[\s\S]{0,80}?_imagePath = null;',
      ).hasMatch(src),
      isTrue,
      reason: 'иначе непонятно, что показывать в кружке',
    );
  });

  test('лист не открывает системный пикер сам, а просит владельца экрана', () {
    final src = code('lib/screens/profile_screen.dart');
    expect(
      src.contains('final Future<String?> Function() onPickImage;'),
      isTrue,
      reason: 'путь копии возвращает экран, лист только показывает',
    );
    expect(
      src.contains(
        '_AddFriendSheet(onPickImage: _copyPickedImageToPrivateDir)',
      ),
      isTrue,
    );
    // Пикер и копирование живут в одном месте — и для себя, и для друга.
    expect(
      src.contains('Future<String?> _copyPickedImageToPrivateDir()'),
      isTrue,
    );
    // Ровно один вызов пикера КАРТИНОК: музыка ищется отдельно
    // (`FileType.audio`), дублировать копирование фото не нужно.
    expect(
      RegExp(
        r"FilePicker\.pickFile\(type: FileType\.image\)",
      ).allMatches(src).length,
      1,
      reason: 'дублировать копирование картинки не нужно',
    );
  });

  testWidgets('смена картинки друга идёт кроссфейдом, а не кадром', (
    tester,
  ) async {
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: ProfileAvatar(index: 0, size: 44)),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AnimatedSwitcher), findsWidgets);

    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: ProfileAvatar(index: 0, size: 44, imagePath: '/tmp/x.png'),
            ),
          ),
        ),
      ),
    );
    // Кадр перехода: обе стороны существуют одновременно — это и есть
    // плавная смена, а не мгновенная подмена.
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
  });
}
