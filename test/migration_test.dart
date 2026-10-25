import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/migration.dart';
import 'package:keramika/services/prefs.dart';

/// Тесты миграции данных со старого хранилища (SharedPreferences) на
/// JSON-файлы.
///
/// Почему это важно покрыть: миграция переносит данные пользователя
/// (привычки, задачи, будильники, проверки) из prefs в файлы. Ошибка здесь
/// — не «краш», а тихая потеря данных: привычки пропали, будильники не
/// перенеслись, и человек узнаёт об этом, когда будильник не прозвонил.
///
/// Проверяем:
///  * данные переносятся и читаются обратно;
///  * миграция идёт ровно один раз (второй вызов не трогает данные);
///  * reality checks собираются в новый формат из разрозненных prefs;
///  * отсутствующие в prefs сущности не создают мусорных файлов.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUp(() async {
    JsonFile.resetForTesting();
    directory = await Directory.systemTemp.createTemp('keramika_migration_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationDocumentsDirectory'
              ? directory.path
              : null,
        );
    JsonFile.useEncryptionKeyForTesting(List<int>.filled(32, 9));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await directory.delete(recursive: true);
    JsonFile.resetForTesting();
  });

  /// Читает перенесённый документ и разбирает JSON. Отсутствие файла или
  /// ключа — ошибка теста, поэтому бросаем с понятным текстом.
  Future<Object?> readJson(String key) async {
    final raw = await JsonFile.read(key);
    expect(
      raw,
      isNotNull,
      reason: 'Документ «$key» не перенесён',
    );
    return jsonDecode(raw!);
  }

  /// Старые данные в prefs — как их видел предыдущий формат.
  void seedLegacyPrefs() {    SharedPreferences.setMockInitialValues({
      'habits': jsonEncode([
        {'id': 'h1', 'name': 'Читать', 'streak': 5, 'doneToday': false},
      ]),
      'tasks': jsonEncode([
        {'id': 't1', 'title': 'Позвонить', 'priority': 1, 'done': false},
      ]),
      'task_categories': jsonEncode(['Работа', 'Дом']),
      'alarms': jsonEncode([
        {
          'id': 'a1',
          'hour': 7,
          'minute': 30,
          'enabled': true,
          'days': [1, 2, 3, 4, 5],
        },
      ]),
      'app_timers': jsonEncode([
        {'id': 'timer1', 'label': 'Фокус', 'totalSeconds': 1500},
      ]),
    });
  }

  test('переносит привычки, задачи, категории, будильники и таймеры', () async {
    seedLegacyPrefs();
    await initPrefs();

    await migrateFromPrefs();

    final habits = await readJson('habits') as List;
    expect(habits, hasLength(1));
    expect((habits.first as Map)['name'], 'Читать');
    expect((habits.first as Map)['streak'], 5);

    final tasks = await readJson('tasks') as List;
    expect((tasks.first as Map)['title'], 'Позвонить');

    final categories = await readJson('task_categories') as List;
    expect(categories, contains('Работа'));

    final alarms = await readJson('alarms') as List;
    expect((alarms.first as Map)['hour'], 7);
    expect((alarms.first as Map)['enabled'], true);

    final timers = await readJson('app_timers') as List;
    expect((timers.first as Map)['label'], 'Фокус');
  });

  test('проверки реальности собираются в единый документ', () async {
    SharedPreferences.setMockInitialValues({
      'reality_checks': jsonEncode(['Встал?']),
      'rc_checks_per_day': 7,
      'rc_time_from': '9:30',
      'rc_time_to': '21:15',
      'rc_use_exact_times': true,
      'rc_exact_times': jsonEncode(['09:30', '13:00']),
    });
    await initPrefs();

    await migrateFromPrefs();

    final data =
        await readJson('reality_check_data') as Map;
    expect(jsonDecode(data['checks'] as String), contains('Встал?'));
    expect(data['checksPerDay'], 7);
    expect(data['timeFromHour'], 9);
    expect(data['timeFromMinute'], 30);
    expect(data['timeToHour'], 21);
    expect(data['timeToMinute'], 15);
    expect(data['useExactTimes'], true);
    expect(data['exactTimes'], jsonEncode(['09:30', '13:00']));
  });

  test('у разрозненных проверок берутся значения по умолчанию', () async {
    // Время может лежать в нестандартном виде («8:0»), а часов в сутки может
    // не быть вовсе. Миграция не должна падать на этом.
    SharedPreferences.setMockInitialValues({
      'reality_checks': jsonEncode(['Встал?']),
      'rc_time_from': '8:0',
      'rc_time_to': '22:0',
    });
    await initPrefs();

    await migrateFromPrefs();

    final data =
        await readJson('reality_check_data') as Map;
    expect(data['timeFromHour'], 8);
    expect(data['timeFromMinute'], 0);
    expect(data['timeToHour'], 22);
    expect(data['timeToMinute'], 0);
    expect(data['checksPerDay'], 10);
    expect(data['useExactTimes'], false);
  });

  test('миграция помечается выполненной и не повторяется', () async {
    seedLegacyPrefs();
    await initPrefs();

    await migrateFromPrefs();
    expect(globalPrefs.getBool('migrated_to_json_file_v1'), isTrue);

    // Второй вызов не должен перетирать уже перенесённые данные новыми
    // (пустыми) значениями из prefs — именно это и ломало данные раньше.
    await JsonFile.write('habits', jsonEncode([{'id': 'h2', 'name': 'Новая'}]));
    await migrateFromPrefs();

    final habits = await readJson('habits') as List;
    expect(habits, hasLength(1));
    expect((habits.first as Map)['name'], 'Новая');
  });

  test('отсутствующие в prefs сущности не создают мусорных файлов', () async {
    SharedPreferences.setMockInitialValues({});
    await initPrefs();

    await migrateFromPrefs();

    final files = directory
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(
      files.where((f) => f.endsWith('.json')),
      isEmpty,
      reason: 'Миграция создала файлы для данных, которых не было: $files',
    );
  });
}
