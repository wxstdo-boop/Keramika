import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/services/json_file.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const secureStorageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

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
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 7));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
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

  test('missing key never creates a replacement over encrypted data', () async {
    await JsonFile.write('profile', '{"profile":"private data"}');
    final file = File('${directory.path}/profile.json');
    final encryptedBefore = await file.readAsBytes();
    JsonFile.resetForTesting();

    await expectLater(
      JsonFile.initialize(),
      throwsA(
        isA<JsonFileException>().having(
          (error) => error.message,
          'message',
          contains('encryption key is missing'),
        ),
      ),
    );
    expect(await file.readAsBytes(), encryptedBefore);
  });

  test('secure-storage read failure never writes a replacement key', () async {
    await JsonFile.write('profile', '{"profile":"private data"}');
    final file = File('${directory.path}/profile.json');
    final encryptedBefore = await file.readAsBytes();
    JsonFile.resetForTesting();
    var writes = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          if (call.method == 'read') {
            throw PlatformException(code: 'KeyUnavailable');
          }
          if (call.method == 'write') writes++;
          return null;
        });

    await expectLater(JsonFile.initialize(), throwsA(isA<JsonFileException>()));
    expect(writes, 0);
    expect(await file.readAsBytes(), encryptedBefore);
  });

  test(
    'enables backed-up v9-to-v10 migration without automatic reset',
    () async {
      final optionsSeen = <Map<dynamic, dynamic>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            optionsSeen.add(
              Map<dynamic, dynamic>.from(arguments['options'] as Map),
            );
            return null;
          });
      JsonFile.resetForTesting();

      await JsonFile.initialize();

      expect(optionsSeen, hasLength(2));
      for (final options in optionsSeen) {
        expect(
          options['keyCipherAlgorithm'],
          'RSA_ECB_OAEPwithSHA_256andMGF1Padding',
        );
        expect(options['storageCipherAlgorithm'], 'AES_GCM_NoPadding');
        expect(options['migrateOnAlgorithmChange'], 'true');
        expect(options['migrateWithBackup'], 'true');
        expect(options['resetOnError'], 'false');
      }
    },
  );

  test(
    'recovery phrase is strong, verified, and never stored in the envelope',
    () async {
      final phrase = JsonFile.generateRecoveryPhrase();
      expect(phrase.split(' '), hasLength(24));

      const value = '{"profile":"private data"}';
      await JsonFile.write('profile', value);
      await JsonFile.createRecoveryEnvelope(phrase);
      final envelope = await JsonFile.exportRecoveryEnvelope();

      expect(envelope, isNotNull);
      expect(envelope, isNot(contains(phrase)));
      expect(envelope, isNot(contains(base64Encode(List<int>.filled(32, 7)))));
      expect(await JsonFile.testRecoveryPhrase(phrase), isTrue);
      expect(
        await JsonFile.testRecoveryPhrase(JsonFile.generateRecoveryPhrase()),
        isFalse,
      );
      expect(await JsonFile.read('profile'), value);
    },
  );

  test(
    'recovery restores only a verified missing key without changing files',
    () async {
      String? storedKey;
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            if (call.method == 'read') return storedKey;
            if (call.method == 'write') {
              writes++;
              storedKey = arguments['value'] as String;
            }
            return null;
          });
      const value = '{"profile":"private data"}';
      await JsonFile.write('profile', value);
      final phrase = JsonFile.generateRecoveryPhrase();
      await JsonFile.createRecoveryEnvelope(phrase);
      final envelope = (await JsonFile.exportRecoveryEnvelope())!;
      final file = File('${directory.path}/profile.json');
      final encryptedBefore = await file.readAsBytes();

      JsonFile.resetForTesting();
      await expectLater(
        JsonFile.restoreEncryptionKey(
          JsonFile.generateRecoveryPhrase(),
          envelope: envelope,
        ),
        throwsA(isA<JsonFileException>()),
      );
      expect(writes, 0);
      expect(await file.readAsBytes(), encryptedBefore);

      await JsonFile.restoreEncryptionKey(phrase, envelope: envelope);
      expect(writes, 1);
      expect(await JsonFile.read('profile'), value);
      expect(await file.readAsBytes(), encryptedBefore);
    },
  );

  test('verified recovery phrase can replace a wrong stored key', () async {
    String? storedKey;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
          final arguments = call.arguments as Map<dynamic, dynamic>;
          if (call.method == 'read') return storedKey;
          if (call.method == 'write') {
            storedKey = arguments['value'] as String;
          }
          return null;
        });
    const value = '{"profile":"private data"}';
    await JsonFile.write('profile', value);
    final phrase = JsonFile.generateRecoveryPhrase();
    await JsonFile.createRecoveryEnvelope(phrase);
    final envelope = (await JsonFile.exportRecoveryEnvelope())!;
    storedKey = base64Encode(List<int>.filled(32, 8));

    JsonFile.resetForTesting();
    await JsonFile.restoreEncryptionKey(phrase, envelope: envelope);

    expect(storedKey, base64Encode(List<int>.filled(32, 7)));
    expect(await JsonFile.read('profile'), value);
  });

  test(
    'verified recovery works when secure storage cannot read its old key',
    () async {
      String? storedKey;
      var writes = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(secureStorageChannel, (call) async {
            final arguments = call.arguments as Map<dynamic, dynamic>;
            if (call.method == 'read') {
              if (writes == 0) {
                throw PlatformException(code: 'KeyUnavailable');
              }
              return storedKey;
            }
            if (call.method == 'write') {
              writes++;
              storedKey = arguments['value'] as String;
            }
            return null;
          });
      const value = '{"profile":"private data"}';
      await JsonFile.write('profile', value);
      final phrase = JsonFile.generateRecoveryPhrase();
      await JsonFile.createRecoveryEnvelope(phrase);
      final envelope = (await JsonFile.exportRecoveryEnvelope())!;
      final file = File('${directory.path}/profile.json');
      final encryptedBefore = await file.readAsBytes();

      JsonFile.resetForTesting();
      await JsonFile.restoreEncryptionKey(phrase, envelope: envelope);

      expect(writes, 1);
      expect(await JsonFile.read('profile'), value);
      expect(await file.readAsBytes(), encryptedBefore);
    },
  );

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
