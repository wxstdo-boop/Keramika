import 'dart:convert';
import 'json_file.dart';
import 'prefs.dart';

Future<void> migrateFromPrefs() async {
  final migratedKey = 'migrated_to_json_file_v1';
  if (globalPrefs.getBool(migratedKey) == true) return;

  final habitsRaw = globalPrefs.getString('habits');
  if (habitsRaw != null && habitsRaw.isNotEmpty) {
    await JsonFile.write('habits', habitsRaw);
  }

  final tasksRaw = globalPrefs.getString('tasks');
  if (tasksRaw != null && tasksRaw.isNotEmpty) {
    await JsonFile.write('tasks', tasksRaw);
  }
  final catRaw = globalPrefs.getString('task_categories');
  if (catRaw != null && catRaw.isNotEmpty) {
    await JsonFile.write('task_categories', catRaw);
  }

  final alarmsRaw = globalPrefs.getString('alarms');
  if (alarmsRaw != null && alarmsRaw.isNotEmpty) {
    await JsonFile.write('alarms', alarmsRaw);
  }

  final timersRaw = globalPrefs.getString('app_timers');
  if (timersRaw != null && timersRaw.isNotEmpty) {
    await JsonFile.write('app_timers', timersRaw);
  }

  final rcChecks = globalPrefs.getString('reality_checks');
  if (rcChecks != null && rcChecks.isNotEmpty) {
    final rcPerDay = globalPrefs.getInt('rc_checks_per_day') ?? 10;
    final rcFrom = globalPrefs.getString('rc_time_from') ?? '8:0';
    final rcTo = globalPrefs.getString('rc_time_to') ?? '22:0';
    final rcUseExact = globalPrefs.getBool('rc_use_exact_times') ?? false;
    final rcExactTimes = globalPrefs.getString('rc_exact_times') ?? '';
    final fromParts = rcFrom.split(':');
    final toParts = rcTo.split(':');
    final rcData = jsonEncode({
      'checks': rcChecks,
      'checksPerDay': rcPerDay,
      'timeFromHour': int.tryParse(fromParts[0]) ?? 8,
      'timeFromMinute':
          int.tryParse(fromParts.length > 1 ? fromParts[1] : '0') ?? 0,
      'timeToHour': int.tryParse(toParts[0]) ?? 22,
      'timeToMinute': int.tryParse(toParts.length > 1 ? toParts[1] : '0') ?? 0,
      'useExactTimes': rcUseExact,
      'exactTimes': rcExactTimes,
    });
    await JsonFile.write('reality_check_data', rcData);
  }

  await globalPrefs.setBool(migratedKey, true);
}
