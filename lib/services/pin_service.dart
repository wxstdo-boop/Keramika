import 'prefs.dart';

class PinService {
  static const _key = 'app_pin';

  /// Синхронный кэш наличия PIN.
  ///
  /// Нужен для «мгновенной» тёмной плашки при сворачивании приложения:
  /// системный снапшот «недавних» снимается через мгновение после onPause,
  /// и асинхронный `getString` (платформенный канал) просто не успевает —
  /// в «недавних» оказывается настоящее содержимое. Кэш обновляется при
  /// установке/удалении PIN и при старте приложения.
  static bool? _hasPinCache;

  static bool hasPinSync() => _hasPinCache ?? false;

  static Future<void> refreshCache() async {
    final pin = await globalPrefs.getString(_key);
    _hasPinCache = pin != null && pin.isNotEmpty;
  }

  static Future<String?> getPin() async {
    return globalPrefs.getString(_key);
  }

  static Future<bool> hasPin() async {
    final pin = await getPin();
    final has = pin != null && pin.isNotEmpty;
    _hasPinCache = has;
    return has;
  }

  static Future<void> setPin(String pin) async {
    await globalPrefs.setString(_key, pin);
    _hasPinCache = pin.isNotEmpty;
  }

  static Future<void> removePin() async {
    await globalPrefs.remove(_key);
    _hasPinCache = false;
  }

  static Future<bool> verifyPin(String pin) async {
    final stored = await getPin();
    return stored == pin;
  }
}
