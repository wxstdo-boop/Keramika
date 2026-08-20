import 'dart:async';
import 'package:flutter/material.dart';
import '../models/app_timer.dart';
import 'json_file.dart';

class TimerService extends ChangeNotifier {
  static final TimerService _instance = TimerService._();
  factory TimerService() => _instance;
  TimerService._() {
    load();
  }

  List<AppTimer> _timers = [];
  bool _loaded = false;
  static const _key = 'app_timers';

  final Map<String, int> _remainingSeconds = {};
  final Map<String, bool> _running = {};
  Timer? _ticker;

  List<AppTimer> get timers => List.unmodifiable(_timers);
  bool isRunning(String id) => _running[id] ?? false;
  int remaining(String id) => _remainingSeconds[id] ?? 0;

  String remainingDisplay(String id) =>
      AppTimer.formatDuration(_remainingSeconds[id] ?? 0);

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        _timers = appTimersFromJson(raw);
      }
    } catch (_) {}
    _loaded = true;
    for (final t in _timers) {
      _remainingSeconds.putIfAbsent(t.id, () => t.totalSeconds);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    await JsonFile.write(_key, appTimersToJson(_timers));
  }

  Future<void> add(AppTimer timer) async {
    _timers.add(timer);
    _remainingSeconds[timer.id] = timer.totalSeconds;
    _running[timer.id] = false;
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _running[id] = false;
    _timers.removeWhere((t) => t.id == id);
    _remainingSeconds.remove(id);
    _running.remove(id);
    _checkTicker();
    notifyListeners();
    await _save();
  }

  Future<void> update(AppTimer timer) async {
    final idx = _timers.indexWhere((t) => t.id == timer.id);
    if (idx != -1) {
      _timers[idx] = timer;
      _remainingSeconds[timer.id] = timer.totalSeconds;
      _running[timer.id] = false;
      _checkTicker();
      notifyListeners();
      await _save();
    }
  }

  void startTimer(String id) {
    if (_remainingSeconds[id] == null || _remainingSeconds[id]! <= 0) {
      _remainingSeconds[id] = _timers
          .firstWhere((t) => t.id == id)
          .totalSeconds;
    }
    _running[id] = true;
    _startTicker();
    notifyListeners();
  }

  void pauseTimer(String id) {
    _running[id] = false;
    _checkTicker();
    notifyListeners();
  }

  void resetTimer(String id) {
    final t = _timers.firstWhere((t) => t.id == id);
    _remainingSeconds[id] = t.totalSeconds;
    _running[id] = false;
    _checkTicker();
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      bool anyRunning = false;
      final completed = <String>[];
      for (final t in _timers) {
        if (_running[t.id] == true) {
          final rem = (_remainingSeconds[t.id] ?? 0) - 1;
          _remainingSeconds[t.id] = rem;
          if (rem <= 0) {
            completed.add(t.id);
          } else {
            anyRunning = true;
          }
        }
      }
      for (final id in completed) {
        _running[id] = false;
        onTimerDone?.call(id);
      }
      if (!anyRunning) {
        _ticker?.cancel();
        _ticker = null;
      }
      // Сохраняем только при завершении таймера, а не каждый тик!
      if (completed.isNotEmpty) {
        _save();
      }
      // Обновляем UI КАЖДЫЙ тик (1 раз в секунду) — счётчик на карточке
      // тикает, прогресс-кольцо крутится, а не стоит на месте до конца.
      notifyListeners();
    });
  }

  void _checkTicker() {
    final anyRunning = _running.values.any((v) => v);
    if (!anyRunning) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void Function(String id)? onTimerDone;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> forceSave() async {
    await _save();
  }
}
