import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/music_service.dart';
import '../services/new_year_event_service.dart';
import '../services/profile_service.dart';
import '../utils/context_menu.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import '../utils/snackbar.dart';
import '../widgets/inline_keyboard.dart';
import '../widgets/music_pulse_ring.dart';
import '../widgets/online_dot.dart';
import '../widgets/press_scale.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/smooth_digits.dart';
import '../widgets/new_year_event_banner.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/volumetric_switch.dart';

/// Официальный сайт Agysha. Здесь — события проекта; список кэшируется
/// локально, а пункты открываются в браузере. Когда появится публичный фид,
/// сюда достаточно подставить сетевую загрузку — форма карточки не изменится.
const String kAgyshaSiteUrl = 'https://agysha.ru';

/// Плавная шторка листов профиля: кубическая кривая вместо пружины по
/// умолчанию. Пружина на слабых телефонах проседает по кадрам и читается
/// дёрганой; кубика дешёвая и мягкая, а вход чуть длиннее — лист «выезжает»,
/// а не выскакивает.
AnimationStyle _sheetStyle() => AnimationStyle(
  // Мягкое всплытие: `easeOutCubic` разгоняется и плавно тормозит ПО ВСЕЙ
  // дистанции. Прежний `easeOutQuint` проходил почти весь путь в первой
  // трети и резко «втыкался» в конце — вход читался тормознутым.
  curve: Curves.easeOutCubic,
  duration: const Duration(milliseconds: 340),
  // Выход короче и ровный: лист уходит собранно, не задерживая палец.
  reverseCurve: Curves.easeInCubic,
  reverseDuration: const Duration(milliseconds: 240),
);

/// Округлая (капсульная) форма кнопок профиля — та же «отдача фоном», что у
/// кнопок настроек: полное скругление и мягкое вдавливание под пальцем.
/// Тон применяется вызывающим: кнопки — tonal, как экспорт/импорт настроек.
ButtonStyle _roundButtonStyle() => FilledButton.styleFrom(
  shape: const StadiumBorder(),
  padding: const EdgeInsets.symmetric(
    horizontal: Spacing.md,
    vertical: Spacing.sm,
  ),
);

/// Плоское скруглённое поле профиля — как у остальных полей приложения:
/// заливка фоном без жёсткой рамки, подсказка/подпись как обычно, счётчик
/// длины скрыт (лимит и так ощущается обрезкой ввода).
InputDecoration _fieldDecoration(
  ThemeData theme, {
  String? hint,
  String? label,
  double hintAlpha = 1.0,
}) => InputDecoration(
  hintText: hint,
  // Подсказка гаснет и проявляется плавно: [hintAlpha] анимирует состояние
  // экрана при вводе/стирании первой буквы.
  hintStyle: TextStyle(
    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: hintAlpha),
  ),
  labelText: label,
  counterText: '',
  isDense: true,
  filled: true,
  fillColor: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
  contentPadding: const EdgeInsets.symmetric(
    horizontal: Spacing.sm,
    vertical: Spacing.sm,
  ),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(Radii.md),
    borderSide: BorderSide.none,
  ),
);

/// Экран профиля «Agysha-юзера».
///
/// Здесь: короткое имя, цветная аватарка, онлайн-статус (тот самый красный
/// кружок в шапке), рейтинг друзей, своя музыка профиля и события Agysha.
/// Всё хранится локально ([ProfileService]); сеть нужна только для открытия
/// событий в браузере.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _service = ProfileService();
  final _music = MusicService();
  final _nameCtrl = TextEditingController();

  /// Позиция скролла профиля. Нужна для «расплытия» аватарки под верхней
  /// полкой: с ростом прокрутки верх списка мягко размывается и подтухает —
  /// аватарка буквально «уходит под матовое стекло» шапки, а не просто
  /// уползает за край.
  final _scrollCtrl = ScrollController();

  /// Прозрачность подсказки «Как вас звать?»: видна, пока поле НЕ в фокусе.
  /// Подсказка гаснет плавно, как только пользователь открыл поле, и так же
  /// плавно возвращается, когда он его закрыл, — отдельный контроллер, потому
  /// что штатный `hintText` меняется мгновенно и не умеет этого.
  late final AnimationController _hintCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: _nameCtrl.text.isEmpty ? 1 : 0,
  );

  /// Фокус поля имени: подсказка живёт ровно столько, сколько поле закрыто.
  final _nameFocus = FocusNode();

  void _syncHint() {
    // Подсказка видна, пока поле ЗАКРЫТО и пусто: открыл поле — гаснет,
    // закрыл — возвращается. Пока в поле есть имя, подсказку не показываем —
    // иначе она легла бы поверх текста. `_hintCtrl.value` — это и есть
    // прозрачность подсказки: 1 показана, 0 скрыта.
    final shown = !_nameFocus.hasFocus && _nameCtrl.text.isEmpty;
    if (MotionPrefs.shouldReduceMotion) {
      _hintCtrl.value = shown ? 1 : 0;
      return;
    }
    if (shown) {
      _hintCtrl.forward();
    } else {
      _hintCtrl.reverse();
    }
  }

  /// События Agysha: заголовок + ссылка. Пока список локальный — он не
  /// зависит от доступности сайта и открывается мгновенно.
  ///
  /// Новогодний ивент — ОДНИМ пунктом списка: тап по нему открывает то самое
  /// окно со шапками ([NewYearEventBanner]), а не сайт. Раньше ивент жил
  /// отдельной шапкой Деда Мороза в заголовке — теперь он здесь.
  List<_AgyshaEvent> get _events => [
    _AgyshaEvent(
      title: Translations.t('eventNewYear', context, 'Новогодний ивент'),
      subtitle: Translations.t(
        'eventNewYearDesc',
        context,
        'Каждый день — новая шапка до 1 января',
      ),
      url: kAgyshaSiteUrl,
      banner: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _music.addListener(_onMusicChanged);
    _nameCtrl.text = _service.name;
    _nameCtrl.addListener(_syncHint);
    _nameFocus.addListener(_syncHint);
    // Клавиатура не должна «приезжать» в профиль вместе с экраном. Если
    // предыдущий экран оставил открытое поле (или фокус), система поднимает
    // IME сразу при появлении роута — пользователь видит «автовызов
    // клавиатуры». Явно снимаем фокус на первом кадре профиля: поле имени
    // получает ввод только по тапу.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focus = FocusManager.instance.primaryFocus;
      if (focus != null && !_nameFocus.hasFocus) {
        focus.unfocus();
      }
    });
    if (!_service.loaded) {
      _service.load().then((_) {
        if (mounted) {
          _nameCtrl.text = _service.name;
          _syncHint();
        }
      });
    }
  }

  @override
  void dispose() {
    // Плеер НЕ останавливаем и не уничтожаем: музыка — общий сервис, она
    // должна продолжать играть при уходе с экрана (см. [MusicService]).
    _music.removeListener(_onMusicChanged);
    _nameCtrl.removeListener(_syncHint);
    _nameFocus.removeListener(_syncHint);
    _nameFocus.dispose();
    _nameCtrl.dispose();
    _hintCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onMusicChanged() {
    if (mounted) setState(() {});
  }

  void _toast(String message, {IconData icon = Icons.check_circle_outline}) {
    if (!mounted) return;
    showBeautifulSnackBar(context, message: message, icon: icon);
  }

  Future<void> _saveName() async {
    // Имя обрезаем до лимита и снимаем пробелы по краям: в шапке оно
    // показывается как есть, и «хвост» из пробелов там читался бы дырой.
    await _service.setName(_nameCtrl.text.trim());
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    Haptics.light();
    _toast(Translations.t('profileNameSaved', context, 'Имя сохранено'));
  }

  Future<void> _pickAvatar() async {
    Haptics.light();
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) => _AvatarPickerSheet(
        selected: _service.avatarIndex,
        imagePath: _service.avatarImagePath,
        onPick: (i) => Navigator.of(ctx).pop(i),
        onPickImage: () => Navigator.of(ctx).pop(const _PickImageSignal()),
      ),
    );
    // После закрытия листа фокус возвращается предыдущему владельцу, и поле
    // имени могло «подхватить» ввод — система поднимала клавиатуру сама.
    // Явно снимаем фокус: поле профиля получает ввод только по тапу.
    _dropFocus();
    if (picked is _PickImageSignal) {
      await _pickAvatarFromGallery();
    } else if (picked is int) {
      await _service.setAvatarIndex(picked);
    }
  }

  /// Снять фокус с полей после закрытия листов, чтобы клавиатура не
  /// «приезжала» сама (см. `_pickAvatar`).
  void _dropFocus() {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Своя аватарка из галереи: системный пикер картинок, затем копия в
  /// приватную папку — путь из галереи/кэша переживёт не всякий день, а своя
  /// аватарка должна оставаться на месте.
  Future<void> _pickAvatarFromGallery() async {
    final path = await _copyPickedImageToPrivateDir();
    if (path == null) return;
    await _service.setAvatarImage(path);
    if (!mounted) return;
    Haptics.light();
    _toast(Translations.t('profileAvatarSet', context, 'Аватарка обновлена'));
  }

  /// Выбор картинки из галереи с копированием в приватную папку `avatars`.
  /// Возвращает путь копии либо `null`, если пользователь отменил выбор или
  /// копирование не удалось (тогда показываем мягкую ошибку).
  ///
  /// Вынесено отдельно: тем же путём идёт аватарка друга, и дублировать
  /// копирование/обработку ошибок во втором месте не нужно.
  Future<String?> _copyPickedImageToPrivateDir() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null || picked.path == null) return null;
    final src = picked.path!;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${dir.path}/avatars');
      await avatarDir.create(recursive: true);
      final ext = picked.extension?.isNotEmpty == true
          ? picked.extension!
          : 'png';
      final newPath =
          '${avatarDir.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.$ext';
      await File(src).copy(newPath);
      return newPath;
    } catch (_) {
      if (mounted) {
        _toast(
          Translations.t(
            'profileAvatarFailed',
            context,
            'Не удалось загрузить аватарку',
          ),
          icon: Icons.error_outline,
        );
      }
      return null;
    }
  }

  Future<void> _toggleOnline() async {
    Haptics.medium();
    await _service.toggleOnline();
  }

  Future<void> _pickMusic() async {
    // Системный пикер — на время открытия гасим «свои» эффекты.
    final picked = await FilePicker.pickFile(type: FileType.audio);
    if (picked?.path == null) return;
    final srcPath = picked!.path!;
    try {
      // Копируем в приватную папку приложения: путь из общего хранилища или
      // кэша переживёт не всякий день, а свой файл должен играть всегда.
      final dir = await getApplicationDocumentsDirectory();
      final soundsDir = Directory('${dir.path}/sounds');
      await soundsDir.create(recursive: true);
      final ext = picked.extension?.isNotEmpty == true
          ? picked.extension!
          : 'mp3';
      final newPath =
          '${soundsDir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(srcPath).copy(newPath);
      final title = picked.name.isNotEmpty ? picked.name : 'Моя музыка';
      // Останавливаем старый трек и сразу ставим новый. Прежде между ними
      // была искусственная пауза с «пустым» состоянием: карточка успевала
      // показать заглушку, потом прыгала на трек — читалось как рывок и
      // мигание текста. Переход между состояниями делает сам
      // `AnimatedSwitcher` карточки, без ручной задержки.
      await _music.stop();
      if (!mounted) return;
      await _service.setMusic(path: newPath, title: title);
      if (!mounted) return;
      _toast(Translations.t('profileMusicSet', context, 'Музыка сохранена'));
    } catch (_) {
      if (!mounted) return;
      _toast(
        Translations.t(
          'profileMusicFailed',
          context,
          'Не удалось загрузить музыку',
        ),
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _toggleMusicPlayback() async {
    final path = _service.musicPath;
    if (path == null) return;
    Haptics.light();
    final ok = await _music.toggle(path);
    if (!ok && mounted) {
      _toast(
        Translations.t('profileMusicMissing', context, 'Файл не найден'),
        icon: Icons.error_outline,
      );
    }
  }

  Future<void> _removeMusic() async {
    // Состояние меняем СРАЗУ, а затухание плеера уходит в фон: раньше карточка
    // ждала окончания фейда (до 420 мс) и схлопывалась с запозданием —
    // читалось как «дёрнуло». Теперь плашка уезжает плавно и сразу, а звук
    // стихает параллельно.
    final stopping = _music.stop();
    await _service.setMusic();
    await stopping;
  }

  /// Открыть окно новогоднего ивента (пункт «Новогодний ивент» в событиях).
  /// Если ивент сейчас неактивен — сообщаем об этом, а не открываем пустое
  /// окно. Роут с прозрачным барьером: затемнение рисует сам баннер.
  Future<void> _openEventBanner() async {
    if (!NewYearEventService.isActive) {
      _toast(
        Translations.t('eventNewYearSoon', context, 'Ивент ещё не начался'),
        icon: Icons.event_outlined,
      );
      return;
    }
    Haptics.light();
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      routeSettings: const RouteSettings(name: 'dlg:event'),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) => NewYearEventBanner(
        onClose: () {
          if (Navigator.canPop(ctx)) Navigator.of(ctx).pop();
        },
      ),
      transitionBuilder: (ctx, _, _, child) => child,
    );
    // После закрытия ивента клавиатура возвращаться НЕ должна: возврат
    // фокуса роутом поднимал IME прямо на поле имени («автовызов клавиатуры
    // после ивента»). Гасим фокус и на следующем кадре — фреймворк успевает
    // восстановить его уже после `pop`.
    if (!mounted) return;
    _nameFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _nameFocus.unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _openEvent(String url) async {
    Haptics.light();
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _toast(url, icon: Icons.link);
    } catch (_) {
      _toast(url, icon: Icons.link);
    }
  }

  Future<void> _addFriend() async {
    final result = await showModalBottomSheet<_FriendDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      // Лист сам открыть системный пикер не может: после его открытия поверх
      // листа системное окно вернулось бы в приложение, и «свой» лист остался
      // бы под ним. Поэтому выбор картинки идёт через владельца экрана, а лист
      // лишь получает готовый путь и показывает его.
      builder: (ctx) =>
          _AddFriendSheet(onPickImage: _copyPickedImageToPrivateDir),
    );
    // Лист «Добавить друга» несёт собственную клавиатуру; после его закрытия
    // снимаем фокус, иначе система поднимет системную панель в профиле.
    _dropFocus();
    if (result == null) return;
    final ok = await _service.addFriend(
      name: result.name,
      colorIndex: result.colorIndex,
      score: result.score,
      imagePath: result.imagePath,
    );
    if (!mounted) return;
    if (!ok) {
      _toast(
        Translations.t(
          'profileFriendsFull',
          context,
          'В рейтинге уже 50 друзей',
        ),
        icon: Icons.groups_outlined,
      );
      return;
    }
    Haptics.light();
  }

  Future<void> _editFriend(ProfileFriend friend) async {
    // ОДИН маршрут на оба шага: затемнение одно и живёт непрерывно, поэтому
    // позади окна очков больше не появляется «второй тёмный фон», а переход
    // «действия → очки» идёт без паузы и без торможения.
    final outcome = await showModalBottomSheet<_FriendOutcome>(
      context: context,
      backgroundColor: Colors.transparent,
      // Затемнение мягче (0.32 → 0.26): лист лёгкий, тяжёлый барьер «давил».
      barrierColor: Colors.black.withValues(alpha: 0.26),
      isScrollControlled: true,
      sheetAnimationStyle: _sheetStyle(),
      builder: (ctx) => _FriendSheet(
        friend: friend,
        onPickImage: _copyPickedImageToPrivateDir,
      ),
    );
    _dropFocus();
    if (outcome is _FriendScoreSaved) {
      await _service.updateFriend(outcome.friend);
    } else if (outcome is _FriendRemoved) {
      await _service.removeFriend(friend.id);
      Haptics.light();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.t('profile', context, 'Профиль')),
        leading: const BackButtonTooltip(),
        centerTitle: true,
      ),
      body: AnimatedBuilder(
        animation: _service,
        builder: (context, _) => ListView(
          controller: _scrollCtrl,
          padding: const EdgeInsets.fromLTRB(
            Spacing.md,
            Spacing.sm,
            Spacing.md,
            Spacing.xxl,
          ),
          children: [
            _headerCard(theme),
            const SizedBox(height: Spacing.md),
            _nameCard(theme),
            const SizedBox(height: Spacing.md),
            _onlineCard(theme),
            const SizedBox(height: Spacing.md),
            _musicCard(theme),
            const SizedBox(height: Spacing.md),
            _leaderboardCard(theme),
            const SizedBox(height: Spacing.md),
            _eventsCard(theme),
          ],
        ),
      ),
    );
  }

  /// Шапка профиля: крупная аватарка (тап — смена цвета) и имя, слева от
  /// которого — кружок онлайна (тап переключает статус).
  ///
  /// Текстовой строки «В сети / Не в сети» больше нет: статус читается по
  /// кружку, который сам плавно перетекает между красным и пустым.
  Widget _headerCard(ThemeData theme) {
    // Пустое имя в шапке подписываем «Аноним» — как и было; приглашение
    // «Как вас звать?» живёт в поле ввода, а не на месте имени.
    final name = _service.displayName.isEmpty
        ? Translations.t('profileAnonymous', context, 'Аноним')
        : _service.displayName;
    return _Card(
      child: Column(
        children: [
          const SizedBox(height: Spacing.xs),
          PressScale(
            pressedScale: 0.92,
            // Заметно медленнее штатного: аватарка «уходит» под палец и
            // возвращается мягко, а не щёлкает размером.
            duration: const Duration(milliseconds: 520),
            releaseDuration: const Duration(milliseconds: 620),
            child: GestureDetector(
              onTap: _pickAvatar,
              behavior: HitTestBehavior.opaque,
              // При прокрутке аватарка мягко уходит под верхнюю полку:
              // содержимое внутри круга «расплывается» (blur нарастает) и
              // чуть сдвигается — обводка-круг стоит на месте, поэтому нет
              // ни «разрезов», ни дрожания формы. Обратно так же плавно.
              //
              // Источник прокрутки отдан САМОЙ аватарке ([ProfileAvatar.motion]):
              // она перестраивает только свой слой. Раньше `AnimatedBuilder`
              // стоял здесь и каждый кадр прокрутки пересобирал аватарку
              // целиком (со всей шапкой) — на слабом телефоне это лагало.
              child: ProfileAvatar(
                index: _service.avatarIndex,
                size: 96,
                imagePath: _service.avatarImagePath,
                motion: _scrollCtrl,
                motionOf: () =>
                    _scrollCtrl.hasClients ? (_scrollCtrl.offset / 140) : 0.0,
              ),
            ),
          ),
          const SizedBox(height: Spacing.md),
          // Кружок слева от имени — тап по нему переключает онлайн-статус.
          // Зона тапа кружка (30 px) шире глифа (11 px): сдвигаем всю группу
          // влево на её «свес», чтобы по центру карточки осталось ИМЯ, а не
          // середина пары «кружок + имя».
          Center(
            child: Transform.translate(
              offset: Offset(-_dotOverhang, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OnlineDot(size: _dotSize, onTap: _toggleOnline),
                  // Зазор мал: кружок стоит вплотную к первой букве имени, а
                  // не «висит» отдельно от него.
                  const SizedBox(width: 1),
                  // Смена имени (и «Аноним») — плавным кросс-фейдом, а не кадром.
                  AnimatedSwitcher(
                    duration: MotionPrefs.shouldReduceMotion
                        ? Duration.zero
                        : Motion.normal,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(
                        axis: Axis.horizontal,
                        sizeFactor: anim,
                        child: child,
                      ),
                    ),
                    child: Text(
                      name,
                      key: ValueKey(name),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: Weights.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Видимый диаметр кружка онлайна у имени, px.
  static const double _dotSize = 11;

  /// «Свес» зоны тапа кружка влево от глифа: половина разницы между зоной
  /// тапа и самим глифом. На столько сдвигаем пару «кружок + имя», чтобы имя
  /// осталось по центру карточки.
  static const double _dotOverhang = (OnlineDot.tapTarget - _dotSize) / 2;

  /// Лимит короткого имени: 10 символов. Счётчик под полем не нужен —
  /// ввод просто обрезается, а подпись «Короткое имя» уже всё объясняет.
  static const int _nameMaxLength = 10;

  Widget _nameCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileName', context, 'Короткое имя'),
      icon: Icons.badge_outlined,
      child: Row(
        children: [
          Expanded(
            // Как в остальных полях приложения: буквы проявляются и гаснут
            // по одной ([SmoothTyping]), лупа выделения выключена, меню —
            // короткое (Копировать/Вставить/Вырезать). Само поле прозрачное,
            // «мозг» ввода — настоящий TextField внутри.
            //
            // Подсказка «Как вас звать?» нарисована ПОВЕРХ поля отдельным
            // слоем: штатный `hintText` исчезает мгновенно и не умеет
            // возвращаться плавно, а нам нужен мягкий фейд и при вводе, и при
            // стирании.
            child: Stack(
              children: [
                // Невидимое поле ловит тап и отдаёт фокус: тап по подсказке
                // должен открывать ввод, иначе «поле не работает».
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => _nameFocus.requestFocus(),
                  ),
                ),
                SmoothTyping(
                  controller: _nameCtrl,
                  style: theme.textTheme.bodyLarge,
                  builder: (style) => TextField(
                    controller: _nameCtrl,
                    style: style,
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    contextMenuBuilder: minimalContextMenuBuilder,
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.done,
                    maxLength: _nameMaxLength,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_nameMaxLength),
                    ],
                    onSubmitted: (_) => _saveName(),
                    cursorOpacityAnimates: true,
                    decoration: _fieldDecoration(theme),
                  ),
                ),
                IgnorePointer(
                  child: AnimatedBuilder(
                    animation: _hintCtrl,
                    builder: (context, _) {
                      final t = _hintCtrl.value;
                      if (t <= 0.001) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: Spacing.sm),
                          child: Opacity(
                            opacity: t,
                            child: Text(
                              Translations.t(
                                'profileNameHint',
                                context,
                                'Как вас звать?',
                              ),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.xs),
          // Отдача «вдавливанием», как у значка «Назад»: кнопка мягко
          // уменьшается под пальцем и так же возвращается.
          PressScale(
            pressedScale: 0.94,
            child: FilledButton.tonal(
              onPressed: _saveName,
              style: _roundButtonStyle(),
              child: Text(Translations.t('save', context, 'Сохранить')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _onlineCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileOnlineTitle', context, 'Онлайн-статус'),
      icon: Icons.podcasts_outlined,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.t(
                    'profileOnlineSwitch',
                    context,
                    'Показывать красный кружок',
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  Translations.t(
                    'profileOnlineSwitchDesc',
                    context,
                    'Другие увидят, что вы на связи',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Spacing.sm),
          // Тот же объёмный переключатель, что в настройках: статус не
          // выпадает из общего вида приложения.
          VolumetricSwitch(
            value: _service.online,
            onChanged: (_) => _toggleOnline(),
            activeColor: theme.colorScheme.primary,
            semanticLabel: Translations.t(
              'profileOnlineSwitch',
              context,
              'Показывать красный кружок',
            ),
          ),
        ],
      ),
    );
  }

  Widget _musicCard(ThemeData theme) {
    final hasMusic = _service.musicPath != null;
    final playing = _music.playing && _music.path == _service.musicPath;
    // Плашка меняется ПЛАВНО: между «пусто», строкой трека и подписью
    // кнопки играет AnimatedSize + AnimatedSwitcher — добавление, замена и
    // удаление музыки не «щёлкают» раскладкой.
    final crossDur = MotionPrefs.shouldReduceMotion
        ? Duration.zero
        : Motion.slow;
    return _Card(
      title: Translations.t('profileMusic', context, 'Твоя музыка'),
      icon: Icons.music_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Смена «пусто ↔ трек» — ОДНИМ механизмом: `AnimatedCrossFade`
          // сам и проявляет, и тянет высоту ОДНОЙ кривой. Раньше проявку
          // делал `AnimatedSwitcher`, а высоту — внешний `AnimatedSize`, и
          // они спорили: карточка дёргала текст и «скукоживалась» рывком
          // при удалении трека.
          AnimatedCrossFade(
            duration: crossDur,
            sizeCurve: Curves.easeOutCubic,
            firstCurve: Curves.easeOut,
            secondCurve: Curves.easeIn,
            crossFadeState: hasMusic
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: hasMusic
                // Гасим чернильные всплески ListTile: без этого при тапе по
                // строке под пальцем вспыхивал прямоугольник на всю ширину
                // карточки («квадрат»). Кнопки внутри сохраняют свой отклик.
                ? Theme(
                    data: theme.copyWith(
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                    ),
                    child: ListTile(
                      key: const ValueKey('music_row'),
                      contentPadding: EdgeInsets.zero,
                      // Слева — кнопка проигрывания, справа — корзина:
                      // привычный порядок строки, как было раньше.
                      leading: PressScale(
                        pressedScale: 0.88,
                        child: MusicPulseRing(
                          active: playing,
                          child: IconButton(
                            onPressed: _toggleMusicPlayback,
                            // Полностью прозрачно: под пальцем нет ни
                            // квадратной заливки, ни круга — только кольцо.
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: Colors.transparent,
                              foregroundColor: theme.colorScheme.primary,
                              highlightColor: Colors.transparent,
                              hoverColor: Colors.transparent,
                            ),
                            icon: AnimatedSwitcher(
                              // Значок плей/пауза сменяется медленно и мягко,
                              // а не подменой кадром.
                              duration: MotionPrefs.shouldReduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 460),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              // Оба значка в одной ячейке, выровнены по
                              // центру: иначе «пауза» и «плей» разной ширины
                              // дёргали бы кнопку вбок при смене.
                              layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.center,
                                children: [...previous, ?current],
                              ),
                              // Мягкая смена: входящий значок проявляется и
                              // чуть подрастает, уходящий так же плавно
                              // гаснет. Считаем ПРОСТО по `anim` (без
                              // сравнения ключей): прежний вариант с
                              // `child.key == ValueKey(playing)` при быстром
                              // двойном тапе путал «входящий/уходящий» и
                              // оставлял значок с нулевой прозрачностью —
                              // кнопка на миг пропадала.
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                    opacity: anim,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.75,
                                        end: 1,
                                      ).animate(anim),
                                      child: child,
                                    ),
                                  ),
                              child: Icon(
                                playing
                                    ? Icons.pause
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(playing),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Подпись — как была раньше: «Играет бодрый звук».
                      title: Text(
                        Translations.t(
                          'profileMusicPlaying',
                          context,
                          'Играет бодрый звук',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PressScale(
                        pressedScale: 0.86,
                        child: IconButton(
                          onPressed: _removeMusic,
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                            highlightColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Text(
                Translations.t(
                  'profileMusicEmpty',
                  context,
                  'Добавьте свой трек — он будет играть в профиле',
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: PressScale(
              pressedScale: 0.94,
              // Подпись кнопки («Выбрать файл» ↔ «Заменить») меняется
              // ПЛАВНО: AnimatedSize тянет ширину, AnimatedSwitcher — текст.
              // Длительность — та же, что у самой карточки: добавление и
              // удаление трека идут ОДНОЙ анимацией, а не двумя
              // рассинхронизированными (кнопка «доъезжала» после плашки).
              child: AnimatedSize(
                duration: MotionPrefs.shouldReduceMotion
                    ? Duration.zero
                    : Motion.slow,
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: _pickMusic,
                  style: _roundButtonStyle(),
                  icon: const Icon(Icons.library_music_outlined),
                  label: AnimatedSwitcher(
                    duration: MotionPrefs.shouldReduceMotion
                        ? Duration.zero
                        : Motion.normal,
                    // Свой layoutBuilder: ширина берётся по ВХОДЯЩЕЙ
                    // подписи, а не по максимуму из двух. Штатный `Stack`
                    // раздувал кнопку под «Заменить»/«Выбрать файл» сразу,
                    // и AnimatedSize потом «доводил» её рывком.
                    layoutBuilder: (current, previous) =>
                        current ?? const SizedBox.shrink(),
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Text(
                      hasMusic
                          ? Translations.t(
                              'profileMusicChange',
                              context,
                              'Заменить',
                            )
                          : Translations.t(
                              'profileMusicAdd',
                              context,
                              'Выбрать файл',
                            ),
                      key: ValueKey('music_btn_$hasMusic'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaderboardCard(ThemeData theme) {
    final rows = _service.leaderboard(
      selfFallback: Translations.t('profileMe', context, 'Я'),
    );
    return _Card(
      title: Translations.t('profileLeaderboard', context, 'Рейтинг'),
      icon: Icons.emoji_events_outlined,
      // Кнопка «добавить друга» — БЕЗ цветной оправы: красный кант читался
      // случайным ободком вокруг системной иконки. Отдачу под пальцем держит
      // `PressScale`, а сама кнопка остаётся штатной `IconButton`.
      trailing: PressScale(
        pressedScale: 0.86,
        child: IconButton(
          // На пределе (50 друзей) кнопка гаснет: понятно, что дальше
          // добавлять некуда, и не приходится жать «в пустоту».
          onPressed: _service.canAddFriend ? _addFriend : null,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          tooltip: _service.canAddFriend
              ? Translations.t('profileAddFriend', context, 'Добавить друга')
              : Translations.t(
                  'profileFriendsFull',
                  context,
                  'В рейтинге уже 50 друзей',
                ),
        ),
      ),
      // Строки рейтинга ПЕРЕЕЗЖАЮТ плавно: каждая строка лежит в общем
      // «слое» на своей вертикальной позиции (`AnimatedPositioned` по ключу
      // друга), поэтому смена очков меняет места анимацией, а не мгновенной
      // перестановкой. AnimatedSize тянет высоту при добавлении/удалении.
      child: AnimatedSize(
        duration: MotionPrefs.shouldReduceMotion ? Duration.zero : Motion.slow,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: rows.length * _leaderRowHeight,
              child: Stack(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    AnimatedPositioned(
                      // Ключ — id друга: при смене очков Flutter видит тот же
                      // виджет на новой позиции и анимирует переезд.
                      key: ValueKey(rows[i].id),
                      duration: MotionPrefs.shouldReduceMotion
                          ? Duration.zero
                          : Motion.glide,
                      curve: Curves.easeOutCubic,
                      left: 0,
                      right: 0,
                      top: i * _leaderRowHeight,
                      child: SizedBox(
                        height: _leaderRowHeight,
                        child: _leaderRow(
                          theme,
                          rows[i],
                          rank: i + 1,
                          isMe: rows[i].id == 'me',
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_service.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  Translations.t(
                    'profileNoFriends',
                    context,
                    'Добавьте друзей, чтобы сравнивать прогресс',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _leaderRow(
    ThemeData theme,
    ProfileFriend f, {
    required int rank,
    required bool isMe,
  }) {
    final cs = theme.colorScheme;
    return PressScale(
      // Строка друга мягко уменьшается под пальцем и так же плавно
      // возвращается: зажатие карточки читается как нажатие.
      pressedScale: 0.97,
      duration: const Duration(milliseconds: 180),
      releaseDuration: const Duration(milliseconds: 320),
      enabled: !isMe,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: isMe ? null : () => _editFriend(f),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: rank <= 3 ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: Weights.bold,
                  ),
                ),
              ),
              ProfileAvatar(
                index: f.colorIndex,
                size: 36,
                // Своя аватарка из галереи — и в строке «Я» рейтинга, и у
                // друзей: картинка приходит в самой строке (`f.imagePath`),
                // поэтому после выбора она сразу и плавно встаёт на место
                // сгенерированного варианта.
                imagePath: f.imagePath,
              ),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: isMe ? Weights.bold : Weights.regular,
                  ),
                ),
              ),
              // Очки меняются ПО БУКВАМ, тем же приёмом, что и поле «Очки
              // рейтинга» ([SmoothTyping]): изменившаяся цифра проявляется из
              // прозрачного, старая мягко гаснет. Раньше здесь «докатывался»
              // барабан `AnimatedCounter` — при правке счёта он читался грубым
              // подменом. `sample` держит ширину, чтобы при «99 → 100» строка
              // не дёргалась по горизонтали.
              SmoothDigits(
                value: f.score,
                sample: '0000',
                alignment: Alignment.centerRight,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: Weights.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _eventsCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileEvents', context, 'События'),
      icon: Icons.event_outlined,
      child: Column(
        children: [
          for (final e in _events)
            // Отдача уменьшением + СКРУГЛЁННЫЙ фон зажатия: тап по пункту
            // события читается как нажатие, а подсветка повторяет форму
            // строки, а не заливает квадрат.
            PressScale(
              pressedScale: 0.96,
              duration: const Duration(milliseconds: 180),
              releaseDuration: const Duration(milliseconds: 320),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: () => e.banner ? _openEventBanner() : _openEvent(e.url),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          Icons.local_activity_outlined,
                          color: theme.colorScheme.onPrimaryContainer,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.title,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: Weights.semibold,
                              ),
                            ),
                            Text(
                              e.subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Icon(
                        e.banner
                            ? Icons.celebration_outlined
                            : Icons.open_in_new,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Пункт списка событий.
class _AgyshaEvent {
  final String title;
  final String subtitle;
  final String url;

  /// true — пункт открывает окно новогоднего ивента, а не сайт.
  final bool banner;

  const _AgyshaEvent({
    required this.title,
    required this.subtitle,
    required this.url,
    this.banner = false,
  });
}

/// Карточка с заголовком-иконкой и содержимым — общий вид всех блоков
/// профиля, чтобы экран читался как единое целое.
class _Card extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  const _Card({this.title, this.icon, this.trailing, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Material, а не просто DecoratedBox: ListTile внутри карточки рисует
    // чернильные волны на ближайшем Material, и без него они были бы
    // «спрятаны» фоном карточки (Flutter ругается assertion'ом).
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.xl),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xl),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: Spacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            if (title != null) const SizedBox(height: Spacing.xs),
            child,
          ],
        ),
      ),
    );
  }
}

/// Сигнал «выбрать свою аватарку из галереи»: лист закрывается с ним, а
/// экран открывает системный пикер уже после закрытия листа.
class _PickImageSignal {
  const _PickImageSignal();
}

/// Нижний лист выбора аватарки: первым — «своя из галереи», дальше сетка
/// градиентов, выбранный — с рамкой.
class _AvatarPickerSheet extends StatelessWidget {
  final int selected;
  final String? imagePath;
  final ValueChanged<int> onPick;
  final VoidCallback onPickImage;

  const _AvatarPickerSheet({
    required this.selected,
    required this.onPick,
    required this.onPickImage,
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.t('profilePickAvatar', context, 'Аватарка'),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: Weights.bold,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            // Своя аватарка — ПЕРВОЙ, отдельной крупной кнопкой: это главный
            // выбор, а не один из 48 вариантов. Пока картинка не выбрана,
            // кружок пустой с иконкой галереи; после выбора — сама картинка.
            PressScale(
              pressedScale: 0.9,
              duration: const Duration(milliseconds: 260),
              releaseDuration: const Duration(milliseconds: 520),
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.md),
                onTap: onPickImage,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Row(
                    children: [
                      ProfileAvatar(
                        index: selected,
                        size: 44,
                        imagePath: imagePath,
                        showIcon: imagePath == null,
                      ),
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: Text(
                          Translations.t(
                            'profileAvatarFromGallery',
                            context,
                            'Своя аватарка из галереи',
                          ),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: Weights.semibold,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: Spacing.lg),
            SizedBox(
              height: 300,
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: Spacing.sm,
                  crossAxisSpacing: Spacing.sm,
                ),
                itemCount: profileAvatarVariants.length,
                itemBuilder: (context, i) {
                  final isSelected = i == selected;
                  return PressScale(
                    // Кружки отдают под пальцем и мягко возвращаются: тап по
                    // аватарке читается как нажатие, а не как «мёртвый» выбор.
                    // Возврат заметно длиннее вдавливания — отпускание не
                    // щёлкает, кружок «выплывает» обратно.
                    pressedScale: 0.82,
                    duration: const Duration(milliseconds: 260),
                    releaseDuration: const Duration(milliseconds: 520),
                    child: GestureDetector(
                      onTap: () => onPick(i),
                      // Обводка выбора перетекает плавно (AnimatedContainer), а
                      // не появляется кадром: тап по аватарке не «щёлкает».
                      child: AnimatedContainer(
                        duration: MotionPrefs.shouldReduceMotion
                            ? Duration.zero
                            : Motion.normal,
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: ProfileAvatar(index: i, size: 40),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Черновик нового друга из нижнего листа.
class _FriendDraft {
  final String name;
  final int colorIndex;
  final int score;

  /// Своя аватарка из галереи, если её выбрали в листе. `null` — показываем
  /// сгенерированный вариант по [colorIndex].
  final String? imagePath;
  const _FriendDraft(this.name, this.colorIndex, this.score, {this.imagePath});
}

/// Максимальная длина имени друга.
const int _kFriendNameMax = 30;

/// Максимальное число знаков в очках рейтинга.
const int _kFriendScoreMax = 7;

/// Высота одной строки рейтинга. Фиксирована: строки живут в общем «слое»
/// на вычисленных позициях, и переезд при смене очков — это анимация `top`.
const double _leaderRowHeight = 52;

/// Случайные «весёлые» очки 40…990.
///
/// Раньше число выводилось детерминированно из имени (хэш строки), и кнопка
/// «кубик» выдавала ОДНО И ТО ЖЕ значение при каждом нажатии — «случайные
/// очки» не рандомили вовсе. Теперь источник — настоящий ГПСЧ, а имя лишь
/// сдвигает диапазон, чтобы число не выглядело совсем произвольным.
String _funScore(String seed) {
  var h = 7;
  for (final c in seed.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  final r = math.Random().nextInt(951);
  return '${40 + ((r + h) % 951)}';
}

/// Добавление друга: имя, аватарка, стартовые очки.
class _AddFriendSheet extends StatefulWidget {
  /// Выбор своей картинки из галереи. Лист сам системный пикер не открывает
  /// (см. `_addFriend`): владелец экрана возвращает готовый путь копии либо
  /// `null`, если выбор отменили или копирование не удалось.
  final Future<String?> Function() onPickImage;

  const _AddFriendSheet({required this.onPickImage});

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _ctrl = TextEditingController();
  int _avatar = 0;

  /// Своя аватарка друга, выбранная в этом листе. Пока задана — крупный
  /// кружок показывает её, а не сгенерированный вариант по [_avatar].
  String? _imagePath;

  /// Идёт ли выбор картинки: пока системный пикер открыт, повторные тапы по
  /// аватарке не должны запускать второй запрос.
  bool _picking = false;
  final _scoreCtrl = TextEditingController();

  /// Какое поле печатает встроенная клавиатура. Системная панель тут не
  /// нужна: лист везёт собственную (см. [InlineKeyboard]), а поля — readOnly.
  _FriendField _target = _FriendField.name;
  final _nameFocus = FocusNode();
  final _scoreFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // Очки при открытии — «весёлое» число из имени-заглушки, а не сухой ноль.
    _scoreCtrl.text = _funScore('');
    _nameFocus.addListener(_syncTarget);
    _scoreFocus.addListener(_syncTarget);
  }

  void _syncTarget() {
    if (_nameFocus.hasFocus) {
      setState(() => _target = _FriendField.name);
    } else if (_scoreFocus.hasFocus) {
      setState(() => _target = _FriendField.score);
    }
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_syncTarget);
    _scoreFocus.removeListener(_syncTarget);
    _nameFocus.dispose();
    _scoreFocus.dispose();
    _ctrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  void _insert(String ch) {
    final ctrl = _target == _FriendField.name ? _ctrl : _scoreCtrl;
    final max = _target == _FriendField.name
        ? _kFriendNameMax
        : _kFriendScoreMax;
    // В очки пускаем только цифры.
    if (_target == _FriendField.score && !RegExp(r'^\d$').hasMatch(ch)) return;
    if (ctrl.text.length >= max) return;
    ctrl.text = ctrl.text + ch;
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  void _backspace() {
    final ctrl = _target == _FriendField.name ? _ctrl : _scoreCtrl;
    if (ctrl.text.isEmpty) return;
    ctrl.text = ctrl.text.substring(0, ctrl.text.length - 1);
    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
  }

  void _space() {
    if (_target != _FriendField.name) return;
    if (_ctrl.text.length >= _kFriendNameMax) return;
    _ctrl.text = '${_ctrl.text} ';
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final score = int.tryParse(_scoreCtrl.text.trim()) ?? 0;
    Navigator.of(
      context,
    ).pop(_FriendDraft(name, _avatar, score, imagePath: _imagePath));
  }

  /// Тап по крупной аватарке: своя картинка из галереи. Пока выбор идёт —
  /// повторные тапы игнорируются, а по возвращении путь мягко подставляется
  /// в кружок (кроссфейд делает сам `ProfileAvatar`).
  Future<void> _pickImage() async {
    if (_picking) return;
    setState(() => _picking = true);
    final path = await widget.onPickImage();
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path != null) _imagePath = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translations.t(
                        'profileAddFriend',
                        context,
                        'Добавить друга',
                      ),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: Weights.bold,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      children: [
                        // Крупная аватарка — сама по себе кнопка «своя из
                        // галереи»: тап открывает пикер, выбранная картинка
                        // встаёт на место градиента кроссфейдом. Значок
                        // камеры подсказывает, что кружок нажимается.
                        PressScale(
                          pressedScale: 0.9,
                          duration: const Duration(milliseconds: 240),
                          releaseDuration: const Duration(milliseconds: 460),
                          child: GestureDetector(
                            onTap: _pickImage,
                            behavior: HitTestBehavior.opaque,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                ProfileAvatar(
                                  index: _avatar,
                                  size: 52,
                                  imagePath: _imagePath,
                                  showIcon: _imagePath == null,
                                ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: theme.colorScheme.surface,
                                      border: Border.all(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.photo_camera_outlined,
                                      size: 13,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.md),
                        Expanded(
                          child: SmoothTyping(
                            controller: _ctrl,
                            style: theme.textTheme.bodyLarge,
                            // Без «призраков»: удержание «стереть» на имени
                            // рисовало десяток гаснущих копий и читалось как
                            // заедание. Появление букв остаётся плавным, а
                            // удаление — мгновенным и ровным.
                            ghosts: false,
                            builder: (style) => TextField(
                              controller: _ctrl,
                              style: style,
                              focusNode: _nameFocus,
                              readOnly: true,
                              showCursor: true,
                              magnifierConfiguration:
                                  TextMagnifierConfiguration.disabled,
                              contextMenuBuilder: minimalContextMenuBuilder,
                              cursorOpacityAnimates: true,
                              maxLength: _kFriendNameMax,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(
                                  _kFriendNameMax,
                                ),
                              ],
                              decoration: _fieldDecoration(
                                theme,
                                hint: Translations.t(
                                  'profileFriendName',
                                  context,
                                  'Имя друга',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    SizedBox(
                      height: 46,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: profileAvatarVariants.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: Spacing.xs),
                        itemBuilder: (context, i) => PressScale(
                          pressedScale: 0.86,
                          duration: const Duration(milliseconds: 180),
                          releaseDuration: const Duration(milliseconds: 340),
                          child: GestureDetector(
                            // Выбор градиента снимает свою картинку: иначе
                            // непонятно, что показывать в кружке, — и аватарка
                            // мягко возвращается к сгенерированному варианту.
                            onTap: () => setState(() {
                              _avatar = i;
                              _imagePath = null;
                            }),
                            child: AnimatedContainer(
                              duration: MotionPrefs.shouldReduceMotion
                                  ? Duration.zero
                                  : Motion.normal,
                              curve: Curves.easeOutCubic,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: i == _avatar
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              padding: const EdgeInsets.all(2),
                              child: ProfileAvatar(index: i, size: 34),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: SmoothTyping(
                            controller: _scoreCtrl,
                            style: theme.textTheme.bodyLarge,
                            ghosts: false,
                            builder: (style) => TextField(
                              controller: _scoreCtrl,
                              style: style,
                              focusNode: _scoreFocus,
                              readOnly: true,
                              showCursor: true,
                              magnifierConfiguration:
                                  TextMagnifierConfiguration.disabled,
                              contextMenuBuilder: minimalContextMenuBuilder,
                              cursorOpacityAnimates: true,
                              maxLength: _kFriendScoreMax,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(
                                  _kFriendScoreMax,
                                ),
                              ],
                              decoration: _fieldDecoration(
                                theme,
                                label: Translations.t(
                                  'profileFriendScore',
                                  context,
                                  'Очки рейтинга',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        PressScale(
                          pressedScale: 0.9,
                          child: IconButton.filledTonal(
                            tooltip: Translations.t(
                              'profileFriendScoreRandom',
                              context,
                              'Случайные очки',
                            ),
                            onPressed: () => setState(
                              () => _scoreCtrl.text = _funScore(_ctrl.text),
                            ),
                            icon: const Icon(Icons.casino_outlined),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.xs),
                    Text(
                      Translations.t(
                        'profileFriendScoreHint',
                        context,
                        'Очки — за активность: привычки, задачи, дни в логе. '
                            'Чем больше — тем выше в рейтинге.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: PressScale(
                        pressedScale: 0.96,
                        child: FilledButton.tonal(
                          onPressed: _submit,
                          style: _roundButtonStyle(),
                          child: Text(
                            Translations.t('add', context, 'Добавить'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Клавиатура — в самом низу листа, под тему приложения.
              InlineKeyboard(
                onChar: _insert,
                onBackspace: _backspace,
                onSpace: _space,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Поле, которое печатает встроенная клавиатура листа «Добавить друга».
enum _FriendField { name, score }

/// Итог листа над другом: сохранённые очки либо удаление.
sealed class _FriendOutcome {
  const _FriendOutcome();
}

class _FriendScoreSaved extends _FriendOutcome {
  final ProfileFriend friend;
  const _FriendScoreSaved(this.friend);
}

class _FriendRemoved extends _FriendOutcome {
  const _FriendRemoved();
}

/// Один лист над другом: сначала «Очки/Удалить», по тапу на «Очки» он же
/// ПЕРЕТЕКАЕТ в правку очков.
///
/// Раньше это были два отдельных маршрута: лист действий закрывался, а лист
/// очков открывался следом. Из-за этого затемнения двух маршрутов коротко
/// складывались — позади окна появлялся «второй тёмный фон», а пауза перед
/// открытием читалась торможением. Теперь маршрут ОДИН: затемнение одно и
/// живёт непрерывно, переключение — мягкая смена содержимого с плавной
/// высотой, без закрытия/открытия.
class _FriendSheet extends StatefulWidget {
  final ProfileFriend friend;

  /// Выбор своей картинки из галереи (см. `_copyPickedImageToPrivateDir`).
  /// Передаётся в шаги, чтобы аватарку друга можно было сменить прямо из
  /// листа: тап по кружку — пикер, картинка встаёт на место градиента
  /// кроссфейдом, а в рейтинге строка обновляется тем же сохранением.
  final Future<String?> Function() onPickImage;

  const _FriendSheet({required this.friend, required this.onPickImage});

  @override
  State<_FriendSheet> createState() => _FriendSheetState();
}

class _FriendSheetState extends State<_FriendSheet> {
  bool _score = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MotionPrefs.shouldReduceMotion;
    return AnimatedSize(
      duration: reduce ? Duration.zero : Motion.slow,
      curve: Motion.emphasized,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : Motion.normal,
        // Кривая с НУЛЕВОЙ скоростью на обоих концах: шаг не «выстреливает»
        // в первый кадр и не щёлкает в последнем — переход читается мягким.
        switchInCurve: Motion.emphasized,
        switchOutCurve: Motion.emphasized,
        // Кросс-фейд шагов выравниваем ПО ВЕРХУ: у шага очков высота больше
        // (внизу клавиатура), и при центрировании короткий список действий
        // «прыгал» бы вверх. Ширину/высоту тянет `AnimatedSize` выше.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          children: [...previous, ?current],
        ),
        // Проявление + лёгкий «доезд» снизу: шаг не подменяется кадром, а
        // всплывает на место. Оба направления симметричны, поэтому не нужен
        // разбор «входящий/уходящий» по ключу.
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        child: _score
            ? _FriendScoreSheet(
                key: const ValueKey('friend_score'),
                friend: widget.friend,
                onSave: (updated) =>
                    Navigator.of(context).pop(_FriendScoreSaved(updated)),
              )
            : _FriendActionsSheet(
                key: const ValueKey('friend_actions'),
                friend: widget.friend,
                onScore: () => setState(() => _score = true),
                onRemove: () =>
                    Navigator.of(context).pop(const _FriendRemoved()),
                // Смена аватарки сохраняется сразу: лист закрывается с новым
                // другом, и строка рейтинга перетекает на его новую картинку.
                onAvatar: () async {
                  final path = await widget.onPickImage();
                  if (path == null || !context.mounted) return;
                  Navigator.of(context).pop(
                    _FriendScoreSaved(widget.friend.copyWith(imagePath: path)),
                  );
                },
              ),
      ),
    );
  }
}

/// Действия над другом: изменить очки или удалить.
class _FriendActionsSheet extends StatelessWidget {
  final ProfileFriend friend;
  final VoidCallback onScore;
  final VoidCallback onRemove;

  /// Тап по аватарке друга: сменить её на свою из галереи.
  final VoidCallback onAvatar;

  const _FriendActionsSheet({
    super.key,
    required this.friend,
    required this.onScore,
    required this.onRemove,
    required this.onAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Radii.sheetTop,
          ),
          padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(Spacing.md),
                child: Row(
                  children: [
                    // Кружок нажимается: своя аватарка друга из галереи.
                    // Значок камеры — подсказка, что аватарка меняется.
                    PressScale(
                      pressedScale: 0.9,
                      duration: const Duration(milliseconds: 240),
                      releaseDuration: const Duration(milliseconds: 460),
                      child: GestureDetector(
                        onTap: onAvatar,
                        behavior: HitTestBehavior.opaque,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ProfileAvatar(
                              index: friend.colorIndex,
                              size: 44,
                              imagePath: friend.imagePath,
                              showIcon: !friend.hasImage,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: theme.colorScheme.surface,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.photo_camera_outlined,
                                  size: 12,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Text(
                      friend.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: Weights.semibold,
                      ),
                    ),
                  ],
                ),
              ),
              // Отдача «вдавливанием» на обеих строках: раньше тап по «Очки»
              // и «Удалить» срабатывал без отклика, и палец не чувствовал
              // нажатия.
              _actionTile(
                context,
                theme,
                icon: Icons.tune,
                label: Translations.t('profileFriendSetScore', context, 'Очки'),
                // Смена шага — сразу, без искусственной паузы: плавность
                // теперь несёт сам переход (`SlideTransition` + `AnimatedSize`),
                // а задержка только добавляла лаг между пальцем и откликом.
                onTap: onScore,
              ),
              _actionTile(
                context,
                theme,
                icon: Icons.delete_outline,
                label: Translations.t('delete', context, 'Удалить'),
                danger: true,
                onTap: onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    // Раньше строка была `ListTile`: его чернильная волна заливала
    // ПРЯМОУГОЛЬНИК на всю ширину листа, и подсветка читалась «квадратом».
    // `InkWell` со скруглением повторяет форму строки — вспышка под пальцем
    // мягкая и округлая.
    return PressScale(
      // Медленнее и глубже: строка ощутимо «уходит» под палец и мягко
      // возвращается — раньше 150 мс читались как резкий щелчок.
      pressedScale: 0.95,
      duration: const Duration(milliseconds: 240),
      releaseDuration: const Duration(milliseconds: 380),
      child: Material(
        // Свой Material: без него чернильная волна уходила под фон
        // `Container` листа, и Flutter ругался на невидимые splashes.
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: Spacing.md),
                Text(label, style: TextStyle(color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Изменение очков друга.
class _FriendScoreSheet extends StatefulWidget {
  final ProfileFriend friend;

  /// Отдать сохранённые очки НАРУЖУ. Раньше лист сам делал `pop`, потому что
  /// был отдельным маршрутом; теперь он лишь шаг внутри [_FriendSheet], и
  /// закрывать общий маршрут должен его владелец.
  final ValueChanged<ProfileFriend> onSave;

  const _FriendScoreSheet({
    super.key,
    required this.friend,
    required this.onSave,
  });

  @override
  State<_FriendScoreSheet> createState() => _FriendScoreSheetState();
}

class _FriendScoreSheetState extends State<_FriendScoreSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: '${widget.friend.score}',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _insert(String ch) {
    if (!RegExp(r'^\d$').hasMatch(ch)) return;
    if (_ctrl.text.length >= _kFriendScoreMax) return;
    _ctrl.text = _ctrl.text + ch;
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _backspace() {
    if (_ctrl.text.isEmpty) return;
    _ctrl.text = _ctrl.text.substring(0, _ctrl.text.length - 1);
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: Radii.sheetTop,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  Spacing.md,
                  Spacing.md,
                  Spacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Шапка — как у листа действий: аватарка и имя друга.
                    // Раньше окно очков открывалось «с пустого места» — было
                    // не понять, кому правишь счёт.
                    Row(
                      children: [
                        ProfileAvatar(
                          index: widget.friend.colorIndex,
                          size: 40,
                          imagePath: widget.friend.imagePath,
                          showIcon: !widget.friend.hasImage,
                        ),
                        const SizedBox(width: Spacing.sm),
                        Expanded(
                          child: Text(
                            widget.friend.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: Weights.semibold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: SmoothTyping(
                            controller: _ctrl,
                            style: theme.textTheme.bodyLarge,
                            ghosts: false,
                            builder: (style) => TextField(
                              controller: _ctrl,
                              style: style,
                              readOnly: true,
                              showCursor: true,
                              magnifierConfiguration:
                                  TextMagnifierConfiguration.disabled,
                              contextMenuBuilder: minimalContextMenuBuilder,
                              cursorOpacityAnimates: true,
                              maxLength: _kFriendScoreMax,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(
                                  _kFriendScoreMax,
                                ),
                              ],
                              decoration: _fieldDecoration(
                                theme,
                                label: Translations.t(
                                  'profileFriendScore',
                                  context,
                                  'Очки рейтинга',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.xs),
                        PressScale(
                          pressedScale: 0.9,
                          child: IconButton.filledTonal(
                            tooltip: Translations.t(
                              'profileFriendScoreRandom',
                              context,
                              'Случайные очки',
                            ),
                            onPressed: () => setState(
                              () => _ctrl.text = _funScore(widget.friend.name),
                            ),
                            icon: const Icon(Icons.casino_outlined),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: PressScale(
                        pressedScale: 0.96,
                        child: FilledButton.tonal(
                          onPressed: () {
                            final score = int.tryParse(_ctrl.text.trim()) ?? 0;
                            widget.onSave(widget.friend.copyWith(score: score));
                          },
                          style: _roundButtonStyle(),
                          child: Text(
                            Translations.t('save', context, 'Сохранить'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              InlineKeyboard(
                onChar: _insert,
                onBackspace: _backspace,
                onSpace: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}
