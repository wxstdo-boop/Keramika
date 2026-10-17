import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
  static const _keyName = 'keramika_database_key_v1';
  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();
  // Never let the plugin erase the secure-storage entry automatically after
  // a Keystore error. Losing this key would make the encrypted JSON files
  // unreadable, so keep the original state and fail closed for recovery.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  static final Map<String, String?> _observed = {};
  static final Map<String, Future<void>> _queues = {};
  static Directory? _dir;
  static Future<SecretKey>? _keyFuture;

  static Future<Directory> get _directory async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  static Future<void> initialize() async {
    await _encryptionKey();
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
        final stored = await _secureStorage.read(key: _keyName);
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
        await _secureStorage.write(key: _keyName, value: base64Encode(bytes));
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
      if (entity is! File ||
          (!entity.path.endsWith('.json') &&
              !entity.path.endsWith('.json.bak'))) {
        continue;
      }
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
