import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'prefs.dart';

class JsonFile {
  static Directory? _dir;

  static Future<Directory> get _directory async {
    _dir ??= await getApplicationDocumentsDirectory();
    return _dir!;
  }

  static Future<void> write(String key, String value) async {
    // На web dart:io File недоступен — пишем в localStorage через
    // SharedPreferences. Так данные (привычки, задачи, будильники,
    // приёмы пищи, настройки) переживают перезагрузку страницы.
    if (kIsWeb) {
      try {
        await globalPrefs.setString(key, value);
      } catch (_) {}
      return;
    }
    try {
      final dir = await _directory;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$key.json');
      // Direct overwrite — `File.rename` fails on Windows when target
      // exists, а у пользователя Керамики уже могут лежать старые json’ы.
      await file.writeAsString(value, flush: true);
    } catch (_) {
      // Последняя попытка: write в .tmp и заменить поверх, чтобы
      // не потерять данные, если прямой writeAsString вдруг споткнулся.
      try {
        final dir = await _directory;
        final file = File('${dir.path}/$key.json');
        final temp = File('${dir.path}/$key.json.tmp');
        await temp.writeAsString(value, flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await temp.rename(file.path);
      } catch (_) {}
    }
  }

  static Future<String?> read(String key) async {
    if (kIsWeb) {
      try {
        return globalPrefs.getString(key);
      } catch (_) {
        return null;
      }
    }
    try {
      final dir = await _directory;
      final file = File('${dir.path}/$key.json');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    if (kIsWeb) {
      try {
        await globalPrefs.remove(key);
      } catch (_) {}
      return;
    }
    try {
      final dir = await _directory;
      final file = File('${dir.path}/$key.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
