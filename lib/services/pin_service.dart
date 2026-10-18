import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'prefs.dart';

class PinService {
  static const _key = 'app_pin';
  static const _format = 'pbkdf2-sha256-v1';
  // 4-значный ПИН защищён только на устройстве: «агрессор» не может
  // выкачать salt+hash для оффлайн-брута, а физические попытки ввода
  // ограничены UI. Поэтому KDF сознательно лёгкий — 100k итераций (ровно
  // _minimumIterations) вместо прежних 210k: разблокировка с первого раза
  // стала ~2x быстрее, а старые верификаторы на 210k по-прежнему проходят
  // проверку _decodeVerifier (диапазон _minimumIterations.._maximumIterations)
  // и верифицируются на собственных 210k.
  static const _iterations = 100000;
  static const _minimumIterations = 100000;
  static const _maximumIterations = 1000000;
  static final _random = Random.secure();
  static bool? _hasPinCache;

  /// Кэш KDF на время сессии: результат PBKDF2 — чистая функция
  /// (PIN, salt, iterations), поэтому повторная разблокировка в том же
  /// процессе (после блокировки при выходе в фон) не пересчитывает KDF и
  /// проходит мгновенно. В значениях лежат только результаты KDF (32
  /// байта на запись); исходный PIN хранится лишь в ключе-идентификаторе
  /// пары (соль, PIN). Потолок [_maxKdfCacheEntries] с LRU-сбросом
  /// старейших ограничивает память при локальном переборе псевдо-PIN.
  static final Map<String, List<int>> _kdfCache = {};
  static const _maxKdfCacheEntries = 16;

  /// Запоминает результат KDF; при переполнении сбрасывает старейшие
  /// записи (Map в Dart итерируется в порядке вставки — oldest first).
  static void _rememberKdf(String key, List<int> derived) {
    _kdfCache[key] = derived;
    while (_kdfCache.length > _maxKdfCacheEntries) {
      _kdfCache.remove(_kdfCache.keys.first);
    }
  }

  /// Идентификатор записи кэша. Ключ — (salt, PIN): результат KDF зависит
  /// от обоих входов и от iterations, которые выводятся из соли. Без PIN
  /// в ключе разные пины дали бы один и тот же KDF-результат на общей
  /// соли, и верификация ошибочно принимала бы чужой пин.
  static String _kdfCacheKey(String saltB64, String pin) => '$saltB64:$pin';

  static bool hasPinSync() => _hasPinCache ?? false;

  @visibleForTesting
  static void resetCacheForTesting() {
    _hasPinCache = null;
    _kdfCache.clear();
  }

  static Future<bool> hasPin() async {
    final stored = globalPrefs.getString(_key);
    final has = stored != null && stored.isNotEmpty;
    _hasPinCache = has;
    // Presence checks run during app startup. Defer legacy plaintext
    // migration until verifyPin accepts it, so KDF work never delays the
    // first lock-screen frame.
    return has;
  }

  static Future<String?> exportVerifier() async {
    final stored = globalPrefs.getString(_key);
    if (stored == null || stored.isEmpty) return null;
    if (_decodeVerifier(stored) != null) return stored;
    _throwIfCorruptVerifier(stored);
    await setPin(stored);
    return globalPrefs.getString(_key);
  }

  static Future<void> importBackupValue(String value) async {
    final verifier = _decodeVerifier(value);
    if (verifier == null) {
      _throwIfCorruptVerifier(value);
      await setPin(value);
      return;
    }
    if (!await globalPrefs.setString(_key, value)) {
      throw StateError('Could not restore the PIN verifier');
    }
    _hasPinCache = true;
    // Новый верификатор может иметь другую соль и итерации — прежние
    // записи KDF-кэша теперь ложны.
    _kdfCache.clear();
  }

  static Future<void> setPin(String pin) async {
    if (pin.isEmpty) {
      await removePin();
      return;
    }

    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final saltB64 = base64Encode(salt);
    // PBKDF2 deliberately takes time, so keep its CPU work off the UI isolate.
    final derivedBytes = await Isolate.run(
      () => _derivePinHash(utf8.encode(pin), salt, _iterations),
    );
    _rememberKdf(_kdfCacheKey(saltB64, pin), derivedBytes);
    final verifier = jsonEncode({
      'format': _format,
      'iterations': _iterations,
      'salt': saltB64,
      'hash': base64Encode(derivedBytes),
    });
    if (!await globalPrefs.setString(_key, verifier)) {
      throw StateError('Could not save the PIN verifier');
    }
    _hasPinCache = true;
  }

  static Future<void> removePin() async {
    await globalPrefs.remove(_key);
    _hasPinCache = false;
    _kdfCache.clear();
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = globalPrefs.getString(_key);
    if (stored == null || stored.isEmpty) return false;
    final verifier = _decodeVerifier(stored);
    if (verifier == null) {
      _throwIfCorruptVerifier(stored);
      if (!_constantTimeEquals(utf8.encode(stored), utf8.encode(pin))) {
        return false;
      }
      await setPin(pin);
      return true;
    }

    final salt = base64Decode(verifier['salt'] as String);
    final expected = base64Decode(verifier['hash'] as String);
    final iterations = verifier['iterations'] as int;
    final cacheKey = _kdfCacheKey(verifier['salt'] as String, pin);
    final cached = _kdfCache[cacheKey];
    if (cached != null) {
      return _constantTimeEquals(cached, expected);
    }
    // Кэша нет: PBKDF2 — единственная дорогая операция на этом пути,
    // поэтому считаем его в отдельном isolate и запоминаем, чтобы
    // повторная разблокировка в той же сессии обходилась без пересчёта.
    final actual = await Isolate.run(
      () => _derivePinHash(utf8.encode(pin), salt, iterations),
    );
    _rememberKdf(cacheKey, actual);
    return _constantTimeEquals(actual, expected);
  }

  static Map<String, dynamic>? _decodeVerifier(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic> && decoded['format'] == _format) {
        final salt = base64Decode(decoded['salt'] as String);
        final hash = base64Decode(decoded['hash'] as String);
        final iterations = decoded['iterations'] as int;
        if (salt.length == 16 &&
            hash.length == 32 &&
            iterations >= _minimumIterations &&
            iterations <= _maximumIterations) {
          return decoded;
        }
      }
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
    return null;
  }

  static bool _isVerifierEnvelope(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> && decoded['format'] == _format;
    } on FormatException {
      return false;
    }
  }

  static void _throwIfCorruptVerifier(String value) {
    if (_isVerifierEnvelope(value)) {
      throw const FormatException('The stored PIN verifier is invalid');
    }
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}

Future<List<int>> _derivePinHash(
  List<int> pin,
  List<int> salt,
  int iterations,
) async {
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final key = await kdf.deriveKey(secretKey: SecretKey(pin), nonce: salt);
  return key.extractBytes();
}
