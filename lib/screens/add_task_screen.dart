import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_tooltip.dart' show SmoothTooltip, BackButtonTooltip;
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/icon_map.dart';
import '../widgets/icon_picker_sheet.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/item_reveal.dart';
import '../widgets/category_chip.dart';
import '../utils/snackbar.dart';
import '../widgets/stagger_in.dart';
import '../widgets/priority_selector.dart';
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
      _titleCtrl = WideDashController(text: widget.existing!.title);
      _iconCodePoint = widget.existing!.iconCodePoint;
      _category = widget.existing!.category;
      _priority = widget.existing!.priority;
      _editing = true;
    } else {
      _titleCtrl = WideDashController();
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
    final ctrl = WideDashController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('newCategory', context)),
        content: SmoothTyping(
          controller: ctrl,
          builder: (style) => TextField(
            style: style,
            cursorOpacityAnimates: true,
            magnifierConfiguration: TextMagnifierConfiguration.disabled,
            controller: ctrl,
            contextMenuBuilder: minimalContextMenuBuilder,
            decoration: InputDecoration(
              labelText: Translations.t('categoryName', context),
              border: const OutlineInputBorder(),
            ),
            inputFormatters: [
              LengthLimitingTextInputFormatter(15),
              WideDashFormatter(),
            ],
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
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
      if (_taskSvc.categories.length >= _taskSvc.maxCategories) {
        showBeautifulSnackBar(
          context,
          message: Translations.t(
            'maxCat',
            context,
            'Максимум {n} категорий',
          ).replaceAll('{n}', '${_taskSvc.maxCategories}'),
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
    final ctrl = WideDashController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(Translations.t('category', context)),
        content: SmoothTyping(
          controller: ctrl,
          builder: (style) => TextField(
            style: style,
            cursorOpacityAnimates: true,
            magnifierConfiguration: TextMagnifierConfiguration.disabled,
            controller: ctrl,
            contextMenuBuilder: minimalContextMenuBuilder,
            maxLength: 15,
            enableSuggestions: false,
            autocorrect: false,
            buildCounter: smoothCharCounterBuilder,
            // Широкое тире и в переименовании: раньше форматтер стоял во всех
            // полях, КРОМЕ этого, — поэтому здесь тире и оставалось узким.
            inputFormatters: [WideDashFormatter()],
            decoration: InputDecoration(
              labelText: Translations.t('categoryName', context),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
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

  /// Плавный «чип» категории: ширина и подпись едут одним движением
  /// (см. [CategoryChip]), выбор анимируется цветом, а не «прыгает».
  Widget _categoryChip(BuildContext context, String value) {
    final label = value.isEmpty ? Translations.uncategorizedOf(context) : value;
    return CategoryChip(
      label: label,
      selected: _category == value,
      onTap: () {
        if (_category == value) return;
        Haptics.light();
        setState(() => _category = value);
      },
    );
  }

  /// Кнопка «+ Новая категория» в ряду чипов.
  Widget _newCategoryChip(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PressScale(
        pressedScale: 0.96,
        duration: const Duration(milliseconds: 400),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _createCategory,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeInOutCubic,
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
        leading: const BackButtonTooltip(),
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
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.50,
                        ),
                        width: 2,
                      ),
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
                  child: SmoothTyping(
                    controller: _titleCtrl,
                    builder: (style) => TextField(
                      style: style,
                      cursorOpacityAnimates: true,
                      magnifierConfiguration:
                          TextMagnifierConfiguration.disabled,
                      controller: _titleCtrl,
                      contextMenuBuilder: minimalContextMenuBuilder,
                      maxLength: 250,
                      inputFormatters: [WideDashFormatter()],
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLines: 5,
                      buildCounter: smoothCharCounterBuilder,
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
                          Expanded(
                            child: Text(
                              Translations.categoryOf(context),
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          // Карандаш + корзина: обе плавно появляются/
                          // исчезают (AnimatedSwitcher: fade + scale) ТОЛЬКО
                          // когда выбрана конкретная категория.
                          // Unique: slide-from-right + subtle scale
                          SizedBox(
                            height: 36,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 420),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              // Карандаш и корзина ВЫЛЕТАЮТ из мелкого в
                              // крупное с плавным фейдом и так же плавно
                              // улетают обратно. Прозрачность — линейная
                              // (без overshoot), масштаб — легко «пружинит»
                              // (easeOutBack), поэтому появление живое, но
                              // не дёргается.
                              transitionBuilder: (child, anim) {
                                final curved = CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOutBack,
                                  reverseCurve: Curves.easeInCubic,
                                );
                                return FadeTransition(
                                  opacity: anim,
                                  child: ScaleTransition(
                                    scale: Tween<double>(
                                      begin: 0.42,
                                      end: 1.0,
                                    ).animate(curved),
                                    child: child,
                                  ),
                                );
                              },
                              child: _category.isNotEmpty
                                  ? Row(
                                      // Ключ зависит только от ФАКТА выбора,
                                      // а не от имени категории: при смене
                                      // категории ряд НЕ пересоздаётся и не
                                      // мигает повторным появлением.
                                      key: ValueKey(
                                        'cat_btns_${_category.isNotEmpty}',
                                      ),
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        SmoothTooltip(
                                          message: Translations.t(
                                            'category',
                                            context,
                                          ),
                                          preferredAbove: true,
                                          child: PressScale(
                                            // Медленная плавная отдача: при
                                            // зажатии карандаш мягко уменьшается.
                                            pressedScale: 0.86,
                                            duration: const Duration(
                                              milliseconds: 460,
                                            ),
                                            child: IconButton(
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                                size: 17,
                                              ),
                                              onPressed: () =>
                                                  _renameCategory(_category),
                                              // Заливка отклика — в тон темы, а
                                              // не серый кружок по умолчанию.
                                              splashColor: theme
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.12),
                                              highlightColor:
                                                  Colors.transparent,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SmoothTooltip(
                                          message: Translations.t(
                                            'deleteCategory',
                                            context,
                                            'Удалить категорию',
                                          ),
                                          preferredAbove: true,
                                          child: PressScale(
                                            // Медленная плавная отдача: при
                                            // зажатии корзина мягко уменьшается.
                                            pressedScale: 0.86,
                                            duration: const Duration(
                                              milliseconds: 460,
                                            ),
                                            child: IconButton(
                                              icon: Icon(
                                                Icons.delete_outline,
                                                size: 17,
                                                color: theme.colorScheme.error,
                                              ),
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: Text(
                                                      Translations.t(
                                                        'deleteCategory',
                                                        context,
                                                      ),
                                                    ),
                                                    content: Text(_category),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              false,
                                                            ),
                                                        child: Text(
                                                          Translations.cancelOf(
                                                            context,
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                              ctx,
                                                              true,
                                                            ),
                                                        child: Text(
                                                          Translations.deleteOf(
                                                            context,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true &&
                                                    mounted) {
                                                  setState(() {
                                                    _taskSvc.removeCategory(
                                                      _category,
                                                    );
                                                    _category = '';
                                                  });
                                                }
                                              },
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              splashColor: theme
                                                  .colorScheme
                                                  .error
                                                  .withValues(alpha: 0.12),
                                              highlightColor:
                                                  Colors.transparent,
                                              constraints: const BoxConstraints(
                                                minWidth: 32,
                                                minHeight: 32,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(
                                      key: ValueKey('cat_btns_empty'),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ListenableBuilder(
                        listenable: _taskSvc,
                        builder: (ctx, _) {
                          final cats = <String>['', ..._taskSvc.categories];
                          // Создание, удаление и переименование категорий —
                          // плавно: новый чип РАЗВОРАЧИВАЕТСЯ на своём месте,
                          // удалённый тает «призраком», а соседи мягко
                          // съезжаются, без рывка строки.
                          return ChipsReveal(
                            items: cats,
                            height: 44,
                            itemBuilder: _categoryChip,
                            trailing:
                                _taskSvc.categories.length <
                                    _taskSvc.maxCategories
                                ? _newCategoryChip(ctx)
                                : null,
                          );
                        },
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
                      // Свой селектор вместо SegmentedButton: капсулы с
                      // градиентом, бликом и цветным свечением выбранного
                      // уровня — тот же визуальный язык, что у таблетки
                      // приоритета в списке задач, но «глубже».
                      PrioritySelector(
                        value: _priority,
                        onChanged: (p) => setState(() => _priority = p),
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
