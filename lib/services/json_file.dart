import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'prefs.dart';

class JsonFileException implements Exception {
  const JsonFileException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

class JsonFileConflictException extends JsonFileException {
  const JsonFileConflictException(super.message);
}

class JsonFile {
  static const _format = 'keramika-json-v1';
  static const recoveryFormat = 'keramika-key-recovery-v1';
  static const _keyName = 'keramika_database_key_v1';
  static final _cipher = AesGcm.with256bits();
  static final _recoveryKdf = Pbkdf2.hmacSha256(iterations: 200000, bits: 256);
  static final _random = Random.secure();
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // resetOnError=true: при сбое инициализации EncryptedSharedPreferences
      // (например, неудачной миграции мастер-ключа «algorithm change»)
      // хранилище самоочищается и становится пригодным для записи. Иначе
      // сбой повторяется на каждом запуске и приложение больше не открывается:
      // ключ данных восстанавливается recovery-фразой, а не теряется молча.
      resetOnError: true,
      migrateOnAlgorithmChange: true,
      migrateWithBackup: true,
    ),
  );
  static final Map<String, String?> _observed = {};
  static final Map<String, Future<void>> _queues = {};
  static Directory? _dir;
  static Future<SecretKey>? _keyFuture;

  static Future<Directory> get _directory async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  static String generateRecoveryPhrase() {
    final entropy = List<int>.generate(32, (_) => _random.nextInt(256));
    final hexEntropy = entropy
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return bip39.entropyToMnemonic(hexEntropy);
  }

  static Future<bool> hasRecoveryEnvelope() async =>
      await exportRecoveryEnvelope() != null;

  static Future<String?> exportRecoveryEnvelope() async {
    if (kIsWeb) return globalPrefs.getString('keramika_key_recovery');
    final file = File('${(await _directory).path}/.keramika-key-recovery.json');
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<void> createRecoveryEnvelope(String phrase) async {
    final normalized = _normalizeRecoveryPhrase(phrase);
    if (!bip39.validateMnemonic(normalized) ||
        normalized.split(' ').length != 24) {
      throw const JsonFileException('Recovery phrase is invalid');
    }

    final key = await _encryptionKey();
    await _validateKeyAgainstData(key);
    final keyBytes = await key.extractBytes();
    final salt = _randomBytes(16);
    final derivedKey = await _deriveRecoveryKey(normalized, salt);
    final box = await _cipher.encrypt(
      keyBytes,
      secretKey: derivedKey,
      nonce: _randomBytes(12),
      aad: utf8.encode(recoveryFormat),
    );
    final envelope = jsonEncode({
      'format': recoveryFormat,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': 200000,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
    await _persistRecoveryEnvelope(envelope);
  }

  static Future<bool> testRecoveryPhrase(
    String phrase, {
    String? envelope,
  }) async {
    final normalized = _normalizeRecoveryPhrase(phrase);
    if (!bip39.validateMnemonic(normalized) ||
        normalized.split(' ').length != 24) {
      return false;
    }
    final storedEnvelope = envelope ?? await exportRecoveryEnvelope();
    if (storedEnvelope == null) return false;
    try {
      final candidate = await _unwrapRecoveryEnvelope(
        normalized,
        storedEnvelope,
      );
      await _validateKeyAgainstData(candidate);
      return true;
    } on Exception {
      return false;
    }
  }

  static Future<void> restoreEncryptionKey(
    String phrase, {
    required String envelope,
  }) async {
    final normalized = _normalizeRecoveryPhrase(phrase);
    if (!bip39.validateMnemonic(normalized) ||
        normalized.split(' ').length != 24) {
      throw const JsonFileException('Recovery phrase is invalid');
    }
    final candidate = await _unwrapRecoveryEnvelope(normalized, envelope);

    await _withKeyLock(_keyName, () async {
      String? stored;
      try {
        stored = await _secureStorage.read(key: _keyName);
      } on PlatformException {
        // The phrase is user-supplied and the candidate is authenticated
        // against the existing encrypted documents before it is written.
      }
      if (stored != null) {
        try {
          final existing = base64Decode(stored);
          final candidateBytes = await candidate.extractBytes();
          if (_constantTimeEqual(existing, candidateBytes)) {
            _keyFuture = Future.value(candidate);
            return;
          }
        } on FormatException {
          // An explicitly authenticated recovery phrase may replace an
          // unreadable stored value after verifying the encrypted documents.
        }
      }

      await _validateKeyAgainstData(candidate);
      final candidateBytes = await candidate.extractBytes();
      try {
        await _secureStorage.write(
          key: _keyName,
          value: base64Encode(candidateBytes),
        );
      } catch (error) {
        // Случайный сбой записи: понятная ошибка вместо крэша. При
        // resetOnError=true хранилище уже очищено от сломанного мастер-ключа,
        // поэтому повторная запись восстановленного ключа обычно проходит.
        throw JsonFileException(
          'The recovered key could not be written to secure storage',
          error,
        );
      }
      _keyFuture = Future.value(candidate);
    });
  }

  static Future<SecretKey> _unwrapRecoveryEnvelope(
    String phrase,
    String envelope,
  ) async {
    try {
      if (envelope.length > 4096) {
        throw const FormatException('Recovery envelope is too large');
      }
      final decoded = jsonDecode(envelope);
      if (decoded is! Map ||
          decoded['format'] != recoveryFormat ||
          decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          decoded['iterations'] != 200000) {
        throw const FormatException('Unsupported recovery envelope');
      }
      final salt = _decodeBase64Field(decoded, 'salt', length: 16);
      final nonce = _decodeBase64Field(decoded, 'nonce', length: 12);
      final ciphertext = _decodeBase64Field(decoded, 'ciphertext', length: 32);
      final mac = _decodeBase64Field(decoded, 'mac', length: 16);
      final derivedKey = await _deriveRecoveryKey(phrase, salt);
      final clear = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: derivedKey,
        aad: utf8.encode(recoveryFormat),
      );
      if (clear.length != 32) {
        throw const FormatException('Invalid recovered key length');
      }
      return SecretKey(clear);
    } catch (error) {
      throw JsonFileException('Recovery phrase or backup is invalid', error);
    }
  }

  static List<int> _decodeBase64Field(
    Map<dynamic, dynamic> envelope,
    String field, {
    required int length,
  }) {
    final value = envelope[field];
    if (value is! String) throw FormatException('Invalid $field');
    final bytes = base64Decode(value);
    if (bytes.length != length) throw FormatException('Invalid $field length');
    return bytes;
  }

  static Future<SecretKey> _deriveRecoveryKey(
    String phrase,
    List<int> salt,
  ) async {
    final seed = bip39.mnemonicToSeed(phrase);
    return _recoveryKdf.deriveKey(secretKey: SecretKey(seed), nonce: salt);
  }

  static String _normalizeRecoveryPhrase(String phrase) =>
      phrase.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');

  static List<int> _randomBytes(int count) =>
      List<int>.generate(count, (_) => _random.nextInt(256));

  static bool _constantTimeEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static Future<void> _validateKeyAgainstData(SecretKey candidate) async {
    Future<void> validate(String name, String raw) async {
      dynamic parsed;
      try {
        parsed = jsonDecode(raw);
      } on FormatException {
        return;
      }
      if (parsed is! Map || parsed['format'] != _format) return;
      try {
        final box = SecretBox(
          base64Decode(parsed['ciphertext'] as String),
          nonce: base64Decode(parsed['nonce'] as String),
          mac: Mac(base64Decode(parsed['mac'] as String)),
        );
        await _cipher.decrypt(box, secretKey: candidate);
      } catch (error) {
        throw JsonFileException(
          'Recovery key does not match encrypted "$name"; data was not changed',
          error,
        );
      }
    }

    if (kIsWeb) {
      for (final name in globalPrefs.getKeys()) {
        final raw = globalPrefs.get(name);
        if (raw is String) await validate(name, raw);
      }
      return;
    }
    final dir = await _directory;
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File &&
          (entity.path.endsWith('.json') ||
              entity.path.endsWith('.json.bak'))) {
        await validate(
          entity.uri.pathSegments.last,
          await entity.readAsString(),
        );
      }
    }
  }

  static Future<void> _persistRecoveryEnvelope(String envelope) async {
    if (kIsWeb) {
      if (!await globalPrefs.setString('keramika_key_recovery', envelope)) {
        throw const JsonFileException('Could not save recovery information');
      }
      return;
    }
    final target = File(
      '${(await _directory).path}/.keramika-key-recovery.json',
    );
    final temp = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(envelope, flush: true);
    try {
      if (!await target.exists()) {
        await temp.rename(target.path);
        return;
      }
      final backup = File('${target.path}.bak');
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      try {
        await temp.rename(target.path);
        await backup.delete();
      } catch (_) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  static Future<void> initialize() async {
    try {
      final key = await _encryptionKey();
      await _validateKeyAgainstData(key);
    } on JsonFileException {
      rethrow;
    } catch (error) {
      throw JsonFileException(
        'Could not access the encryption key; data was not changed',
        error,
      );
    }
  }

  @visibleForTesting
  static void useEncryptionKeyForTesting(List<int> key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key.length', 'Must be 32 bytes');
    }
    _keyFuture = Future.value(SecretKey(List<int>.unmodifiable(key)));
  }

  @visibleForTesting
  static void resetForTesting() {
    _dir = null;
    _keyFuture = null;
    _observed.clear();
    _queues.clear();
  }

  static Future<SecretKey> _encryptionKey() =>
      _keyFuture ??= _withKeyLock(_keyName, () async {
        String? stored;
        try {
          stored = await _secureStorage.read(key: _keyName);
        } catch (error) {
          // Сбой защищённого хранилища — например, неудачная миграция
          // мастер-ключа EncryptedSharedPreferences («Migration failed after
          // algorithm change»). Раньше PlatformException утекал до main(),
          // который перебрасывал не-JsonFileException и рисовал крэш-экран.
          // Превращаем в JsonFileException: main() ведёт её на стартовый
          // экран восстановления, где пользователь вводит recovery-фразу и
          // возвращает ключ. resetOnError=true очистил хранилище, поэтому
          // восстановленный ключ снова можно записать.
          throw JsonFileException(
            'Secure key storage is unavailable (master-key migration '
            'failed); restore the encryption key with the recovery phrase',
            error,
          );
        }
        if (stored != null) {
          try {
            final bytes = base64Decode(stored);
            if (bytes.length != 32) {
              throw const FormatException('Invalid key length');
            }
            return SecretKey(bytes);
          } catch (error) {
            throw JsonFileException(
              'The encryption key is unreadable; data was not changed',
              error,
            );
          }
        }

        if (await _hasEncryptedData()) {
          throw const JsonFileException(
            'The encryption key is missing while encrypted data exists; '
            'data was not changed',
          );
        }

        final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
        try {
          await _secureStorage.write(key: _keyName, value: base64Encode(bytes));
        } catch (error) {
          throw JsonFileException(
            'Could not store the encryption key in secure storage',
            error,
          );
        }
        return SecretKey(bytes);
      });

  static Future<bool> _hasEncryptedData() async {
    if (kIsWeb) {
      for (final key in globalPrefs.getKeys()) {
        final value = globalPrefs.get(key);
        if (value is String && _isEncryptedEnvelope(value)) return true;
      }
      return false;
    }

    final dir = await _directory;
    if (!await dir.exists()) return false;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.contains('.json')) continue;
      final raw = await entity.readAsString();
      if (_isEncryptedEnvelope(raw)) return true;
    }
    return false;
  }

  static bool _isEncryptedEnvelope(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map && decoded['format'] == _format;
    } on FormatException {
      return raw.contains(_format);
    }
  }

  static Future<T> _withKeyLock<T>(
    String key,
    Future<T> Function() action,
  ) async {
    final previous = _queues[key] ?? Future<void>.value();
    final gate = Completer<void>();
    _queues[key] = gate.future;
    await previous;
    try {
      if (kIsWeb) return await action();

      final dir = await _directory;
      await dir.create(recursive: true);
      final handle = await File(
        '${dir.path}/.$key.lock',
      ).open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive);
        try {
          return await action();
        } finally {
          await handle.unlock();
        }
      } finally {
        await handle.close();
      }
    } finally {
      gate.complete();
      if (identical(_queues[key], gate.future)) _queues.remove(key);
    }
  }

  static Future<String?> read(String key) => _withKeyLock(key, () async {
    final value = await _readPlainLocked(key);
    _observed[key] = value;
    return value;
  });

  static Future<void> write(String key, String value) async {
    final hasBase = _observed.containsKey(key);
    await _write(
      key,
      value,
      base: _observed[key],
      hasBase: hasBase,
      updateObserved: true,
    );
  }

  /// Writes against the exact document previously loaded by the caller.
  ///
  /// Returns the persisted document, including any safely merged external
  /// changes. Callers should advance their snapshot only when it matches the
  /// value represented by their in-memory state.
  static Future<String> writeWithSnapshot(
    String key,
    String value,
    String? base,
  ) => _write(key, value, base: base, hasBase: true, updateObserved: false);

  static Future<String> _write(
    String key,
    String value, {
    required String? base,
    required bool hasBase,
    required bool updateObserved,
  }) async {
    try {
      jsonDecode(value);
    } catch (error) {
      throw JsonFileException(
        'Refusing to store invalid JSON for "$key"',
        error,
      );
    }

    return _withKeyLock(key, () async {
      final current = await _readPlainLocked(key);
      var resolved = value;
      final externalChange = current != base;
      if (externalChange) {
        if (!hasBase || base == null || current == null) {
          throw JsonFileConflictException(
            'Concurrent change detected for "$key"; newer data was preserved',
          );
        }
        resolved = _mergeConcurrentJson(key, base, value, current);
      }

      if (current != resolved) await _persistPlainLocked(key, resolved);
      if (updateObserved) {
        // Readers in the same engine may still hold an older in-memory copy.
        // Their explicit snapshot writes remain protected by their own base.
        _observed[key] = externalChange ? base : resolved;
      }
      return resolved;
    });
  }

  static Future<String?> _readPlainLocked(String key) async {
    String? raw;
    if (kIsWeb) {
      raw = globalPrefs.getString(key);
    } else {
      final dir = await _directory;
      await dir.create(recursive: true);
      final file = File('${dir.path}/$key.json');
      final backup = File('${file.path}.bak');
      if (!await file.exists() && await backup.exists()) {
        await backup.rename(file.path);
      }
      if (await file.exists()) raw = await file.readAsString();
    }
    if (raw == null) return null;

    final decoded = await _decode(key, raw);
    if (!decoded.$2) await _persistPlainLocked(key, decoded.$1);
    return decoded.$1;
  }

  static Future<(String, bool)> _decode(String key, String raw) async {
    dynamic parsed;
    try {
      parsed = jsonDecode(raw);
    } catch (error) {
      throw JsonFileException(
        'Stored value for "$key" is not valid JSON',
        error,
      );
    }

    if (parsed is Map && parsed['format'] == _format) {
      try {
        final box = SecretBox(
          base64Decode(parsed['ciphertext'] as String),
          nonce: base64Decode(parsed['nonce'] as String),
          mac: Mac(base64Decode(parsed['mac'] as String)),
        );
        final clear = await _cipher.decrypt(
          box,
          secretKey: await _encryptionKey(),
        );
        return (utf8.decode(clear), true);
      } catch (error) {
        throw JsonFileException(
          'Could not decrypt "$key"; original data was left untouched',
          error,
        );
      }
    }
    return (raw, false);
  }

  static Future<void> _persistPlainLocked(String key, String value) async {
    final encrypted = await _encode(value);
    if (kIsWeb) {
      if (!await globalPrefs.setString(key, encrypted)) {
        throw JsonFileException('Could not persist "$key"');
      }
      return;
    }

    final dir = await _directory;
    await dir.create(recursive: true);
    final target = File('${dir.path}/$key.json');
    final temp = File(
      '${target.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(encrypted, flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException catch (error) {
      if (!Platform.isWindows || !await target.exists()) {
        throw JsonFileException('Could not atomically replace "$key"', error);
      }
      final backup = File('${target.path}.bak');
      if (await backup.exists()) await backup.delete();
      await target.rename(backup.path);
      try {
        await temp.rename(target.path);
      } catch (replaceError) {
        if (!await target.exists() && await backup.exists()) {
          await backup.rename(target.path);
        }
        throw JsonFileException(
          'Could not replace "$key"; old data restored',
          replaceError,
        );
      }
      await backup.delete();
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  static Future<String> _encode(String value) async {
    try {
      final box = await _cipher.encrypt(
        utf8.encode(value),
        secretKey: await _encryptionKey(),
      );
      return jsonEncode({
        'format': _format,
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      });
    } catch (error) {
      throw JsonFileException('Could not encrypt JSON data', error);
    }
  }

  static Future<void> remove(String key) => _withKeyLock(key, () async {
    final current = await _readPlainLocked(key);
    if (_observed.containsKey(key) && current != _observed[key]) {
      throw JsonFileConflictException(
        'Concurrent change detected for "$key"; newer data was preserved',
      );
    }
    if (kIsWeb) {
      await globalPrefs.remove(key);
    } else {
      final dir = await _directory;
      final file = File('${dir.path}/$key.json');
      if (await file.exists()) await file.delete();
      final backup = File('${file.path}.bak');
      if (await backup.exists()) await backup.delete();
    }
    _observed[key] = null;
  });

  static String _canonical(dynamic value) {
    dynamic normalize(dynamic item) {
      if (item is Map) {
        final keys = item.keys.cast<String>().toList()..sort();
        return <String, dynamic>{
          for (final key in keys) key: normalize(item[key]),
        };
      }
      if (item is List) return item.map(normalize).toList();
      return item;
    }

    return jsonEncode(normalize(value));
  }

  static bool _equal(dynamic a, dynamic b) => _canonical(a) == _canonical(b);

  static String _mergeConcurrentJson(
    String key,
    String base,
    String local,
    String remote,
  ) {
    try {
      return jsonEncode(
        _mergeValue(
          key,
          jsonDecode(base),
          jsonDecode(local),
          jsonDecode(remote),
        ),
      );
    } on JsonFileException {
      rethrow;
    } catch (error) {
      throw JsonFileConflictException('Cannot safely merge "$key": $error');
    }
  }

  @visibleForTesting
  static String mergeConcurrentJsonForTesting(
    String key,
    String base,
    String local,
    String remote,
  ) => _mergeConcurrentJson(key, base, local, remote);

  static dynamic _mergeValue(
    String key,
    dynamic base,
    dynamic local,
    dynamic remote,
  ) {
    if (_equal(local, base)) return remote;
    if (_equal(remote, base) || _equal(local, remote)) return local;
    if (base is Map && local is Map && remote is Map) {
      final result = <String, dynamic>{};
      final keys = <String>{
        ...base.keys.cast<String>(),
        ...local.keys.cast<String>(),
        ...remote.keys.cast<String>(),
      };
      for (final field in keys) {
        final slot = _mergeSlot(
          key,
          (base.containsKey(field), base[field]),
          (local.containsKey(field), local[field]),
          (remote.containsKey(field), remote[field]),
        );
        if (slot.$1) result[field] = slot.$2;
      }
      return result;
    }
    if (base is List && local is List && remote is List) {
      return _mergeLists(key, base, local, remote);
    }
    throw JsonFileConflictException(
      'Overlapping edits for "$key"; newer data was preserved',
    );
  }

  static (bool, dynamic) _mergeSlot(
    String key,
    (bool, dynamic) base,
    (bool, dynamic) local,
    (bool, dynamic) remote,
  ) {
    if (_sameSlot(local, base)) return remote;
    if (_sameSlot(remote, base) || _sameSlot(local, remote)) return local;
    if (base.$1 && local.$1 && remote.$1) {
      return (true, _mergeValue(key, base.$2, local.$2, remote.$2));
    }
    throw JsonFileConflictException(
      'Concurrent add/remove conflict for "$key"; newer data was preserved',
    );
  }

  static bool _sameSlot((bool, dynamic) a, (bool, dynamic) b) =>
      a.$1 == b.$1 && (!a.$1 || _equal(a.$2, b.$2));

  static String _identity(dynamic item) {
    if (item is Map) {
      final id = item['id'];
      if (id is String && id.isNotEmpty) return 'id:$id';
      final ts = item['ts'];
      if (ts is num) return 'ts:$ts:${item['isUser']}:${item['text']}';
    }
    return 'value:${_canonical(item)}';
  }

  static Map<String, dynamic> _index(String key, List<dynamic> items) {
    final indexed = <String, dynamic>{};
    for (final item in items) {
      final id = _identity(item);
      if (indexed.containsKey(id)) {
        throw JsonFileConflictException(
          'Duplicate entries cannot be merged safely for "$key"',
        );
      }
      indexed[id] = item;
    }
    return indexed;
  }

  static List<dynamic> _mergeLists(
    String key,
    List<dynamic> base,
    List<dynamic> local,
    List<dynamic> remote,
  ) {
    final b = _index(key, base);
    final l = _index(key, local);
    final r = _index(key, remote);
    final bo = base.map(_identity).toList();
    final lo = local.map(_identity).toList();
    final ro = remote.map(_identity).toList();
    final shared = bo
        .where((id) => l.containsKey(id) && r.containsKey(id))
        .toList();
    final localShared = lo
        .where((id) => b.containsKey(id) && r.containsKey(id))
        .toList();
    final remoteShared = ro
        .where((id) => b.containsKey(id) && l.containsKey(id))
        .toList();
    final localMoved = !_sameOrder(localShared, shared);
    final remoteMoved = !_sameOrder(remoteShared, shared);
    if (localMoved && remoteMoved && !_sameOrder(localShared, remoteShared)) {
      throw JsonFileConflictException(
        'Concurrent reorder conflict for "$key"; newer data was preserved',
      );
    }

    final merged = <String, dynamic>{};
    for (final id in <String>{...b.keys, ...l.keys, ...r.keys}) {
      final slot = _mergeSlot(
        key,
        (b.containsKey(id), b[id]),
        (l.containsKey(id), l[id]),
        (r.containsKey(id), r[id]),
      );
      if (slot.$1) merged[id] = slot.$2;
    }
    final order = <String>[];
    final seen = <String>{};
    for (final id in [...(localMoved ? lo : ro), ...ro, ...lo]) {
      if (merged.containsKey(id) && seen.add(id)) order.add(id);
    }
    return order.map((id) => merged[id]).toList();
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
