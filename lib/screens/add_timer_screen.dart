import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_timer.dart';
import '../services/timer_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/rolling_number.dart';
import '../widgets/smooth_keyboard_body.dart';

class AddTimerScreen extends StatefulWidget {
  final AppTimer? existing;
  const AddTimerScreen({super.key, this.existing});

  @override
  State<AddTimerScreen> createState() => _AddTimerScreenState();
}

class _AddTimerScreenState extends State<AddTimerScreen> {
  late int _hours;
  late int _minutes;
  late int _seconds;
  late TextEditingController _labelCtrl;
  late String _soundName;
  late bool _vibrate;
  late List<String> _availableSounds;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final total = widget.existing!.totalSeconds;
      _hours = total ~/ 3600;
      _minutes = (total % 3600) ~/ 60;
      _seconds = total % 60;
      _labelCtrl = TextEditingController(text: widget.existing!.label);
      _soundName = widget.existing!.soundName;
      _vibrate = widget.existing!.vibrate;
    } else {
      _hours = 0;
      _minutes = 5;
      _seconds = 0;
      _labelCtrl = TextEditingController();
      _soundName = 'Default';
      _vibrate = true;
    }
    _availableSounds = List<String>.from(AppTimer.sounds);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  int get _totalSeconds => _hours * 3600 + _minutes * 60 + _seconds;

  void _save() {
    if (_totalSeconds == 0) return;
    final timer = AppTimer(
      id: widget.existing?.id ?? const Uuid().v4(),
      totalSeconds: _totalSeconds,
      label: _labelCtrl.text.trim(),
      soundName: _soundName,
      vibrate: _vibrate,
    );
    Navigator.of(context).pop(timer);
  }

  Future<void> _pickDuration() async {
    int h = _hours, m = _minutes, s = _seconds;
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) {
        int th = h, tm = m, ts = s;
        // Направление последнего шага — «ролик» цифр крутится в ту сторону.
        int thD = 1, tmD = 1, tsD = 1;
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(Translations.t('timerDuration', context)),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _numberPicker(
                    ctx,
                    th,
                    0,
                    23,
                    'h',
                    thD,
                    (v) => setState(() {
                      thD = v > th ? 1 : -1;
                      th = v;
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(':', style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(width: 8),
                  _numberPicker(
                    ctx,
                    tm,
                    0,
                    59,
                    'm',
                    tmD,
                    (v) => setState(() {
                      tmD = v > tm ? 1 : -1;
                      tm = v;
                    }),
                  ),
                  const SizedBox(width: 8),
                  Text(':', style: Theme.of(ctx).textTheme.headlineSmall),
                  const SizedBox(width: 8),
                  _numberPicker(
                    ctx,
                    ts,
                    0,
                    59,
                    's',
                    tsD,
                    (v) => setState(() {
                      tsD = v > ts ? 1 : -1;
                      ts = v;
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(Translations.cancelOf(context)),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, {'h': th, 'm': tm, 's': ts}),
                  child: Text(Translations.okOf(context)),
                ),
              ],
            );
          },
        );
      },
    );
    if (result != null) {
      setState(() {
        _hours = result['h']!;
        _minutes = result['m']!;
        _seconds = result['s']!;
      });
    }
  }

  Widget _numberPicker(
    BuildContext ctx,
    int value,
    int min,
    int max,
    String suffix,
    int delta,
    ValueChanged<int> onChanged,
  ) {
    final theme = Theme.of(ctx);
    return SizedBox(
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HoldStepper(
            icon: Icons.keyboard_arrow_up,
            iconSize: 20,
            color: value < max
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outlineVariant,
            onStep: () {
              if (value < max) onChanged(value + 1);
            },
          ),
          RollingNumber(
            value: '${value.toString().padLeft(2, '0')}$suffix',
            delta: delta,
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            style: theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          HoldStepper(
            icon: Icons.keyboard_arrow_down,
            iconSize: 20,
            color: value > min
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.outlineVariant,
            onStep: () {
              if (value > min) onChanged(value - 1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSoundRow(BuildContext context, String s) {
    // RadioListTile's `groupValue`/`onChanged` were deprecated in newer Flutter
    // in favor of `RadioGroup<T>`. We stick with the legacy form because the
    // project's flutter SDK may not yet ship RadioGroup; the deprecation is
    // silenced inline.
    // ignore: deprecated_member_use
    final tile = RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(s),
      value: s,
      // ignore: deprecated_member_use
      groupValue: _soundName,
      // ignore: deprecated_member_use
      onChanged: (v) {
        if (v == null) return;
        setState(() => _soundName = v);
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    if (s == 'Default') return tile;
    return Dismissible(
      key: ValueKey('sound_dismiss_$s'),
      movementDuration: const Duration(milliseconds: 320),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: const BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        setState(() {
          _availableSounds.remove(s);
          if (_soundName == s) {
            _soundName = _availableSounds.isNotEmpty
                ? _availableSounds.first
                : 'Default';
          }
        });
        // Заменяем удалённый звук на Default в существующих таймерах
        // Используем singleton напрямую — load() не нужен, данные уже в памяти
        for (final t in TimerService().timers) {
          if (t.soundName == s) {
            TimerService().update(t.copyWith(soundName: 'Default'));
          }
        }
      },
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing
              ? Translations.t('editTimer', context)
              : Translations.t('newTimer', context),
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
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      AppTimer.formatDuration(_totalSeconds),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.tonal(
                      onPressed: _pickDuration,
                      child: Text(Translations.t('timerDuration', context)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translations.t('timerLabel', context),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      magnifierConfiguration:
                          TextMagnifierConfiguration.disabled,
                      controller: _labelCtrl,
                      contextMenuBuilder: minimalContextMenuBuilder,
                      maxLength: 20,
                      buildCounter: smoothCharCounterBuilder,
                      decoration: InputDecoration(
                        hintText: AppTimer.formatDuration(_totalSeconds),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 4,
                        top: 4,
                        bottom: 4,
                      ),
                      child: Text(
                        Translations.soundOf(context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    for (final s in _availableSounds)
                      _buildSoundRow(context, s),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(Translations.vibrateOf(context)),
                leading: Icon(
                  _vibrate ? Icons.vibration : Icons.music_note,
                  color: theme.colorScheme.primary,
                ),
                onTap: () => setState(() => _vibrate = !_vibrate),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                trailing: VolumetricSwitch(
                  value: _vibrate,
                  onChanged: (v) => setState(() => _vibrate = v),
                  activeColor: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _totalSeconds > 0 ? _save : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(Translations.saveOf(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
