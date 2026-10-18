import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/services/json_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    JsonFile.resetForTesting();
    directory = await Directory.systemTemp.createTemp('keramika_json_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? directory.path
              : null,
        );
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
    JsonFile.resetForTesting();
  });

  test(
    'writes authenticated encrypted envelopes and reads them back',
    () async {
      const value = '{"profile":"private data"}';

      await JsonFile.write('profile', value);

      final stored = await File(
        '${directory.path}/profile.json',
      ).readAsString();
      expect(stored, contains('keramika-json-v1'));
      expect(stored, isNot(contains('private data')));
      expect(await JsonFile.read('profile'), value);
    },
  );

  test('migrates legacy plaintext without changing its value', () async {
    const value = '{"profile":"legacy"}';
    await File('${directory.path}/profile.json').writeAsString(value);

    expect(await JsonFile.read('profile'), value);
    final stored = await File('${directory.path}/profile.json').readAsString();
    expect(stored, contains('keramika-json-v1'));
    expect(stored, isNot(contains('legacy')));
  });

  test('refuses a wrong key and leaves the encrypted file untouched', () async {
    await JsonFile.write('profile', '{"profile":"private data"}');
    final file = File('${directory.path}/profile.json');
    final encryptedBefore = await file.readAsBytes();

    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 8));

    await expectLater(
      JsonFile.read('profile'),
      throwsA(isA<JsonFileException>()),
    );
    expect(await file.readAsBytes(), encryptedBefore);
  });

  test('merges disjoint object edits and rejects overlapping edits', () {
    final merged = JsonFile.mergeConcurrentJsonForTesting(
      'settings',
      '{"display":{"theme":"light","scale":1}}',
      '{"display":{"theme":"dark","scale":1}}',
      '{"display":{"theme":"light","scale":2}}',
    );

    expect(merged, '{"display":{"theme":"dark","scale":2}}');
    expect(
      () => JsonFile.mergeConcurrentJsonForTesting(
        'settings',
        '{"theme":"light"}',
        '{"theme":"dark"}',
        '{"theme":"rose"}',
      ),
      throwsA(isA<JsonFileConflictException>()),
    );
  });

  test('stale autosaves keep merged external edits on later writes', () async {
    const base = '{"a":1,"b":1}';
    const local = '{"a":2,"b":1}';
    const external = '{"a":1,"b":2}';
    const merged = '{"a":2,"b":2}';

    await JsonFile.write('profile', base);
    final localSnapshot = await JsonFile.read('profile');
    final remoteSnapshot = await JsonFile.read('profile');
    await JsonFile.writeWithSnapshot('profile', external, remoteSnapshot);
    await JsonFile.read('profile');
    final firstMerge = await JsonFile.writeWithSnapshot(
      'profile',
      local,
      localSnapshot,
    );
    expect(firstMerge, merged);
    expect(await JsonFile.read('profile'), merged);

    await JsonFile.writeWithSnapshot('profile', local, localSnapshot);
    expect(await JsonFile.read('profile'), merged);
  });

  test('stale snapshot cannot overwrite data created after its read', () async {
    const current = '{"value":"new"}';
    await JsonFile.write('profile', current);

    await expectLater(
      JsonFile.writeWithSnapshot('profile', '{"value":"stale"}', null),
      throwsA(isA<JsonFileConflictException>()),
    );
    expect(await JsonFile.read('profile'), current);
  });
}
