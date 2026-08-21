import 'package:flutter/material.dart';
import '../models/alarm.dart';
import 'json_file.dart';
import 'prefs.dart';

class AlarmService extends ChangeNotifier {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  List<Alarm> _alarms = [];
  bool _loaded = false;
  static const _key = 'alarms';

  List<Alarm> get alarms => List.unmodifiable(_alarms);

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        _alarms = alarmsFromJson(raw);
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
    // Pin-флаг теперь хранится непосредственно в JSON будильника.
    // Убираем восстановление из globalPrefs, которое могло перезаписывать
    // корректно импортированное значение.
  }

  Future<void> _save() async {
    if (!_loaded) return;
    await JsonFile.write(_key, alarmsToJson(_alarms));
  }

  Future<void> add(Alarm alarm) async {
    _alarms.add(alarm);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _alarms.removeWhere((a) => a.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> toggle(String id) async {
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _alarms[idx].enabled = !_alarms[idx].enabled;
      notifyListeners();
      await _save();
    }
  }

  Future<void> update(Alarm alarm) async {
    final idx = _alarms.indexWhere((a) => a.id == alarm.id);
    if (idx != -1) {
      _alarms[idx] = alarm;
      notifyListeners();
      await _save();
    }
  }

  /// Закрепляет/открепляет будильник.
  ///
  /// Дополнительно пишем признак в [globalPrefs] как страховку на случай,
  /// если файл-миграция отвалится в следующих билдах. На следующем запуске
  /// [load] сначала читает JSON, а потом пробегает по этим «бэкап-ключам»
  /// и восстанавливает pin-флаг, если он ещё не был записан в JSON.
  Future<void> pin(String id) async {
    if (!_loaded) await load();
    final idx = _alarms.indexWhere((a) => a.id == id);
    if (idx != -1) {
      _alarms[idx].pinned = !_alarms[idx].pinned;
      _alarms.sort((a, b) {
        if (a.pinned && !b.pinned) return -1;
        if (!a.pinned && b.pinned) return 1;
        return a.time.hour * 60 +
            a.time.minute -
            (b.time.hour * 60 + b.time.minute);
      });
      // Безопасный порядок: сначала файл (источник истины), потом notify,
      // потом уведомления слушателей и страховочная запись в prefs.
      // Если _save() упадёт — listeners не получат ложное состояние,
      // и prefs-бэкап не будет врать о якобы сохранённом пине.
      await _save();
      notifyListeners();
      try {
        await globalPrefs.setBool('alarm_pin_$id', _alarms[idx].pinned);
      } catch (_) {}
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _alarms.length) return;
    if (newIndex < 0 || newIndex >= _alarms.length) return;
    final item = _alarms.removeAt(oldIndex);
    _alarms.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  Alarm? getById(String id) {
    try {
      return _alarms.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> forceSave() async {
    await _save();
  }
}
