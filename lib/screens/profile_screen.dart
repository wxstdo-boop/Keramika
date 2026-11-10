import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/profile_service.dart';
import '../utils/context_menu.dart';
import '../utils/design_tokens.dart';
import '../utils/motion_prefs.dart';
import '../utils/snackbar.dart';
import '../widgets/online_dot.dart';
import '../widgets/press_scale.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/smooth_typing.dart';

/// Официальный сайт Keramika. Здесь — события проекта; список кэшируется
/// локально, а пункты открываются в браузере. Когда появится публичный фид,
/// сюда достаточно подставить сетевую загрузку — форма карточки не изменится.
const String kKeramikaSiteUrl = 'https://keramika.ru';

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
}) => InputDecoration(
  hintText: hint,
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

/// Экран профиля «керамика-юзера».
///
/// Здесь: короткое имя, цветная аватарка, онлайн-статус (тот самый красный
/// кружок в шапке), рейтинг друзей, своя музыка профиля и события Keramika.
/// Всё хранится локально ([ProfileService]); сеть нужна только для открытия
/// событий в браузере.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _service = ProfileService();
  final _nameCtrl = TextEditingController();

  AudioPlayer? _player;
  bool _playingMusic = false;

  /// События Keramika: заголовок + ссылка. Пока список локальный — он не
  /// зависит от доступности сайта и открывается мгновенно.
  List<_KeramikaEvent> get _events => [
    _KeramikaEvent(
      title: Translations.t('eventNewYear', context, 'Новогодний ивент'),
      subtitle: Translations.t(
        'eventNewYearDesc',
        context,
        'Каждый день — новая шапка до 1 января',
      ),
      url: kKeramikaSiteUrl,
    ),
    _KeramikaEvent(
      title: Translations.t('eventCeramics', context, 'Керамическая ярмарка'),
      subtitle: Translations.t(
        'eventCeramicsDesc',
        context,
        'Мастер-классы и обжиг для новичков',
      ),
      url: kKeramikaSiteUrl,
    ),
    _KeramikaEvent(
      title: Translations.t('eventCommunity', context, 'Встреча сообщества'),
      subtitle: Translations.t(
        'eventCommunityDesc',
        context,
        'Онлайн-сбор керамика-юзеров раз в месяц',
      ),
      url: kKeramikaSiteUrl,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = _service.name;
    if (!_service.loaded) {
      _service.load().then((_) {
        if (mounted) setState(() => _nameCtrl.text = _service.name);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _player?.dispose();
    super.dispose();
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
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AvatarPickerSheet(
        selected: _service.avatarIndex,
        onPick: (i) => Navigator.of(ctx).pop(i),
      ),
    );
    if (picked != null) await _service.setAvatarIndex(picked);
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
      await _service.setMusic(path: newPath, title: title);
      if (!mounted) return;
      setState(() {});
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
    final player = _player ??= AudioPlayer();
    if (_playingMusic) {
      await player.stop();
      if (mounted) setState(() => _playingMusic = false);
      return;
    }
    try {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        _toast(
          Translations.t('profileMusicMissing', context, 'Файл не найден'),
          icon: Icons.error_outline,
        );
        return;
      }
      player.onPlayerComplete.listen((_) {
        if (mounted && _playingMusic) setState(() => _playingMusic = false);
      });
      await player.play(DeviceFileSource(path));
      if (mounted) setState(() => _playingMusic = true);
    } catch (_) {
      if (mounted) setState(() => _playingMusic = false);
    }
  }

  Future<void> _removeMusic() async {
    await _player?.stop();
    await _service.setMusic();
    if (mounted) setState(() => _playingMusic = false);
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
      builder: (ctx) => const _AddFriendSheet(),
    );
    if (result == null) return;
    await _service.addFriend(
      name: result.name,
      colorIndex: result.colorIndex,
      score: result.score,
    );
    Haptics.light();
  }

  Future<void> _editFriend(ProfileFriend friend) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FriendActionsSheet(friend: friend),
    );
    if (action == 'remove') {
      await _service.removeFriend(friend.id);
      Haptics.light();
    } else if (action == 'score') {
      if (!mounted) return;
      final updated = await showModalBottomSheet<ProfileFriend>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _FriendScoreSheet(friend: friend),
      );
      if (updated != null) await _service.updateFriend(updated);
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
    final name = _service.displayName.isEmpty
        ? Translations.t('profileAnonymous', context, 'Аноним')
        : _service.displayName;
    return _Card(
      child: Column(
        children: [
          const SizedBox(height: Spacing.xs),
          PressScale(
            pressedScale: 0.92,
            child: GestureDetector(
              onTap: _pickAvatar,
              behavior: HitTestBehavior.opaque,
              child: ProfileAvatar(
                index: _service.avatarIndex,
                size: 96,
                glow: true,
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
                  const SizedBox(width: Spacing.xxs),
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
            child: SmoothTyping(
              controller: _nameCtrl,
              style: theme.textTheme.bodyLarge,
              builder: (style) => TextField(
                controller: _nameCtrl,
                style: style,
                magnifierConfiguration: TextMagnifierConfiguration.disabled,
                contextMenuBuilder: minimalContextMenuBuilder,
                textInputAction: TextInputAction.done,
                maxLength: _nameMaxLength,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(_nameMaxLength),
                ],
                onSubmitted: (_) => _saveName(),
                cursorOpacityAnimates: true,
                decoration: _fieldDecoration(
                  theme,
                  hint: Translations.t(
                    'profileNameHint',
                    context,
                    'Как вас звать?',
                  ),
                ),
              ),
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
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _service.online,
        onChanged: (_) => _toggleOnline(),
        title: Text(
          Translations.t(
            'profileOnlineSwitch',
            context,
            'Показывать красный кружок',
          ),
        ),
        subtitle: Text(
          Translations.t(
            'profileOnlineSwitchDesc',
            context,
            'Другие увидят, что вы на связи',
          ),
        ),
      ),
    );
  }

  Widget _musicCard(ThemeData theme) {
    final hasMusic = _service.musicPath != null;
    return _Card(
      title: Translations.t('profileMusic', context, 'Своя музыка'),
      icon: Icons.music_note_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMusic)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PressScale(
                pressedScale: 0.88,
                child: IconButton.filledTonal(
                  onPressed: _toggleMusicPlayback,
                  icon: Icon(
                    _playingMusic ? Icons.pause : Icons.play_arrow_rounded,
                  ),
                ),
              ),
              title: Text(
                _service.musicTitle ??
                    Translations.t('profileMusicTrack', context, 'Мой трек'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                onPressed: _removeMusic,
                icon: const Icon(Icons.delete_outline),
              ),
            )
          else
            Padding(
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
          Align(
            alignment: Alignment.centerLeft,
            child: PressScale(
              pressedScale: 0.94,
              child: FilledButton.tonalIcon(
                onPressed: _pickMusic,
                style: _roundButtonStyle(),
                icon: const Icon(Icons.library_music_outlined),
                label: Text(
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
      title: Translations.t('profileLeaderboard', context, 'Рейтинг друзей'),
      icon: Icons.emoji_events_outlined,
      trailing: IconButton(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        tooltip: Translations.t('profileAddFriend', context, 'Добавить друга'),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _leaderRow(theme, rows[i], rank: i + 1, isMe: rows[i].id == 'me'),
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
    );
  }

  Widget _leaderRow(
    ThemeData theme,
    ProfileFriend f, {
    required int rank,
    required bool isMe,
  }) {
    final cs = theme.colorScheme;
    return InkWell(
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
            ProfileAvatar(index: f.colorIndex, size: 36),
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
            Text(
              '${f.score}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: cs.primary,
                fontWeight: Weights.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventsCard(ThemeData theme) {
    return _Card(
      title: Translations.t('profileEvents', context, 'События keramika.ru'),
      icon: Icons.event_outlined,
      child: Column(
        children: [
          for (final e in _events)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.local_activity_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                  size: 20,
                ),
              ),
              title: Text(e.title),
              subtitle: Text(e.subtitle),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openEvent(e.url),
            ),
        ],
      ),
    );
  }
}

/// Пункт списка событий.
class _KeramikaEvent {
  final String title;
  final String subtitle;
  final String url;
  const _KeramikaEvent({
    required this.title,
    required this.subtitle,
    required this.url,
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

/// Нижний лист выбора аватарки: сетка градиентов, выбранный — с рамкой.
class _AvatarPickerSheet extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onPick;

  const _AvatarPickerSheet({required this.selected, required this.onPick});

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
            const SizedBox(height: Spacing.md),
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
                  return GestureDetector(
                    onTap: () => onPick(i),
                    child: Container(
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
  const _FriendDraft(this.name, this.colorIndex, this.score);
}

/// Добавление друга: имя, аватарка, стартовые очки.
class _AddFriendSheet extends StatefulWidget {
  const _AddFriendSheet();

  @override
  State<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends State<_AddFriendSheet> {
  final _ctrl = TextEditingController();
  int _avatar = 0;
  final _scoreCtrl = TextEditingController(text: '0');

  @override
  void dispose() {
    _ctrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    final score = int.tryParse(_scoreCtrl.text.trim()) ?? 0;
    Navigator.of(context).pop(_FriendDraft(name, _avatar, score));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
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
                Translations.t('profileAddFriend', context, 'Добавить друга'),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: Weights.bold,
                ),
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  ProfileAvatar(index: _avatar, size: 52, glow: true),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: SmoothTyping(
                      controller: _ctrl,
                      style: theme.textTheme.bodyLarge,
                      builder: (style) => TextField(
                        controller: _ctrl,
                        style: style,
                        magnifierConfiguration:
                            TextMagnifierConfiguration.disabled,
                        contextMenuBuilder: minimalContextMenuBuilder,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        cursorOpacityAnimates: true,
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
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.xs),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => setState(() => _avatar = i),
                    child: Container(
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
              const SizedBox(height: Spacing.md),
              SmoothTyping(
                controller: _scoreCtrl,
                style: theme.textTheme.bodyLarge,
                ghosts: false,
                builder: (style) => TextField(
                  controller: _scoreCtrl,
                  style: style,
                  keyboardType: TextInputType.number,
                  magnifierConfiguration: TextMagnifierConfiguration.disabled,
                  contextMenuBuilder: minimalContextMenuBuilder,
                  cursorOpacityAnimates: true,
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
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: double.infinity,
                child: PressScale(
                  pressedScale: 0.96,
                  child: FilledButton.tonal(
                    onPressed: _submit,
                    style: _roundButtonStyle(),
                    child: Text(Translations.t('add', context, 'Добавить')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Действия над другом: изменить очки или удалить.
class _FriendActionsSheet extends StatelessWidget {
  final ProfileFriend friend;
  const _FriendActionsSheet({required this.friend});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
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
                  ProfileAvatar(index: friend.colorIndex, size: 44),
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
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(
                Translations.t('profileFriendSetScore', context, 'Очки'),
              ),
              onTap: () => Navigator.of(context).pop('score'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(Translations.t('delete', context, 'Удалить')),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Изменение очков друга.
class _FriendScoreSheet extends StatefulWidget {
  final ProfileFriend friend;
  const _FriendScoreSheet({required this.friend});

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: Radii.sheetTop,
          ),
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SmoothTyping(
                controller: _ctrl,
                style: theme.textTheme.bodyLarge,
                ghosts: false,
                builder: (style) => TextField(
                  controller: _ctrl,
                  style: style,
                  keyboardType: TextInputType.number,
                  magnifierConfiguration: TextMagnifierConfiguration.disabled,
                  contextMenuBuilder: minimalContextMenuBuilder,
                  cursorOpacityAnimates: true,
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
              const SizedBox(height: Spacing.md),
              SizedBox(
                width: double.infinity,
                child: PressScale(
                  pressedScale: 0.96,
                  child: FilledButton.tonal(
                    onPressed: () {
                      final score = int.tryParse(_ctrl.text.trim()) ?? 0;
                      Navigator.of(
                        context,
                      ).pop(widget.friend.copyWith(score: score));
                    },
                    style: _roundButtonStyle(),
                    child: Text(Translations.t('save', context, 'Сохранить')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
