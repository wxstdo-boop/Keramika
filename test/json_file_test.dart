import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agysha/services/json_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    JsonFile.resetForTesting();
    directory = await Directory.systemTemp.createTemp('agysha_json_test');
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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, null);
    await directory.delete(recursive: true);
    JsonFile.resetForTesting();
  });

  /// Подменяет настоящий Keystore простым словарём, чтобы тест шёл по
  /// реальному пути `_encryptionKey` → чтение ключа, а не в обход него.
  Map<String, String> fakeSecureStorage() {
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
          final args = (call.arguments as Map).cast<String, Object?>();
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return store[key];
            case 'write':
              store[key!] = args['value']! as String;
              return null;
            case 'delete':
              store.remove(key);
              return null;
            case 'readAll':
              return Map<String, String>.from(store);
            case 'containsKey':
              return store.containsKey(key);
            case 'deleteAll':
              store.clear();
              return null;
          }
          return null;
        });
    return store;
  }

  test(
    'writes authenticated encrypted envelopes and reads them back',
    () async {
      const value = '{"profile":"private data"}';

      await JsonFile.write('profile', value);

      final stored = await File(
        '${directory.path}/profile.json',
      ).readAsString();
      expect(stored, contains('agysha-json-v1'));
      expect(stored, isNot(contains('private data')));
      expect(await JsonFile.read('profile'), value);
    },
  );

  test('migrates legacy plaintext without changing its value', () async {
    const value = '{"profile":"legacy"}';
    await File('${directory.path}/profile.json').writeAsString(value);

    expect(await JsonFile.read('profile'), value);
    final stored = await File('${directory.path}/profile.json').readAsString();
    expect(stored, contains('agysha-json-v1'));
    expect(stored, isNot(contains('legacy')));
  });

  test('reads envelopes written under the legacy Keramika format', () async {
    const value = '{"profile":"from older build"}';
    await JsonFile.write('profile', value);

    final file = File('${directory.path}/profile.json');
    final migrated = (await file.readAsString()).replaceAll(
      'agysha-json-v1',
      'keramika-json-v1',
    );
    await file.writeAsString(migrated);

    JsonFile.resetForTesting();
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));

    expect(await JsonFile.read('profile'), value);
  });

  test('migrates the Keramika key so upgraded users keep their data', () async {
    const value = '{"habits":"kept after upgrade"}';
    final keyBytes = List<int>.filled(32, 42);
    final store = fakeSecureStorage();

    // Как выглядело хранилище у пользователя Keramika: файл зашифрован
    // ключом, который лежит под старым именем.
    JsonFile.useEncryptionKeyForTesting(keyBytes);
    await JsonFile.write('habits', value);
    final file = File('${directory.path}/habits.json');
    await file.writeAsString(
      (await file.readAsString()).replaceAll(
        'agysha-json-v1',
        'keramika-json-v1',
      ),
    );
    store['keramika_database_key_v1'] = base64Encode(keyBytes);

    // Обновление: ключ читается штатным путём, без подсказок теста.
    JsonFile.resetForTesting();

    expect(await JsonFile.read('habits'), value);
    expect(store['agysha_database_key_v1'], base64Encode(keyBytes));

    // Первая же запись переносит файл на текущий маркер.
    await JsonFile.write('habits', '{"habits":"updated"}');
    expect(await file.readAsString(), contains('agysha-json-v1'));
    expect(await JsonFile.read('habits'), '{"habits":"updated"}');
  });

  test('keeps a recovered store in the legacy dir when only it exists', () {
    final legacy = JsonFile.recoveryLocation(
      '/data',
      'v1',
      currentExists: false,
      legacyExists: true,
    );
    expect(legacy.path, '/data/keramika_recovery_v1');
    expect(legacy.namespace, 'keramika');

    final fresh = JsonFile.recoveryLocation(
      '/data',
      'abc123',
      currentExists: false,
      legacyExists: false,
    );
    expect(fresh.path, '/data/agysha_recovery_abc123');
    expect(fresh.namespace, 'agysha');

    final existing = JsonFile.recoveryLocation(
      '/data',
      'v1',
      currentExists: true,
      legacyExists: true,
    );
    expect(existing.path, '/data/agysha_recovery_v1');
    expect(existing.namespace, 'agysha');
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
