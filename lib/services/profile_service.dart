import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/profile_gift.dart';
import 'completion_log_service.dart';
import 'habit_service.dart';
import 'json_file.dart';
import 'prefs.dart';
import 'score_service.dart';
import 'task_service.dart';

/// Друг в рейтинге «Agysha-юзеров».
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
    this.imagePath,
  });

  final String id;
  final String name;

  /// Индекс градиента аватарки в [profileAvatarVariants]. Показывается, пока
  /// не выбрана своя картинка ([imagePath]).
  final int colorIndex;

  /// Очки «Agysha-рейтинга» (см. [ProfileService.localScore]).
  final int score;

  /// Своя аватарка друга из галереи — путь к копии в приватной папке.
  /// Пока путь задан, в рейтинге и в листах показывается она, а не
  /// сгенерированный градиент. Ноль означает «вариант по цвету».
  final String? imagePath;

  /// Показывать ли картинку вместо сгенерированного варианта.
  bool get hasImage => imagePath != null && imagePath!.isNotEmpty;

  /// Копия с изменёнными полями. [clearImage] снимает свою картинку: `null`
  /// в [imagePath] значит «не трогать» (иначе нельзя было бы отличить
  /// «не передан» от «стереть»), поэтому возврат к градиенту идёт флагом.
  ProfileFriend copyWith({
    String? name,
    int? colorIndex,
    int? score,
    String? imagePath,
    bool clearImage = false,
  }) => ProfileFriend(
    id: id,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
    score: score ?? this.score,
    imagePath: clearImage ? null : (imagePath ?? this.imagePath),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorIndex,
    'score': score,
    'image': imagePath,
  };

  factory ProfileFriend.fromJson(Map<String, dynamic> j) => ProfileFriend(
    id: (j['id'] ?? '').toString(),
    name: (j['name'] ?? '').toString(),
    colorIndex: (j['color'] as num?)?.toInt() ?? 0,
    score: (j['score'] as num?)?.toInt() ?? 0,
    imagePath: j['image']?.toString(),
  );
}

/// Трек «своей музыки» профиля. Хранится списком: до [ProfileService.maxTracks]
/// штук, чтобы в профиле была не одна песня, а небольшая своя подборка.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.addedAt,
    this.fingerprint = '',
  });

  final String id;

  /// Путь к копии файла в приватной папке приложения.
  final String path;

  /// Подпись трека. По умолчанию — имя файла; название можно менять.
  final String title;

  /// Когда трек добавлен (мс с эпохи) — для стабильного порядка и «свежих»
  /// подписей.
  final int addedAt;

  /// Отпечаток содержимого файла (SHA-256). Один и тот же звук нельзя
  /// добавить дважды: сравниваем не имя и не путь, а сами байты — тот же
  /// трек под другим именем тоже не пройдёт.
  final String fingerprint;

  MusicTrack copyWith({String? title}) => MusicTrack(
    id: id,
    path: path,
    title: title ?? this.title,
    addedAt: addedAt,
    fingerprint: fingerprint,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'path': path,
    'title': title,
    'at': addedAt,
    'fp': fingerprint,
  };

  factory MusicTrack.fromJson(Map<String, dynamic> j) => MusicTrack(
    id: (j['id'] ?? '').toString(),
    path: (j['path'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    addedAt: (j['at'] as num?)?.toInt() ?? 0,
    fingerprint: (j['fp'] ?? '').toString(),
  );
}

/// Профиль «Agysha-юзера» и его локальный рейтинг.
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
  final List<MusicTrack> _tracks = [];
  String _prestigeTitle = 'Cyberpunk 2077 Legend';
  int _zenKarma = 0;
  final List<ProfileGift> _gifts = [];

  /// Своя аватарка из галереи: путь к скопированному в приватную папку файлу.
  /// Пока он задан — он и показывается вместо сгенерированного варианта.
  String? _avatarImagePath;
  final List<ProfileFriend> _friends = [];

  bool get loaded => _loaded;
  String get name => _name;
  int get avatarIndex => _avatarIndex;
  String get prestigeTitle =>
      _prestigeTitle.trim().isEmpty ? 'Cyberpunk 2077 Legend' : _prestigeTitle;
  int get zenKarma => _zenKarma;
  List<ProfileGift> get gifts => List.unmodifiable(_gifts);
  /// Своя подборка музыки (до [maxTracks] штук).
  List<MusicTrack> get tracks => List.unmodifiable(_tracks);

  /// Первый трек подборки: на него ориентируются «кто играет» и мини-плеер.
  MusicTrack? get firstTrack => _tracks.isEmpty ? null : _tracks.first;

  /// Путь первого трека — совместимость с прежним одиночным полем.
  String? get musicPath => firstTrack?.path;

  /// Подпись первого трека.
  String? get musicTitle => firstTrack?.title;

  /// Предел подборки: дальше список не принимает треки. 99 — «почти
  /// безлимит» для личного плейлиста: подборка живёт в памяти и на
  /// диске (JSON), а не на экране, поэтому большой список дешёвый.
  static const int maxTracks = 99;

  /// Есть ли ещё место в подборке.
  bool get canAddTrack => _tracks.length < maxTracks;
  String? get avatarImagePath => _avatarImagePath;
  List<ProfileFriend> get friends => List.unmodifiable(_friends);

  /// Короткое имя для показа: пустое поле заменяем на «Agysha-юзер».
  String get displayName => _name.trim().isEmpty ? '' : _name.trim();

  /// Показывать ли красный кружок онлайна. Хранится отдельно и переживает
  /// перезапуск (см. комментарий к классу).
  ///
  /// Значение кэшируется в памяти: чтение из prefs синхронное, но с диска —
  /// и при частом опросе (кружок в шапке слушает сервис) это давало заметный
  /// лаг. Кэш обновляем СРАЗУ при переключении, до записи на диск.
  bool? _onlineCache;

  bool get online => _onlineCache ??= _readOnlinePref();

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
    _tracks.clear();
    _avatarImagePath = null;
    _friends.clear();
    _prestigeTitle = 'Cyberpunk 2077 Legend';
    _zenKarma = 0;
    _gifts
      ..clear()
      ..addAll(ProfileGift.initialShowcase());
    if (raw != null && raw.isNotEmpty) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _name = (map['name'] ?? '').toString();
        _avatarIndex = (map['avatar'] as num?)?.toInt() ?? 0;
        _prestigeTitle =
            (map['prestigeTitle'] ?? 'Cyberpunk 2077 Legend').toString();
        _zenKarma = (map['zenKarma'] as num?)?.toInt() ?? 0;
        final rawGifts = (map['gifts'] as List?) ?? const [];
        if (rawGifts.isNotEmpty) {
          _gifts
            ..clear()
            ..addAll(
              rawGifts.map(
                (e) => ProfileGift.fromJson(Map<String, dynamic>.from(e as Map)),
              ),
            );
        }
        // Новая форма — список треков. Старые профили (одно поле musicPath)
        // читаем как подборку из одного трека: иначе у тех, кто уже выбрал
        // музыку, она бы «потерялась» после обновления.
        final rawTracks = (map['tracks'] as List?) ?? const [];
        _tracks
          ..clear()
          ..addAll(
            rawTracks.map(
              (e) => MusicTrack.fromJson(Map<String, dynamic>.from(e as Map)),
            ),
          );
        if (_tracks.isEmpty) {
          final legacyPath = map['musicPath']?.toString();
          if (legacyPath != null && legacyPath.isNotEmpty) {
            _tracks.add(
              MusicTrack(
                id: 'legacy',
                path: legacyPath,
                title: map['musicTitle']?.toString() ?? '',
                addedAt: 0,
              ),
            );
          }
        }
        _avatarImagePath = map['avatarImage']?.toString();
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
      'prestigeTitle': _prestigeTitle,
      'zenKarma': _zenKarma,
      'gifts': _gifts.map((g) => g.toJson()).toList(),
      'tracks': _tracks.map((t) => t.toJson()).toList(),
      // Дублируем первый трек в старые поля: мини-плеер и прочие места,
      // читающие одиночную музыку, продолжают работать без правок.
      'musicPath': musicPath,
      'musicTitle': musicTitle,
      'avatarImage': _avatarImagePath,
      'friends': _friends.map((f) => f.toJson()).toList(),
    });
    final resolved = await JsonFile.writeWithSnapshot(_fileKey, value, _snapshot);
    if (resolved == value) _snapshot = resolved;
  }

  /// Установить престижный титул (отображается под именем в профиле).
  Future<void> setPrestigeTitle(String title) async {
    _prestigeTitle = title.trim();
    notifyListeners();
    await _save();
  }

  /// Увеличить дзен-карму от антистресс-тапов по сфере аватарки.
  Future<int> incrementZenKarma([int amount = 1]) async {
    _zenKarma += amount;
    notifyListeners();
    await _save();
    return _zenKarma;
  }

  /// Переключить статус избранного для артефакта.
  Future<void> toggleGiftFavorite(String giftId) async {
    final idx = _gifts.indexWhere((g) => g.id == giftId);
    if (idx >= 0) {
      _gifts[idx] = _gifts[idx].copyWith(isFavorite: !_gifts[idx].isFavorite);
      notifyListeners();
      await _save();
    }
  }

  /// Добавить новый разблокированный артефакт в коллекцию.
  Future<void> addGift(ProfileGift gift) async {
    _gifts.insert(0, gift);
    notifyListeners();
    await _save();
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

  /// Выбор сгенерированного варианта: своя картинка из галереи при этом
  /// снимается — иначе непонятно, что показывать.
  Future<void> setAvatarIndex(int index) async {
    _avatarIndex = index;
    _avatarImagePath = null;
    notifyListeners();
    await _save();
  }

  /// Своя аватарка из галереи (путь к уже скопированному файлу).
  Future<void> setAvatarImage(String? path) async {
    _avatarImagePath = path;
    notifyListeners();
    await _save();
  }

  /// Есть ли в подборке трек с таким отпечатком содержимого.
  bool hasTrackWithFingerprint(String fingerprint) {
    if (fingerprint.isEmpty) return false;
    return _tracks.any((t) => t.fingerprint == fingerprint);
  }

  /// Свободное название: если такое уже занято в подборке, добавляем номер
  /// («… 2», «… 3»). Иначе два трека читались бы одним и тем же именем.
  String uniqueTitle(String title) {
    final base = title.trim().isEmpty ? 'Трек' : title.trim();
    final taken = _tracks.map((t) => t.title).toSet();
    if (!taken.contains(base)) return base;
    var n = 2;
    while (taken.contains('$base $n')) {
      n++;
    }
    return '$base $n';
  }

  /// Добавить трек в подборку. Возвращает `false`, если места нет ИЛИ такой
  /// звук уже в подборке (сравнение по отпечатку содержимого).
  Future<bool> addTrack({
    required String path,
    required String title,
    String fingerprint = '',
  }) async {
    if (_tracks.length >= maxTracks) return false;
    if (hasTrackWithFingerprint(fingerprint)) return false;
    _tracks.add(
      MusicTrack(
        id: 't${DateTime.now().microsecondsSinceEpoch}',
        path: path,
        title: uniqueTitle(title),
        addedAt: DateTime.now().millisecondsSinceEpoch,
        fingerprint: fingerprint,
      ),
    );
    notifyListeners();
    await _save();
    return true;
  }

  /// Убрать трек из подборки.
  Future<void> removeTrack(String id) async {
    _tracks.removeWhere((t) => t.id == id);
    notifyListeners();
    await _save();
  }

  /// Переименовать трек (своя подпись вместо имени файла).
  Future<void> renameTrack(String id, String title) async {
    final idx = _tracks.indexWhere((t) => t.id == id);
    if (idx < 0) return;
    _tracks[idx] = _tracks[idx].copyWith(title: title.trim());
    notifyListeners();
    await _save();
  }

  /// Очистить всю подборку (кнопка «удалить всё»).
  Future<void> clearTracks() async {
    _tracks.clear();
    notifyListeners();
    await _save();
  }

  /// Переключает онлайн-статус. Красный кружок в шапке загорается/гаснет
  /// сразу: сначала обновляем кэш и уведомляем слушателей, потом пишем на диск.
  Future<void> setOnline(bool value) async {
    _onlineCache = value;
    notifyListeners();
    try {
      await globalPrefs.setBool(_onlinePrefsKey, value);
    } catch (_) {}
  }

  Future<void> toggleOnline() => setOnline(!online);

  /// Предел числа друзей. За ним список просто перестаёт принимать новых:
  /// иначе рейтинг превращается в бесконечную ленту, а карточка — в тормоз.
  static const int maxFriends = 50;

  bool get canAddFriend => _friends.length < maxFriends;

  /// Добавляет друга. Возвращает `false`, если список уже полон — вызывающий
  /// показывает мягкое сообщение, а не молча роняет действие.
  Future<bool> addFriend({
    required String name,
    required int colorIndex,
    required int score,
    String? imagePath,
  }) async {
    if (!canAddFriend) return false;
    _friends.add(
      ProfileFriend(
        id: 'f${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        colorIndex: colorIndex,
        score: score,
        imagePath: imagePath,
      ),
    );
    notifyListeners();
    await _save();
    return true;
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

  /// Локальный счёт «Agysha-рейтинга» — ПОЖИЗНЕННАЯ копилка [ScoreService].
  ///
  /// Раньше считался только из ТЕКУЩЕГО состояния: снял галочку или потерял
  /// стрик — очки падали, и цифра ничего не значила. Теперь копилка растёт от
  /// каждого действия (привычка, задача, сообщение Аде, приём пищи, проверка
  /// реальности, активный день) и не уменьшается — рейтинг читается как
  /// достижение.
  ///
  /// Текущие стрики и выполненное «сегодня» добавляем СВЕРХУ: это «живой»
  /// срез на случай, когда копилку ещё не успели прогнать (первый запуск
  /// после обновления), — так цифра не обнуляется у тех, кто уже что-то сделал.
  int localScore() {
    var score = ScoreService().total;
    for (final h in HabitService().habits) {
      if (h.streak > 0) score += h.streak;
    }
    score += TaskService().tasks.where((t) => t.done).length;
    final days = CompletionLogService().lastDays(14);
    var active = 0;
    for (final d in days) {
      if (d.habits > 0 || d.tasks > 0) active++;
    }
    score += active * ScoreWeight.activeDay;
    return score;
  }

  /// Разбор «за что очки»: по каждой категории — сколько накоплено и сколько
  /// приносит одна единица. Идёт из одного источника со счётом, поэтому
  /// подписи не разъезжаются с цифрами.
  Map<ScoreKind, int> scoreBreakdown() => ScoreService().breakdown;

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
        imagePath: _avatarImagePath,
      ),
      ..._friends,
    ]..sort((a, b) => b.score.compareTo(a.score));
    return all;
  }
}
