import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agysha/main.dart' show saveBackupBytes;
import 'package:agysha/services/prefs.dart';

/// Регресс-тест на запись файла автоэкспорта.
///
/// Жалоба «автоэкспорт ни пизды не работает» чаще всего = файл не появляется.
/// На Android основной путь пишет в Download/Agysha через нативный
/// MediaStore-канал; когда он недоступен (или платформа не Android), остаётся
/// фолбэк через path_provider. Тест фиксирует, что фолбэк РЕАЛЬНО пишет файл,
/// а не молча теряет данные: раньше ошибки записи тонули, и пользователь не
/// видел ни файла, ни причины.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('agysha_auto_export');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            // Каталог загрузок недоступен — проверяем именно фолбэк.
            if (call.method == 'getDownloadsDirectory') return null;
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  test('файл бэкапа действительно записывается и перезаписывается', () async {
    final bytes = <int>[123, 34, 97, 34, 58, 49, 125]; // {"a":1}

    final path = await saveBackupBytes(bytes, 'agysha-auto-backup.json');

    final file = File(path);
    expect(await file.exists(), isTrue, reason: 'файл бэкапа не создан');
    expect(await file.readAsBytes(), bytes);
    expect(path, endsWith('agysha-auto-backup.json'));

    // Повторный экспорт перезаписывает тот же файл (фиксированное имя),
    // а не плодит копии и не падает на уже существующем.
    final again = await saveBackupBytes(<int>[49], 'agysha-auto-backup.json');
    expect(again, path);
    expect(await File(path).readAsBytes(), <int>[49]);
  });
}
