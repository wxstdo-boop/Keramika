import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/reality_check.dart';
import 'json_file.dart';

class RealityCheckService extends ChangeNotifier {
  static final RealityCheckService _instance = RealityCheckService._();
  factory RealityCheckService() => _instance;
  RealityCheckService._() {
    load();
  }

  List<RealityCheck> _checks = [];
  int _checksPerDay = 10;
  int _timeFromHour = 8;
  int _timeFromMinute = 0;
  int _timeToHour = 22;
  int _timeToMinute = 0;
  List<TimeOfDay> _todaySchedule = [];
  bool _useExactTimes = false;
  List<TimeOfDay> _exactTimes = [];
  // Секционный флаг: когда false — раздел РП полностью выключен
  // (таб «РП» в Home скрывается, уведомлений нет, в статистику не
  // идёт). По умолчанию ВКЛЮЧЕНО — пользователь явно выключает в
  // Настройках, если ему нужен полностью чистый режим.
  bool _enabled = true;

  static const _key = 'reality_check_data';
  bool _loaded = false;

  List<RealityCheck> get checks => List.unmodifiable(_checks);
  int get checksPerDay => _checksPerDay;
  int get timeFromHour => _timeFromHour;
  int get timeFromMinute => _timeFromMinute;
  int get timeToHour => _timeToHour;
  int get timeToMinute => _timeToMinute;
  List<TimeOfDay> get todaySchedule => List.unmodifiable(_todaySchedule);
  bool get useExactTimes => _useExactTimes;
  List<TimeOfDay> get exactTimes => List.unmodifiable(_exactTimes);
  bool get enabled => _enabled;

  int get totalChecksToday {
    final today = RealityCheck.todayKey();
    return _checks.fold(0, (sum, c) {
      if (c.lastDoneDate == today) return sum + c.doneToday;
      return sum;
    });
  }

  /// Whether the user has already marked enough reality checks today to
  /// cover the whole day's schedule. Used to avoid re-scheduling notifications
  /// after the daily goal is reached.
  bool get notificationsDoneForToday {
    if (useExactTimes) {
      if (exactTimes.isEmpty) return false;
      return totalChecksToday >= exactTimes.length;
    }
    return totalChecksToday >= checksPerDay;
  }

  TimeOfDay? get nextCheckTime {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    for (final t in _todaySchedule) {
      if (t.hour * 60 + t.minute > nowMinutes) return t;
    }
    return null;
  }

  Map<String, dynamic> _toMap() => {
    'enabled': _enabled,
    'checks': realityChecksToJson(_checks),
    'checksPerDay': _checksPerDay,
    'timeFromHour': _timeFromHour,
    'timeFromMinute': _timeFromMinute,
    'timeToHour': _timeToHour,
    'timeToMinute': _timeToMinute,
    'useExactTimes': _useExactTimes,
    'exactTimes': _exactTimes.map((t) => '${t.hour * 60 + t.minute}').join(','),
  };

  void _fromMap(Map<String, dynamic> m) {
    final raw = m['checks'] as String?;
    if (raw != null && raw.isNotEmpty) {
      _checks = realityChecksFromJson(raw);
    }
    _checksPerDay = m['checksPerDay'] as int? ?? 10;
    _timeFromHour = m['timeFromHour'] as int? ?? 8;
    _timeFromMinute = m['timeFromMinute'] as int? ?? 0;
    _timeToHour = m['timeToHour'] as int? ?? 22;
    _timeToMinute = m['timeToMinute'] as int? ?? 0;
    _useExactTimes = m['useExactTimes'] is bool
        ? (m['useExactTimes'] as bool)
        : m['useExactTimes'] is num
        ? (m['useExactTimes'] as num) != 0
        : false;
    _enabled = m['enabled'] is bool
        ? (m['enabled'] as bool)
        : m['enabled'] is num
        ? (m['enabled'] as num) != 0
        : true;
    final exactRaw = m['exactTimes'] as String?;
    if (exactRaw != null && exactRaw.isNotEmpty) {
      _exactTimes = exactRaw.split(',').map((s) {
        final t = int.tryParse(s) ?? 0;
        return TimeOfDay(hour: t ~/ 60, minute: t % 60);
      }).toList();
    }
  }

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        _fromMap(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    // Сбрасываем «уведомления отменены» при смене дня.
    final today = RealityCheck.todayKey();
    for (final c in _checks) {
      if (c.lastDoneDate != today && c.notificationsCancelledToday) {
        c.notificationsCancelledToday = false;
      }
    }
    _generateTodaySchedule();
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    await JsonFile.write(_key, jsonEncode(_toMap()));
  }

  void _generateTodaySchedule() {
    // Раздел РП выключен — расписания быть не должно. Уведомления
    // (если остались с прошлых сессий) снимаются через
    // cancelAllRealityChecks() в reality_checks_screen._scheduleReminders().
    if (!_enabled) {
      _todaySchedule = [];
      return;
    }
    if (_useExactTimes) {
      if (_exactTimes.isNotEmpty) {
        _todaySchedule = List.from(_exactTimes)
          ..sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);
      } else {
        _todaySchedule = [];
      }
      return;
    }

    final rng = _dayRng();
    final fromMin = _timeFromHour * 60 + _timeFromMinute;
    final toMin = _timeToHour * 60 + _timeToMinute;
    final range = toMin - fromMin;
    if (range <= 0 || _checksPerDay <= 0) {
      _todaySchedule = [
        TimeOfDay(hour: _timeFromHour, minute: _timeFromMinute),
      ];
    } else {
      final slots = <int>{};
      while (slots.length < _checksPerDay && slots.length < range) {
        slots.add(fromMin + rng.nextInt(range));
      }
      final sorted = slots.toList()..sort();
      _todaySchedule = sorted
          .map((m) => TimeOfDay(hour: m ~/ 60, minute: m % 60))
          .toList();
    }
  }

  Random _dayRng() {
    final now = DateTime.now();
    final seed = now.year * 10000 + now.month * 100 + now.day;
    final mix =
        seed ^
        (_checksPerDay * 73856093) ^
        (_timeFromHour * 19349663) ^
        (_timeToHour * 83492791);
    return Random(mix);
  }

  /// Мгновенное обновление во время драга ползунка: без записи в JSON
  /// на каждый пиксель (это и было причиной «прыжков» на слабых телефонах).
  void setChecksPerDayPreview(int count) {
    _checksPerDay = count.clamp(5, 15);
    notifyListeners();
  }

  void setChecksPerDay(int count) {
    _checksPerDay = count.clamp(5, 15);
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  void setTimeFrom(TimeOfDay time) {
    _timeFromHour = time.hour;
    _timeFromMinute = time.minute;
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  void setTimeTo(TimeOfDay time) {
    _timeToHour = time.hour;
    _timeToMinute = time.minute;
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  void setUseExactTimes(bool value) {
    _useExactTimes = value;
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  /// Включает/выключает весь раздел проверок реальности.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  void setExactTimes(List<TimeOfDay> times) {
    _exactTimes = List.from(times);
    _generateTodaySchedule();
    _save();
    notifyListeners();
  }

  void addExactTime(TimeOfDay time) {
    if (_exactTimes.length >= 40) return;
    _exactTimes.add(time);
    _exactTimes.sort((a, b) => a.hour * 60 + a.minute - b.hour * 60 - b.minute);
    setExactTimes(_exactTimes);
  }

  void removeExactTime(int index) {
    if (index >= 0 && index < _exactTimes.length) {
      _exactTimes.removeAt(index);
      setExactTimes(_exactTimes);
    }
  }

  Future<void> add(RealityCheck check) async {
    _checks.add(check);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _checks.removeWhere((c) => c.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> update(RealityCheck check) async {
    final idx = _checks.indexWhere((c) => c.id == check.id);
    if (idx != -1) {
      _checks[idx] = check;
      notifyListeners();
      await _save();
    }
  }

  Future<void> doCheck(String id) async {
    final idx = _checks.indexWhere((c) => c.id == id);
    if (idx != -1) {
      final c = _checks[idx];
      final today = RealityCheck.todayKey();

      if (c.doneToday >= 40) return;

      if (c.lastDoneDate != today) {
        c.doneToday = 1;
        c.lastDoneDate = today;
      } else {
        c.doneToday++;
      }
      c.totalChecks++;
      c.lastCheckedAt = DateTime.now();
      c.notificationsCancelledToday = true;

      notifyListeners();
      await _save();
    }
  }

  void resetAllStats() {
    for (final c in _checks) {
      c.totalChecks = 0;
      c.doneToday = 0;
      c.notificationsCancelledToday = false;
      c.lastDoneDate = null;
      c.lastCheckedAt = null;
    }
    notifyListeners();
    _save();
  }

  Future<void> forceSave() async {
    await _save();
  }
}
