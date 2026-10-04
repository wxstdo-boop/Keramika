import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'prefs.dart';

class JsonFile {
  static Directory? _dir;

  /// Что последний раз ушло на диск по каждому ключу — подсказка, ЗАЧЕМ
  /// вообще смотреть в файл.
  ///
  /// Автоподсохранение в main() пишет ВСЕ файлы данных раз в 10 секунд, а
  /// `writeAsString(flush: true)` — это fsync: на flash-памяти бюджетного
  /// Redmi это несколько миллисекунд блокировки IO-потока на каждый файл,
  /// пять раз каждые десять секунд весь день. Если на диске уже лежит ровно
  /// этот текст, запись не нужна. Само совпадение проверяется чтением файла
  /// (дешёвым, он в страничном кэше), а не только по памяти: isolate
  /// плавающего окошка Ады пишет часть тех же ключей из своего процесса, и
  /// полагаться только на локальную карту было бы потерей данных.
  static final Map<String, String> _lastWritten = {};

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
      final file = File('${dir.path}/$key.json');
      if (_lastWritten[key] == value && await _sameOnDisk(file, value)) return;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // Direct overwrite — `File.rename` fails on Windows when target
      // exists, а у пользователя Керамики уже могут лежать старые json’ы.
      await file.writeAsString(value, flush: true);
      _lastWritten[key] = value;
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
        _lastWritten[key] = value;
      } catch (_) {}
    }
  }

  /// Лежит ли на диске уже ровно этот текст. Любая ошибка (нет файла, нет
  /// каталога, файл занят) означает «пиши как обычно».
  static Future<bool> _sameOnDisk(File file, String value) async {
    try {
      return await file.readAsString() == value;
    } catch (_) {
      return false;
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
    // Файла на диске больше нет — кэш «что уже записано» обязан быть
    // сброшен, иначе последующая запись того же текста молча пропустится.
    _lastWritten.remove(key);
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
