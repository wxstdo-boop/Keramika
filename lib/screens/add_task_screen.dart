import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/icon_map.dart';
import '../widgets/icon_picker_sheet.dart';
import '../utils/snackbar.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../services/haptics.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? existing;
  const AddTaskScreen({super.key, this.existing});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  late TextEditingController _titleCtrl;
  late int _iconCodePoint;
  late String _category;
  late int _priority;
  final TaskService _taskSvc = TaskService();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _titleCtrl = TextEditingController(text: widget.existing!.title);
      _iconCodePoint = widget.existing!.iconCodePoint;
      _category = widget.existing!.category;
      _priority = widget.existing!.priority;
      _editing = true;
    } else {
      _titleCtrl = TextEditingController();
      _iconCodePoint = 58830;
      _category = '';
      _priority = 0;
    }
    _taskSvc.load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
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

  Future<void> _createCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('newCategory', context)),
        content: TextField(
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
          controller: ctrl,
          contextMenuBuilder: minimalContextMenuBuilder,
          decoration: InputDecoration(
            labelText: Translations.t('categoryName', context),
            border: const OutlineInputBorder(),
          ),
          inputFormatters: [LengthLimitingTextInputFormatter(15)],
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.cancelOf(context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(Translations.t('createCategory', context)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      if (_taskSvc.categories.length >= 15) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('maxCat', context),
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.orange,
        );
      } else {
        final added = await _taskSvc.addCategory(name);
        if (!mounted) return;
        if (added) {
          setState(() => _category = name);
        } else {
          final message = Translations.t('categoryExists', context);
          showBeautifulSnackBar(
            context,
            message: message,
            icon: Icons.warning_amber_outlined,
            iconColor: Colors.orange,
          );
        }
      }
    }
  }

  Future<void> _renameCategory(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('category', context)),
        content: TextField(
          magnifierConfiguration: TextMagnifierConfiguration.disabled,
          controller: ctrl,
          contextMenuBuilder: minimalContextMenuBuilder,
          maxLength: 15,
          decoration: InputDecoration(
            labelText: Translations.t('categoryName', context),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.cancelOf(context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(Translations.saveOf(context)),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && mounted) {
      final renamed = await _taskSvc.renameCategory(oldName, newName);
      if (!mounted) return;
      if (renamed) {
        setState(() => _category = newName);
      } else {
        showBeautifulSnackBar(
          context,
          message: Translations.t('categoryExists', context),
          icon: Icons.warning_amber_outlined,
          iconColor: Colors.orange,
        );
      }
    }
  }

  /// Плавный «чип» категории: выбор анимируется цветом/масштабом,
  /// а не «прыгает» как выпадающий список.
  Widget _categoryChip(BuildContext context, String value) {
    final theme = Theme.of(context);
    final selected = _category == value;
    final label = value.isEmpty ? Translations.uncategorizedOf(context) : value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          setState(() => _category = value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              label,
              key: ValueKey('chip_$label'),
              style: TextStyle(
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Кнопка «+ Новая категория» в ряду чипов.
  Widget _newCategoryChip(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _createCategory,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  Translations.t('newCategory', context),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final task = Task(
      id: widget.existing?.id ?? const Uuid().v4(),
      title: title,
      done: widget.existing?.done ?? false,
      iconCodePoint: _iconCodePoint,
      category: _category,
      priority: _priority,
      note: widget.existing?.note ?? '',
      createdAt: widget.existing?.createdAt,
    );
    Navigator.of(context).pop(task);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing
              ? Translations.t('editTask', context)
              : Translations.t('newTask', context),
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
              child: Center(
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
            ),
            const SizedBox(height: 4),
            StaggerIn(
              index: 1,
              child: Center(
                child: TextButton.icon(
                  onPressed: _pickIcon,
                  icon: const Icon(Icons.touch_app, size: 16),
                  label: Text(Translations.t('changeIcon', context)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            StaggerIn(
              index: 2,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: TextField(
                    magnifierConfiguration: TextMagnifierConfiguration.disabled,
                    controller: _titleCtrl,
                    contextMenuBuilder: minimalContextMenuBuilder,
                    maxLength: 250,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: Translations.t('taskTitle', context),
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
            ),
            const SizedBox(height: 12),
            StaggerIn(
              index: 3,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            Translations.categoryOf(context),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const Spacer(),
                          if (_category.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: Translations.t('category', context),
                              onPressed: () => _renameCategory(_category),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        height: 44,
                        child: ListenableBuilder(
                          listenable: _taskSvc,
                          builder: (ctx, _) {
                            final cats = <String>['', ..._taskSvc.categories];
                            return ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final c in cats) _categoryChip(ctx, c),
                                if (_taskSvc.categories.length < 15)
                                  _newCategoryChip(ctx),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            StaggerIn(
              index: 4,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.t('priority', context),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<int>(
                        segments: [
                          ButtonSegment(
                            value: 0,
                            label: Text(Translations.t('priorityLow', context)),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: Text(
                              Translations.t('priorityMedium', context),
                            ),
                          ),
                          ButtonSegment(
                            value: 2,
                            label: Text(
                              Translations.t('priorityHigh', context),
                            ),
                          ),
                        ],
                        selected: {_priority},
                        onSelectionChanged: (s) =>
                            setState(() => _priority = s.first),
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
