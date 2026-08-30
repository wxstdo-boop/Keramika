import 'dart:io';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../models/alarm.dart';
import '../models/wake_task.dart';
import '../services/alarm_service.dart';
import '../services/prefs.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';
import '../widgets/stagger_in.dart';
import '../widgets/sliding_picker.dart';
import '../widgets/manual_time_dialog.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_keyboard_body.dart';

class AddAlarmScreen extends StatefulWidget {
  final Alarm? existing;
  const AddAlarmScreen({super.key, this.existing});

  @override
  State<AddAlarmScreen> createState() => _AddAlarmScreenState();
}

class _AddAlarmScreenState extends State<AddAlarmScreen> {
  late TimeOfDay _time;
  late List<int> _repeatDays;
  late TextEditingController _labelCtrl;
  late WakeUpTask _taskType;
  late bool _vibrate;
  late String _soundName;
  String? _customSoundPath;
  bool _editing = false;
  AudioPlayer? _player;
  String? _playingSound;
  late List<String> _availableSounds;

  // Удалённые звуки запоминаем, чтобы они не возвращались при создании новых
  // будильников. Дополнительно персистим в globalPrefs, иначе после
  // перезапуска приложения Set теряется и звуки возвращаются снова.
  static final Set<String> deletedSounds = {};

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _time = widget.existing!.time;
      _repeatDays = List.from(widget.existing!.repeatDays);
      _labelCtrl = TextEditingController(text: widget.existing!.label);
      _taskType = widget.existing!.taskType;
      _vibrate = widget.existing!.vibrate;
      _soundName = widget.existing!.soundName;
      _customSoundPath = widget.existing!.customSoundPath;
      _editing = true;
    } else {
      _time = TimeOfDay(
        hour: DateTime.now().hour,
        minute: DateTime.now().minute,
      );
      _repeatDays = [];
      _labelCtrl = TextEditingController();
      _taskType = WakeUpTask.none;
      _vibrate = true;
      _soundName = 'Default';
    }

    // ВАЖНО: при редактировании существующего будильника НЕ перезагружаем
    // список из Alarm.sounds. Иначе удалённые звуки вернутся.
    //
    // Подтягиваем удалённые звуки из prefs — только если локальный кэш
    // пустой (это первый State в текущем процессе). Иначе могли бы
    // перезатереть более свежий список.
    if (deletedSounds.isEmpty) {
      final stored = globalPrefs.getStringList('deleted_alarm_sounds');
      if (stored != null && stored.isNotEmpty) {
        deletedSounds.addAll(stored);
      }
    }
    if (widget.existing != null) {
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
    } else {
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  // Один переиспользуемый плеер на весь экран: создание/уничтожение
  // AudioPlayer на каждый тап давало «щелчки»/шум на слабых устройствах.
  // Остановка — ТОЛЬКО через плавное затухание громкости (иначе stop()
  // режет звук резко, с «щелчком»/шумом).
  Future<void> _fadeOutStop(AudioPlayer? p) async {
    if (p == null) return;
    try {
      for (var i = 10; i > 0; i--) {
        await p.setVolume(i / 10);
        await Future.delayed(const Duration(milliseconds: 18));
      }
      await p.stop();
      await p.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> _previewSound(String name) async {
    // Остановка: иконка и состояние меняются МГНОВЕННО, звук плавно
    // затухает в фоне — чтобы кнопка не «лагала» на слабых устройствах.
    if (_playingSound == name) {
      _playingSound = null;
      if (mounted) setState(() {});
      _fadeOutStop(_player);
      return;
    }
    _playingSound = name;
    if (mounted) setState(() {});
    try {
      final player = _player ??= AudioPlayer();
      // Слушатель вешаем ОДИН раз за жизнь плеера; короткий звук в 1с
      // иначе можно не поймать при быстрой смене.
      player.onPlayerComplete.listen((_) {
        if (mounted && _playingSound != null) {
          setState(() => _playingSound = null);
        }
      });
      // Мягкий сброс перед новым звуком — без щелчка.
      await _fadeOutStop(player);
      if (name == 'Custom' && _customSoundPath != null) {
        await player.play(DeviceFileSource(_customSoundPath!));
      } else {
        final source = _builtinSource(name);
        if (source != null) {
          await player.play(source);
        }
      }
    } catch (_) {
      if (mounted && _playingSound == name) {
        setState(() => _playingSound = null);
      }
    }
  }

  /// Удаление звука (зажатие пункта в карусели): свой файл — сбрасываем,
  /// встроенный — прячем навсегда (как кнопкой удаления).
  void _deleteSound(String name) {
    // Свой звук без файла — удалять нечего: зажатие не делает ничего.
    if (name == 'Custom' && _customSoundPath == null) return;
    // Сначала плавно останавливаем прослушивание удаляемого звука, чтобы
    // старый плеер не продолжал играть поверх уже обновлённого списка.
    if (_playingSound == name) {
      _playingSound = null;
      _fadeOutStop(_player);
    }
    if (name == 'Custom') {
      setState(() {
        _customSoundPath = null;
        // Оставляем карточку «Свой» выбранной даже после удаления файла:
        // следующий файл можно добавить в тот же слот без скачка на Default.
        _soundName = 'Custom';
        if (!_availableSounds.contains('Custom')) {
          _availableSounds.add('Custom');
        }
      });
      return;
    }
    final removed = name;
    // Будильники, у которых стоял этот звук, — запоминаем для отката.
    final affected = AlarmService().alarms
        .where((a) => a.soundName == removed)
        .toList();
    setState(() {
      _availableSounds.remove(removed);
      deletedSounds.add(removed);
      _soundName = _availableSounds.isNotEmpty
          ? _availableSounds.first
          : 'Default';
    });
    globalPrefs.setStringList('deleted_alarm_sounds', deletedSounds.toList());
    for (final a in affected) {
      AlarmService().update(
        a.copyWith(soundName: 'Default', customSoundPath: null),
      );
    }
    // Плавный снекбар с «Отменить» — случайно удалённый звук можно вернуть.
    showBeautifulSnackBar(
      context,
      message: Translations.t('soundDeleted', context, 'Sound deleted'),
      icon: Icons.music_off_outlined,
      iconColor: Colors.orange,
      duration: const Duration(seconds: 4),
      actionLabel: Translations.t('undo', context, 'Undo'),
      onAction: () => _restoreSound(removed, affected),
    );
  }

  /// Откат удаления звука (кнопка «Отменить»): звук снова в списке,
  /// будильники со старым звуком возвращены.
  void _restoreSound(String name, List<Alarm> affected) {
    setState(() {
      deletedSounds.remove(name);
      _availableSounds = Alarm.sounds
          .where((s) => !deletedSounds.contains(s))
          .toList();
      if (_availableSounds.contains(name)) _soundName = name;
    });
    globalPrefs.setStringList('deleted_alarm_sounds', deletedSounds.toList());
    for (final a in affected) {
      AlarmService().update(a);
    }
  }

  Source? _builtinSource(String name) {
    switch (name) {
      case 'Default':
        return AssetSource('sounds/default.wav');
      case 'Gentle':
        return AssetSource('sounds/gentle.wav');
      case 'Classic':
        return AssetSource('sounds/classic.wav');
      case 'Digital':
        return AssetSource('sounds/digital.wav');
      case 'Nature':
        return AssetSource('sounds/nature.wav');
      default:
        return null;
    }
  }

  Future<void> _pickCustomSound() async {
    // Системный пикер на время открытия — отключаем PIN-блюр, иначе
    // экран «сереет» до появления выбора файлов.
    systemUiActive = true;
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    systemUiActive = false;
    if (result != null && result.files.single.path != null) {
      setState(() {
        _customSoundPath = result.files.single.path;
        _soundName = 'Custom';
      });
    }
  }

  void _renameCustomSound() {
    if (_customSoundPath == null) return;
    final path = _customSoundPath!;
    final ctrl = TextEditingController(text: path.split('/').last);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('renameSound', context, 'Rename sound')),
        content: TextField(
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
          controller: ctrl,
          contextMenuBuilder: minimalContextMenuBuilder,
          maxLength: 20,
          buildCounter: smoothCharCounterBuilder,
          decoration: InputDecoration(
            labelText: Translations.t('soundName', context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.cancelOf(context)),
          ),
          TextButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty || newName.length > 20) return;
              final directory = await getApplicationDocumentsDirectory();
              final soundsDir = Directory('${directory.path}/sounds');
              try {
                // Папка может не существовать — без неё rename всегда падал
                // в «фолбэк» (имя не менялось, английский снекбар).
                await soundsDir.create(recursive: true);
                final oldFile = File(path);
                final newPath = '${soundsDir.path}/$newName.wav';
                if (oldFile.existsSync() &&
                    oldFile.parent.path == soundsDir.path) {
                  await oldFile.rename(newPath);
                } else if (oldFile.existsSync()) {
                  // Файл лежит вне документов (Downloads и т.п.) — копируем
                  // в документы приложения, чтобы имя реально сохранилось.
                  await oldFile.copy(newPath);
                }
                setState(() {
                  _customSoundPath = newPath;
                  _soundName = 'Custom';
                });
                Navigator.pop(ctx);
                showBeautifulSnackBar(
                  context,
                  message: Translations.t(
                    'soundRenamed',
                    context,
                    'Sound renamed',
                  ),
                );
              } catch (e) {
                Navigator.pop(ctx);
                showBeautifulSnackBar(
                  context,
                  message: Translations.t(
                    'soundRenameFailed',
                    context,
                    'Could not rename sound',
                  ),
                );
              }
            },
            child: Text(Translations.saveOf(context)),
          ),
        ],
      ),
    );
  }

  void _pickTime() async {
    // Свой диалог ручного времени: у штатного showTimePicker в режиме
    // клавиатуры лупа/магнифай не отключается, поэтому время вводим
    // через собственные TextField'ы без выделения.
    final picked = await showManualTimePicker(context, initial: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _toggleDay(int day) {
    setState(() {
      if (_repeatDays.contains(day)) {
        _repeatDays.remove(day);
      } else {
        _repeatDays.add(day);
        _repeatDays.sort();
      }
    });
  }

  void _save() {
    final alarm = Alarm(
      id: widget.existing?.id ?? const Uuid().v4(),
      time: _time,
      repeatDays: _repeatDays,
      label: _labelCtrl.text.trim(),
      taskType: _taskType,
      vibrate: _vibrate,
      soundName: _soundName,
      customSoundPath: _customSoundPath,
    );
    Navigator.of(context).pop(alarm);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayNames = Translations.dayNames(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing
                ? Translations.editAlarmOf(context)
                : Translations.newAlarmOf(context),
          ),
          centerTitle: true,
          actions: [
            TextButton(
              onPressed: _save,
              child: Text(Translations.saveOf(context)),
            ),
          ],
        ),
        resizeToAvoidBottomInset: false,
        body: SmoothKeyboardBody(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              StaggerIn(
                index: 0,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.access_time),
                    title: Text(
                      _time.format(context),
                      style: theme.textTheme.headlineMedium,
                    ),
                    subtitle: Text(Translations.tapToChangeOf(context)),
                    onTap: _pickTime,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 1,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.repeatOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(7, (i) {
                            final day = i + 1;
                            final selected = _repeatDays.contains(day);
                            return _AlarmDayChip(
                              day: day,
                              label: dayNames[i],
                              selected: selected,
                              onTap: () => _toggleDay(day),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 2,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.wakeUpTaskOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...WakeUpTask.values.map((task) {
                          final selected = _taskType == task;
                          IconData icon;
                          switch (task) {
                            case WakeUpTask.none:
                              icon = Icons.notifications_off_outlined;
                            case WakeUpTask.math:
                              icon = Icons.calculate_outlined;
                            case WakeUpTask.pattern:
                              icon = Icons.touch_app_outlined;
                            case WakeUpTask.memory:
                              icon = Icons.psychology_outlined;
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() => _taskType = task),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color: selected
                                      ? theme.colorScheme.primaryContainer
                                            .withValues(alpha: 0.45)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outlineVariant
                                              .withValues(alpha: 0.35),
                                    width: selected ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(icon, size: 20),
                                    const SizedBox(width: 12),
                                    Text(Translations.t(task.key, context)),
                                    const Spacer(),
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                            scale: animation,
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          ),
                                      child: selected
                                          ? Icon(
                                              Icons.check_circle,
                                              key: ValueKey(
                                                'wake_selected_${task.key}',
                                              ),
                                              size: 20,
                                              color: theme.colorScheme.primary,
                                            )
                                          : const SizedBox(
                                              key: ValueKey('wake_unselected'),
                                              width: 20,
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 3,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      magnifierConfiguration:
                          TextMagnifierConfiguration.disabled,
                      controller: _labelCtrl,
                      contextMenuBuilder: minimalContextMenuBuilder,
                      maxLength: 100,
                      maxLines: 2,
                      buildCounter: smoothCharCounterBuilder,
                      decoration: InputDecoration(
                        labelText: Translations.labelOf(context),
                        prefixIcon: const Icon(Icons.label_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 4,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: ListTile(
                    title: Text(Translations.vibrateOf(context)),
                    leading: const Icon(Icons.vibration),
                    onTap: () => setState(() => _vibrate = !_vibrate),
                    trailing: VolumetricSwitch(
                      value: _vibrate,
                      onChanged: (v) => setState(() => _vibrate = v),
                      activeColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              StaggerIn(
                index: 5,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Translations.soundOf(context),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 520),
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                                alignment: Alignment.center,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(
                                    begin: 0.96,
                                    end: 1.0,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: SlidingPicker<String>(
                            key: ValueKey(_availableSounds.join('|')),
                            items: _availableSounds,
                            selected: _soundName,
                            height: 84,
                            onChanged: (s) => setState(() => _soundName = s),
                            itemBuilder: (context, s, selected) {
                              final isCustom = s == 'Custom';
                              final displayName =
                                  isCustom && _customSoundPath != null
                                  ? _customSoundPath!
                                        .split('/')
                                        .last
                                        .replaceAll('.wav', '')
                                  : (isCustom
                                        ? Translations.t('customSound', context)
                                        : s);
                              return GestureDetector(
                                onTap: () => setState(() => _soundName = s),
                                // Зажатие звука — удаление (свой файл или встроенный).
                                onLongPress: () => _deleteSound(s),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 260),
                                  curve: Curves.easeOutCubic,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: selected
                                        ? theme.colorScheme.primaryContainer
                                              .withValues(alpha: 0.55)
                                        : theme
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.35),
                                    border: Border.all(
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.outlineVariant
                                                .withValues(alpha: 0.6),
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isCustom
                                            ? Icons.folder_open
                                            : Icons.music_note_outlined,
                                        size: 20,
                                        color: selected
                                            ? theme.colorScheme.primary
                                            : theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: selected
                                              ? theme.colorScheme.primary
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Управление текущим звуком: прослушать / загрузить /
                        // переименовать. Кнопки переключаются плавно, значок
                        // проигрывания тает/появляется мягко.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.center,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.9,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: Row(
                              key: ValueKey(
                                '$_soundName|${_customSoundPath != null}|${_playingSound == _soundName}',
                              ),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 250),
                                  transitionBuilder: (child, animation) =>
                                      FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: 0.75,
                                            end: 1.0,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                  child: IconButton(
                                    key: ValueKey(_playingSound == _soundName),
                                    tooltip: Translations.soundOf(context),
                                    icon: Icon(
                                      _playingSound == _soundName
                                          ? Icons.stop_circle
                                          : Icons.play_circle_outline,
                                      color: Colors.pink[300],
                                      size: 30,
                                    ),
                                    onPressed: () => _previewSound(_soundName),
                                  ),
                                ),
                                if (_soundName == 'Custom')
                                  IconButton(
                                    tooltip: Translations.t(
                                      'customSound',
                                      context,
                                    ),
                                    icon: Icon(
                                      Icons.upload_file,
                                      color: Colors.pink[300],
                                      size: 26,
                                    ),
                                    onPressed: _pickCustomSound,
                                  ),
                                if (_soundName == 'Custom' &&
                                    _customSoundPath != null)
                                  IconButton(
                                    tooltip: Translations.t(
                                      'renameSound',
                                      context,
                                      'Rename',
                                    ),
                                    icon: Icon(
                                      Icons.drive_file_rename_outline,
                                      color: Colors.pink[300],
                                      size: 24,
                                    ),
                                    onPressed: _renameCustomSound,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плавный чип дня недели будильника — ровно как в повторении привычки:
/// цвет/граница/галочка анимируются (240 мс) вместо резкого FilterChip.
class _AlarmDayChip extends StatelessWidget {
  final int day;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AlarmDayChip({
    required this.day,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: selected
            ? cs.primary
            : cs.surfaceContainerHigh.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          key: ValueKey('alarm_day_on_$day'),
                          size: 14,
                          color: cs.onPrimary,
                        )
                      : const SizedBox(
                          key: ValueKey('alarm_day_off'),
                          width: 14,
                        ),
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
