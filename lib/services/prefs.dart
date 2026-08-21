import 'package:shared_preferences/shared_preferences.dart';

/// Глобальный кэш SharedPreferences. Инициализируется ОДИН раз в main().
late SharedPreferences globalPrefs;

/// Когда true — поверх приложения системный UI (файл-пикер, системные
/// диалоги): PIN-блюр не показывается, чтобы экран не «серел» перед
/// открытием системного окна.
bool systemUiActive = false;

/// Инициализация — вызывается в main() ПЕРЕД всем остальным.
Future<void> initPrefs() async {
  globalPrefs = await SharedPreferences.getInstance();
}
