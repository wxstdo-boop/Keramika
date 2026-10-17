import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'prefs.dart';

class PinService {
  static const _key = 'app_pin';
  static const _format = 'pbkdf2-sha256-v1';
  static const _iterations = 210000;
  static const _minimumIterations = 100000;
  static const _maximumIterations = 1000000;
  static final _random = Random.secure();
  static final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  static bool? _hasPinCache;

  static bool hasPinSync() => _hasPinCache ?? false;

  @visibleForTesting
  static void resetCacheForTesting() => _hasPinCache = null;

  static Future<void> refreshCache() async {
    final stored = globalPrefs.getString(_key);
    _hasPinCache = stored != null && stored.isNotEmpty;
    if (_hasPinCache! && _decodeVerifier(stored!) == null) {
      _throwIfCorruptVerifier(stored);
      await setPin(stored);
    }
  }

  static Future<bool> hasPin() async {
    final stored = globalPrefs.getString(_key);
    final has = stored != null && stored.isNotEmpty;
    _hasPinCache = has;
    if (has && _decodeVerifier(stored) == null) {
      _throwIfCorruptVerifier(stored);
      await setPin(stored);
    }
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
  }

  static Future<void> setPin(String pin) async {
    if (pin.isEmpty) {
      await removePin();
      return;
    }

    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final derived = await _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    final verifier = jsonEncode({
      'format': _format,
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'hash': base64Encode(await derived.extractBytes()),
    });
    if (!await globalPrefs.setString(_key, verifier)) {
      throw StateError('Could not save the PIN verifier');
    }
    _hasPinCache = true;
  }

  static Future<void> removePin() async {
    await globalPrefs.remove(_key);
    _hasPinCache = false;
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
    final kdf = iterations == _iterations
        ? _kdf
        : Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations,
            bits: expected.length * 8,
          );
    final actual = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return _constantTimeEquals(await actual.extractBytes(), expected);
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
