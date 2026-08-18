import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/habit.dart';
import '../l10n/translations.dart';
import '../services/notification_service_instance.dart';
import '../utils/context_menu.dart';
import '../utils/snackbar.dart';
import '../utils/icon_map.dart';
import '../widgets/icon_picker_sheet.dart';
import '../widgets/manual_time_dialog.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/smooth_keyboard_body.dart';

class AddHabitScreen extends StatefulWidget {
  final Habit? existing;
  const AddHabitScreen({super.key, this.existing});

  @override
  State<AddHabitScreen> createState() => _AddHabitScreenState();
}

class _AddHabitScreenState extends State<AddHabitScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _statusCtrl;
  late int _iconCodePoint;
  late List<int> _activeDays;
  late String _habitType;

  /// Напоминание «Вспомнить всё»: null — выключено.
  TimeOfDay? _reminderTime;
  /// Текст напоминания (до 60 символов).
  String? _reminderText;
  final _reminderTextCtrl = TextEditingController();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl = TextEditingController(text: widget.existing!.name);
      _notesCtrl = TextEditingController(text: widget.existing!.notes);
      _statusCtrl = TextEditingController(text: widget.existing!.status);
      _iconCodePoint = widget.existing!.iconCodePoint;
      _activeDays = List.from(widget.existing!.activeDays);
      _habitType = widget.existing!.type;
      _reminderTime = _parseReminder(widget.existing!.reminderTime);
      _reminderText = widget.existing!.reminderText;
      if (_reminderText != null) _reminderTextCtrl.text = _reminderText!;
      _editing = true;
    } else {
      _nameCtrl = TextEditingController();
      _notesCtrl = TextEditingController();
      _statusCtrl = TextEditingController();
      // По умолчанию — цветок (spa_outlined), чтобы новая привычка
      // сразу выглядела «живой», а не сноубордом.
      _iconCodePoint = 62395;
      _activeDays = [];
      _habitType = 'good';
      _reminderTime = null;
    }
  }

  static TimeOfDay? _parseReminder(String? value) {
    if (value == null || !value.contains(':')) return null;
    final parts = value.split(':');
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// Включение тумблера «Вспомнить всё»: сразу красиво просим выбрать
  /// время; если пользователь закрыл диалог — ставим разумный дефолт 08:00.
  /// Если мастер-тумблер уведомлений выключен, планировщик молча пропускал
  /// напоминания — поэтому при включении напоминания включаем уведомления
  /// (заодно запрашиваем OS-разрешение) и честно предупреждаем, если
  /// разрешение так и не дали.
  Future<void> _enableReminder() async {
    // Уведомления выключены — включаем их: пользователь явно хочет
    // напоминание, это его намерение, а не случайный тап.
    if (!notificationService.enabled) {
      await notificationService.setEnabled(true);
      if (!mounted) return;
      if (!notificationService.enabled) {
        showBeautifulSnackBar(
          context,
          message: Translations.t(
            'remindNeedNotifs',
            context,
            'Включи уведомления, чтобы «Вспомнить всё» работало',
          ),
          icon: Icons.notifications_off,
          iconColor: Colors.orange,
        );
      }
    }
    // Клавиатура не должна «оставаться» после выбора времени: снимаем
    // фокус с поля имени, иначе по возврату из пикера она вылезает снова.
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showManualTimePicker(
      context,
      initial: _reminderTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (!mounted) return;
    setState(() {
      _reminderTime = picked ?? const TimeOfDay(hour: 8, minute: 0);
    });
  }

  void _disableReminder() => setState(() => _reminderTime = null);

  void _toggleDay(int day) {
    setState(() {
      if (_activeDays.contains(day)) {
        _activeDays.remove(day);
      } else {
        _activeDays.add(day);
        _activeDays.sort();
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    _statusCtrl.dispose();
    super.dispose();
  }

  void _pickIcon() async {
    // Снимаем фокус с поля ввода ДО открытия листа — иначе Android
    // считает, что нужно показать клавиатуру под низом листа, и она
    // подскакивает при закрытии.
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await IconPickerSheet.show(context, _iconCodePoint);
    if (result != null) setState(() => _iconCodePoint = result);
  }

  void _showNotesDialog() {
    final ctrl = TextEditingController(text: _statusCtrl.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.lightbulb, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            Text(Translations.t('habitStatusTitle', context)),
          ],
        ),
        content: TextField(
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
          controller: ctrl,
          contextMenuBuilder: minimalContextMenuBuilder,
          maxLength: 50,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: Translations.t('habitStatusHint', context),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.cancelOf(context)),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _statusCtrl.text = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(Translations.saveOf(context)),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final habit = Habit(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: name,
      notes: _notesCtrl.text.trim(),
      status: _statusCtrl.text.trim(),
      streak: widget.existing?.streak ?? 0,
      doneToday: widget.existing?.doneToday ?? false,
      iconCodePoint: _iconCodePoint,
      activeDays: _activeDays,
      pinned: widget.existing?.pinned ?? false,
      lastDoneDate: widget.existing?.lastDoneDate,
      createdAt: widget.existing?.createdAt,
      type: _habitType,
      reminderTime: _reminderTime == null
          ? null
          : '${_reminderTime!.hour.toString().padLeft(2, '0')}:'
                '${_reminderTime!.minute.toString().padLeft(2, '0')}',
      reminderText: _reminderText?.trim().isEmpty == true ? null : _reminderText?.trim(),
    );
    Navigator.of(context).pop(habit);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final name = _nameCtrl.text.trim();
        if (name.isNotEmpty) {
          _save();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _editing
                ? Translations.t('editHabit', context)
                : Translations.t('newHabit', context),
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
              Center(
                child: GestureDetector(
                  onTap: _pickIcon,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(opacity: animation, child: child),
                      ),
                      child: Icon(
                        iconDataForCodePoint(_iconCodePoint),
                        key: ValueKey(_iconCodePoint),
                        size: 32,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: _pickIcon,
                    icon: const Icon(Icons.touch_app, size: 16),
                    label: Text(Translations.t('changeIcon', context)),
                  ),
                  // Для вредного типа привычки скрываем оба варианта «заметок»:
                  // и лампочку-статус, и большое поле «заметки» ниже.
                  if (_habitType == 'good') ...[
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: _showNotesDialog,
                      icon: Icon(
                        _statusCtrl.text.isNotEmpty
                            ? Icons.lightbulb
                            : Icons.lightbulb_outline,
                        size: 20,
                        color: _statusCtrl.text.isNotEmpty
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: Translations.t('habitNotesBtn', context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(
                        Translations.t('habitType', context),
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: Text(Translations.t('habitTypeGood', context)),
                        selected: _habitType == 'good',
                        selectedColor: theme.colorScheme.primaryContainer,
                        checkmarkColor: theme.colorScheme.onPrimaryContainer,
                        labelStyle: TextStyle(
                          color: _habitType == 'good'
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: _editing
                            ? null
                            : (_) => setState(() => _habitType = 'good'),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(Translations.t('habitTypeBad', context)),
                        selected: _habitType == 'bad',
                        selectedColor: theme.colorScheme.errorContainer,
                        checkmarkColor: theme.colorScheme.onErrorContainer,
                        labelStyle: TextStyle(
                          color: _habitType == 'bad'
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        onSelected: _editing
                            ? null
                            : (_) => setState(() => _habitType = 'bad'),
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
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    controller: _nameCtrl,
                    contextMenuBuilder: minimalContextMenuBuilder,
                    maxLength: 150,
                    maxLines: 5,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: Translations.t('habitName', context),
                      prefixIcon: const Icon(Icons.edit_outlined),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Заметки и статус скрыты для вредного типа — но переключение
              // между типами теперь плавное: блок заметок появляется и
              // исчезает с fade+size анимацией, чтобы пользователь видел
              // чёткий визуальный отклик при смене «полезная ↔ вредная».
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
                child: _habitType == 'good'
                    ? Column(
                        key: const ValueKey('good_notes'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: TextField(
                                magnifierConfiguration:
                                    TextMagnifierConfiguration.disabled,
                                controller: _notesCtrl,
                                contextMenuBuilder: minimalContextMenuBuilder,
                                maxLength: 500,
                                minLines: 5,
                                maxLines: 12,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                decoration: InputDecoration(
                                  labelText: Translations.t('notes', context),
                                  prefixIcon: const Icon(Icons.notes_outlined),
                                  border: const OutlineInputBorder(),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      )
                    : const SizedBox.shrink(
                        key: const ValueKey('bad_no_notes'),
                      ),
              ),
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.t('habitDays', context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Translations.t('habitDaysHint', context),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(
                              () => _activeDays = [1, 2, 3, 4, 5, 6, 7],
                            ),
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                            ),
                            label: Text(Translations.t('everyDay', context)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () => setState(() => _activeDays = []),
                            icon: const Icon(Icons.block, size: 18),
                            label: Text(Translations.t('clear', context)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Плавные чипы дней: каждый анимируется (цвет,
                      // граница, галочка) при выборе. Кнопки «Каждый день»/
                      // «Очистить» меняют список за один setState, но чипы
                      // «перетекают» плавно, а не прыгают разом.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(7, (i) {
                          final day = i + 1;
                          final selected = _activeDays.contains(day);
                          return _DayChip(
                            day: day,
                            label: Translations.dayNames(context)[i],
                            selected: selected,
                            onTap: () => _toggleDay(day),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // === Вспомнить всё: напоминание о привычке ===
              // Лёгкая отдача при нажатии, как у карточек привычек.
              SmoothHover(
                hoverScale: 1.01,
                child: Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Бейдж с колокольчиком: пустой / активный.
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary.withValues(
                                  alpha: _reminderTime == null ? 0.10 : 0.16,
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                transitionBuilder: (child, animation) =>
                                    ScaleTransition(
                                      scale: animation,
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                child: Icon(
                                  _reminderTime == null
                                      ? Icons.notifications_none
                                      : Icons.notifications_active,
                                  key: ValueKey(_reminderTime != null),
                                  color: theme.colorScheme.primary,
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Translations.t(
                                      'remindAll',
                                      context,
                                      'Вспомнить всё',
                                    ),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _reminderTime == null
                                        ? Translations.t(
                                            'remindOffHint',
                                            context,
                                            'Напомнит о привычке в выбранное время',
                                          )
                                        : Translations.t(
                                            'remindOnHint',
                                            context,
                                            'Каждый день или по выбранным дням',
                                          ),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            VolumetricSwitch(
                              value: _reminderTime != null,
                              activeColor: theme.colorScheme.primary,
                              onChanged: (v) =>
                                  v ? _enableReminder() : _disableReminder(),
                            ),
                          ],
                        ),
                        // Плавное появление плашки времени при включении.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _reminderTime == null
                              ? const SizedBox(width: double.infinity)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 14),
                                    Material(
                                      color: theme.colorScheme.primaryContainer
                                          .withValues(alpha: 0.45),
                                      borderRadius: BorderRadius.circular(16),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: _enableReminder,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.schedule,
                                                size: 18,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  Translations.t(
                                                    'remindAt',
                                                    context,
                                                    'Напоминать в',
                                                  ),
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium,
                                                ),
                                              ),
                                              Text(
                                                '${_reminderTime!.hour.toString().padLeft(2, '0')}:'
                                                '${_reminderTime!.minute.toString().padLeft(2, '0')}',
                                                style: theme
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: theme
                                                          .colorScheme
                                                          .primary,
                                                      fontFeatures: const [
                                                        FontFeature.tabularFigures(),
                                                      ],
                                                    ),
                                              ),
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.chevron_right,
                                                size: 20,
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        // Текст напоминания (до 60 символов) — появляется плавно.
                        AnimatedSize(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _reminderTime == null
                              ? const SizedBox(width: double.infinity)
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 10),
                                    Material(
                                      color: theme.colorScheme.surfaceContainerHigh
                                          .withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.edit_note_rounded,
                                                  size: 18,
                                                  color: theme.colorScheme.primary,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    Translations.t(
                                                      "remindCustomText",
                                                      context,
                                                      "Текст напоминания (до 60 симв.)",
                                                    ),
                                                    style: theme.textTheme.bodySmall
                                                        ?.copyWith(
                                                      color: theme.colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            TextField(
                                              controller: _reminderTextCtrl,
                                              maxLength: 60,
                                              maxLines: 1,
                                              decoration: InputDecoration(
                                                hintText: Translations.t(
                                                  "remindCustomHint",
                                                  context,
                                                  "Например: Пора пить воду",
                                                ),
                                                hintStyle: theme.textTheme.bodyMedium
                                                    ?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant
                                                      .withValues(alpha: 0.5),
                                                ),
                                                border: InputBorder.none,
                                                isDense: true,
                                                contentPadding: EdgeInsets.zero,
                                                counterStyle: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: theme.colorScheme.onSurfaceVariant
                                                      .withValues(alpha: 0.5),
                                                ),
                                              ),
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                              onChanged: (v) => setState(
                                                  () => _reminderText = v.isEmpty ? null : v),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
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

/// Плавный чип дня недели: цвет/граница/галочка анимируются (240 мс),
/// вместо резкого переключения системного FilterChip.
class _DayChip extends StatelessWidget {
  final int day;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({
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
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(
                    scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          key: ValueKey('day_on_$day'),
                          size: 14,
                          color: cs.onPrimary,
                        )
                      : const SizedBox(
                          key: ValueKey('day_off'),
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
