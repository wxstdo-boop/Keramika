import 'prefs.dart';

/// Гарантированное сохранение через глобальный кэш SharedPreferences.
class SafeSave {
  static void saveString(String key, String value) {
    globalPrefs.setString(key, value);
  }

  static String? loadString(String key) {
    return globalPrefs.getString(key);
  }

  static void saveBool(String key, bool value) {
    globalPrefs.setBool(key, value);
  }

  static bool? loadBool(String key) {
    return globalPrefs.getBool(key);
  }

  static void saveInt(String key, int value) {
    globalPrefs.setInt(key, value);
  }

  static int? loadInt(String key) {
    return globalPrefs.getInt(key);
  }
}
