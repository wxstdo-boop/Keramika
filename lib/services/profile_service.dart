import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'completion_log_service.dart';
import 'habit_service.dart';
import 'json_file.dart';
import 'prefs.dart';
import 'task_service.dart';

/// Друг в рейтинге «керамика-юзеров».
///
/// Хранится локально: у приложения пока нет своего сервера, поэтому список
/// друзей и их очки живут на устройстве. Модель готова к синхронизации —
/// когда появится общий бэкенд, сюда достаточно подставить сетевые очки.
class ProfileFriend {
  const ProfileFriend({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.score,
  });

  final String id;
  final String name;

  /// Индекс градиента аватарки в [profileAvatarVariants].
  final int colorIndex;

  /// Очки «керамика-рейтинга» (см. [ProfileService.localScore]).
  final int score;

  ProfileFriend copyWith({String? name, int? colorIndex, int? score}) =>
      ProfileFriend(
        id: id,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        score: score ?? this.score,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorIndex,
    'score': score,
  };

  factory ProfileFriend.fromJson(Map<String, dynamic> j) => ProfileFriend(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    colorIndex: (j['color'] as num?)?.toInt() ?? 0,
    score: (j['score'] as num?)?.toInt() ?? 0,
  );
}

/// Профиль «керамика-юзера» и его локальный рейтинг.
///
/// Своё имя и цвет аватарки, список друзей с очками, своя музыка для
/// профиля — всё хранится в одном зашифрованном файле ([JsonFile]), как и
/// остальные данные приложения. Онлайн-статус (красный кружок) вынесен
/// отдельным лёгким ключом в SharedPreferences: его читают и шапка, и
/// мини-окошко, и он не тянет за собой разбор всего профиля.
class ProfileService extends ChangeNotifier {
  static final ProfileService _instance = ProfileService._();
  factory ProfileService() => _instance;
  ProfileService._();

  static const String _fileKey = 'profile';
  static const String _onlinePrefsKey = 'profile_online';

  bool _loaded = false;
  String? _snapshot;
  String _name = '';
  int _avatarIndex = 0;
  String? _musicPath;
  String? _musicTitle;
  final List<ProfileFriend> _friends = [];

  bool get loaded => _loaded;
  String get name => _name;
  int get avatarIndex => _avatarIndex;
  String? get musicPath => _musicPath;
  String? get musicTitle => _musicTitle;
  List<ProfileFriend> get friends => List.unmodifiable(_friends);

  /// Короткое имя для показа: пустое поле заменяем на «Керамика-юзер».
  String get displayName => _name.trim().isEmpty ? '' : _name.trim();

  /// Показывать ли красный кружок онлайна. Хранится отдельно и переживает
  /// перезапуск (см. комментарий к классу).
  bool get online => _readOnlinePref();

  bool _readOnlinePref() {
    try {
      return globalPrefs.getBool(_onlinePrefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> load() async {
    final raw = await JsonFile.read(_fileKey);
    _snapshot = raw;
    // Начинаем с чистого состояния: если файла нет (или он битый), профиль
    // должен остаться пустым, а не унаследовать значения прошлого разбора —
    // иначе повторный load() в том же процессе «протекает» старыми данными.
    _name = '';
    _avatarIndex = 0;
    _musicPath = null;
    _musicTitle = null;
    _friends.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _name = (map['name'] ?? '').toString();
        _avatarIndex = (map['avatar'] as num?)?.toInt() ?? 0;
        _musicPath = map['musicPath']?.toString();
        _musicTitle = map['musicTitle']?.toString();
        final list = (map['friends'] as List?) ?? const [];
        _friends
          ..clear()
          ..addAll(
            list.map(
              (e) => ProfileFriend.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            ),
          );
      } catch (_) {
        // Битый файл не должен ронять профиль: остаёмся на значениях по
        // умолчанию, а следующий сохранённый снимок перезапишет его.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (!_loaded) return;
    final value = jsonEncode({
      'name': _name,
      'avatar': _avatarIndex,
      'musicPath': _musicPath,
      'musicTitle': _musicTitle,
      'friends': _friends.map((f) => f.toJson()).toList(),
    });
    final resolved = await JsonFile.writeWithSnapshot(_fileKey, value, _snapshot);
    if (resolved == value) _snapshot = resolved;
  }

  /// Максимальная длина короткого имени. Поле ввода уже ограничивает
  /// набор, но сервис держит лимит и сам: имя приходит и из других мест
  /// (например, из будущей синхронизации), а в шапке длинный текст ломал бы
  /// строку.
  static const int maxNameLength = 10;

  Future<void> setName(String value) async {
    final trimmed = value.trim();
    _name = trimmed.length > maxNameLength
        ? trimmed.substring(0, maxNameLength)
        : trimmed;
    notifyListeners();
    await _save();
  }

  Future<void> setAvatarIndex(int index) async {
    _avatarIndex = index;
    notifyListeners();
    await _save();
  }

  /// Своя музыка профиля: хранится ПУТЬ к уже скопированному в приватную
  /// папку файлу (см. экран профиля) — он переживёт очистку кэша.
  Future<void> setMusic({String? path, String? title}) async {
    _musicPath = path;
    _musicTitle = title;
    notifyListeners();
    await _save();
  }

  /// Переключает онлайн-статус. Красный кружок в шапке загорается/гаснет
  /// сразу: сначала уведомляем слушателей, потом пишем на диск.
  Future<void> setOnline(bool value) async {
    try {
      await globalPrefs.setBool(_onlinePrefsKey, value);
    } catch (_) {}
    // Уведомляем ПОСЛЕ записи: слушатели читают [online] из prefs, и
    // оповещение раньше записи вернуло бы им старое значение.
    notifyListeners();
  }

  Future<void> toggleOnline() => setOnline(!online);

  Future<void> addFriend({
    required String name,
    required int colorIndex,
    required int score,
  }) async {
    _friends.add(
      ProfileFriend(
        id: 'f${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        colorIndex: colorIndex,
        score: score,
      ),
    );
    notifyListeners();
    await _save();
  }

  Future<void> updateFriend(ProfileFriend friend) async {
    final idx = _friends.indexWhere((f) => f.id == friend.id);
    if (idx < 0) return;
    _friends[idx] = friend;
    notifyListeners();
    await _save();
  }

  Future<void> removeFriend(String id) async {
    _friends.removeWhere((f) => f.id == id);
    notifyListeners();
    await _save();
  }

  /// Локальный счёт «керамика-рейтинга»: сумма текущих стриков привычек и
  /// числа выполненных задач плюс бонус за активные дни в логе выполнения.
  ///
  /// Считается из реальной активности, а не вводится руками, — иначе рейтинг
  /// был бы красивой пустышкой.
  int localScore() {
    var score = 0;
    for (final h in HabitService().habits) {
      if (h.streak > 0) score += h.streak;
    }
    score += TaskService().tasks.where((t) => t.done).length;
    final days = CompletionLogService().lastDays(14);
    var active = 0;
    for (final d in days) {
      if (d.habits > 0 || d.tasks > 0) active++;
    }
    score += active * 3;
    return score;
  }

  /// Рейтинг: друзья + сам пользователь, отсортировано по очкам (по убыванию).
  /// [selfFallback] — подпись себя, когда имя ещё не задано (перевод задаёт
  /// экран).
  List<ProfileFriend> leaderboard({String selfFallback = 'Я'}) {
    final all = <ProfileFriend>[
      ProfileFriend(
        id: 'me',
        name: displayName.isEmpty ? selfFallback : displayName,
        colorIndex: _avatarIndex,
        score: localScore(),
      ),
      ..._friends,
    ]..sort((a, b) => b.score.compareTo(a.score));
    return all;
  }
}
