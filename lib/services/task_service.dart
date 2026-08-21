import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/task.dart';
import 'json_file.dart';
import 'prefs.dart';

class TaskService extends ChangeNotifier {
  static final TaskService _instance = TaskService._();
  factory TaskService() => _instance;
  TaskService._();

  List<Task> _tasks = [];
  List<String> _categories = [];
  bool _loaded = false;
  static const _key = 'tasks';
  static const _catKey = 'task_categories';

  List<Task> get tasks => List.unmodifiable(_tasks);
  List<String> get categories => List.unmodifiable(_categories);

  Future<void> load() async {
    try {
      final raw = await JsonFile.read(_key);
      if (raw != null && raw.isNotEmpty) {
        _tasks = tasksFromJson(raw);
      }
      final catRaw = await JsonFile.read(_catKey);
      if (catRaw != null && catRaw.isNotEmpty) {
        final list = jsonDecode(catRaw) as List;
        _categories = list.map((e) => e as String).toList();
      }
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    await JsonFile.write(_key, tasksToJson(_tasks));
  }

  Future<void> _saveCategories() async {
    if (!_loaded) return;
    await JsonFile.write(_catKey, jsonEncode(_categories));
  }

  Future<bool> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 15 || _categories.contains(trimmed))
      return false;
    if (_categories.length >= 15) return false;
    _categories.add(trimmed);
    notifyListeners();
    await _saveCategories();
    return true;
  }

  Future<bool> renameCategory(String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty ||
        trimmed.length > 15 ||
        _categories.contains(trimmed) ||
        !_categories.contains(oldName))
      return false;
    final idx = _categories.indexOf(oldName);
    _categories[idx] = trimmed;
    for (final t in _tasks) {
      if (t.category == oldName) t.category = trimmed;
    }
    notifyListeners();
    await _saveCategories();
    await _save();
    return true;
  }

  Future<void> removeCategory(String name) async {
    // Сначала снимаем категорию с задач — и сразу уведомляем слушателей,
    // чтобы карточки переехали в группу «Без категории» плавно, без
    // промежуточного состояния, когда фильтр показывает пустоту.
    _categories.remove(name);
    for (final t in _tasks) {
      if (t.category == name) t.category = '';
    }
    notifyListeners();
    await _saveCategories();
    await _save();
  }

  Future<void> add(Task task) async {
    _tasks.add(task);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    notifyListeners();
    await _save();
  }

  Future<bool> toggle(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx == -1) return _tasks[idx].done;
    final wasDone = _tasks[idx].done;
    _tasks[idx].done = !wasDone;
    // Счётчик ВСЕХ выполненных задач (растёт всю жизнь) — Ада награждает за
    // вехи 5/10/25/50/100… Считаем только переходы в done=true; отмена
    // честно уменьшает счётчик, чтобы снятые галочки не «фармили» награды.
    final sign = _tasks[idx].done ? 1 : -1;
    final total = (globalPrefs.getInt('ai_tasks_done_total') ?? 0) + sign;
    final clamped = total < 0 ? 0 : total;
    await globalPrefs.setInt('ai_tasks_done_total', clamped);
    notifyListeners();
    await _save();
    return _tasks[idx].done;
  }

  Future<void> update(Task task) async {
    final idx = _tasks.indexWhere((t) => t.id == task.id);
    if (idx != -1) {
      _tasks[idx] = task;
      notifyListeners();
      await _save();
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _tasks.length) return;
    if (newIndex < 0 || newIndex >= _tasks.length) return;
    final item = _tasks.removeAt(oldIndex);
    _tasks.insert(newIndex, item);
    notifyListeners();
    await _save();
  }

  Future<void> forceSave() async {
    await _save();
  }
}
