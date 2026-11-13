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
import '../widgets/category_chip.dart';
import '../widgets/due_date_picker.dart';
import '../utils/snackbar.dart';
import '../widgets/stagger_in.dart';
import '../widgets/priority_selector.dart';
import '../widgets/smooth_keyboard_body.dart';
import '../services/haptics.dart';
import '../widgets/agysha_confirm_dialog.dart';

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
  DateTime? _dueAt;
  int? _estimateMinutes;

  /// Ряд категорий с плавным сдвигом: AnimatedList сам анимирует
  /// удаление/добавление, а соседи переезжают кадр в кадр.
  final GlobalKey<AnimatedListState> _catListKey =
      GlobalKey<AnimatedListState>();
  List<String> _catItems = <String>[];
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
      _dueAt = widget.existing!.dueAt;
      _estimateMinutes = widget.existing!.estimateMinutes;
      _editing = true;
    } else {
      _titleCtrl = WideDashController();
      _iconCodePoint = 58830;
      _category = '';
      _priority = 0;
      _dueAt = null;
      _estimateMinutes = null;
    }
    _taskSvc.load();
    _catItems = <String>['', ..._taskSvc.categories];
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
      // Center обязателен: в ряду высотой 44 чип ростом 36 без центрирования
      // прилипал к ВЕРХУ и стоял выше соседних категорий (CategoryChip
      // центрируется сам) — та самая «новая категория выше остальных».
      child: Center(
        child: PressScale(
          // Отдача «вдавливанием», как у верхних кнопок: чип заметно
          // уменьшается под пальцем. Рябь InkWell убрана — она читалась как
          // «подсветка фоном», а не как отклик на нажатие.
          pressedScale: 0.94,
          duration: const Duration(milliseconds: 180),
          releaseDuration: const Duration(milliseconds: 280),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _createCategory,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeInOutCubic,
              // Габариты РОВНО как у соседних категорий (CategoryChip.height и
              // та же набивка): «+ Новая категория» не выбивается из ряда.
              height: CategoryChip.height,
              padding: const EdgeInsets.symmetric(
                horizontal: CategoryChip.hPad,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  width: CategoryChip.borderWidth,
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
      ),
    );
  }

  bool _sameCatList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Диффит ряд категорий и анимирует удаление/вставку. Благодаря этому
  /// после удаления соседи СДВИГАЮТСЯ плавно (SizeTransition по ширине),
  /// а не прыгают на новое место; добавление/переименование — так же.
  void _syncCatList(List<String> target) {
    final state = _catListKey.currentState;
    if (state == null) {
      _catItems = List<String>.from(target);
      return;
    }
    // Удаляем то, чего больше нет — с конца, чтобы индексы не съезжали.
    for (var i = _catItems.length - 1; i >= 0; i--) {
      if (!target.contains(_catItems[i])) {
        final removed = _catItems.removeAt(i);
        state.removeItem(
          i,
          (context, animation) => _catItemBuilder(context, removed, animation),
          duration: const Duration(milliseconds: 260),
        );
      }
    }
    // Вставляем/переставляем по порядку.
    for (var i = 0; i < target.length; i++) {
      if (i < _catItems.length && _catItems[i] == target[i]) continue;
      final existing = _catItems.indexOf(target[i]);
      if (existing >= 0) {
        final moved = _catItems.removeAt(existing);
        state.removeItem(
          existing,
          (context, animation) => _catItemBuilder(context, moved, animation),
          duration: const Duration(milliseconds: 220),
        );
      }
      _catItems.insert(i, target[i]);
      state.insertItem(i, duration: const Duration(milliseconds: 260));
    }
    // Хвост (если остался) — убираем.
    while (_catItems.length > target.length) {
      final idx = _catItems.length - 1;
      final removed = _catItems.removeAt(idx);
      state.removeItem(
        idx,
        (context, animation) => _catItemBuilder(context, removed, animation),
        duration: const Duration(milliseconds: 220),
      );
    }
  }

  Widget _catItemBuilder(
    BuildContext context,
    String name,
    Animation<double> animation,
  ) {
    final isNew = name == '__new__';
    final child = isNew
        ? _newCategoryChip(context)
        : _categoryChip(context, name);
    return SizeTransition(
      sizeFactor: animation,
      axis: Axis.horizontal,
      child: FadeTransition(
        opacity: animation,
        child: KeyedSubtree(key: ValueKey('cat_$name'), child: child),
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
      dueAt: _dueAt,
      estimateMinutes: _estimateMinutes,
      createdAt: widget.existing?.createdAt,
    );
    Navigator.of(context).pop(task);
  }

  /// Короткий срок задачи: «до какого дня» + «за сколько».
  ///
  /// Быстрые чипы (сегодня/завтра/3 дня/неделя) закрывают 95 % случаев
  /// одним тапом; «Дата…» открывает календарь. Всё на одном Card и
  /// анимируется 180 мс — без простыней и без реординга.
  Widget _deadlineCard(BuildContext context, ThemeData theme) {
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59);
    final tomorrow = today.add(const Duration(days: 1));
    final in3 = today.add(const Duration(days: 3));
    final inWeek = today.add(const Duration(days: 7));

    bool sameDay(DateTime? a, DateTime b) =>
        a != null && a.year == b.year && a.month == b.month && a.day == b.day;

    Widget quick(String label, DateTime? value) => _DeadlineChip(
      label: label,
      selected: value == null ? _dueAt == null : sameDay(_dueAt, value),
      onTap: () => setState(() => _dueAt = value),
    );

    final customSelected =
        _dueAt != null &&
        !sameDay(_dueAt, today) &&
        !sameDay(_dueAt, tomorrow) &&
        !sameDay(_dueAt, in3) &&
        !sameDay(_dueAt, inWeek);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  Translations.t('dueDate', context, 'Срок'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  key: const ValueKey('due_label'),
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  // Подпись прижата к ПРАВОМУ краю. По умолчанию AnimatedSwitcher
                  // центрирует детей в Stack, а ширина «Сегодня» и «12.11»
                  // разная — при смене текста правый край уезжал, это и читалось
                  // как «дёргает вправо». Прижимаем содержимое вправо: правый
                  // край неподвижен, меняется только левый.
                  layoutBuilder: (currentChild, previousChildren) => Stack(
                    alignment: Alignment.centerRight,
                    children: [...previousChildren, ?currentChild],
                  ),
                  // Только КРОССФЕЙД: раньше подпись въезжала справа
                  // (Offset(0.25, 0)) и читалась как «дёргает вправо».
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: _dueAt == null
                      ? const SizedBox.shrink(key: ValueKey('due_none'))
                      : Text(
                          _dueLabel(context, _dueAt!),
                          key: ValueKey(_dueAt!.toIso8601String()),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                quick(Translations.t('dueNone', context, 'Без срока'), null),
                quick(Translations.t('dueToday', context, 'Сегодня'), today),
                quick(
                  Translations.t('dueTomorrow', context, 'Завтра'),
                  tomorrow,
                ),
                quick(
                  Translations.t('dueIn3Days', context, 'Через 3 дня'),
                  in3,
                ),
                quick(
                  Translations.t('dueInWeek', context, 'Через неделю'),
                  inWeek,
                ),
                _DeadlineChip(
                  label: Translations.t('duePickDate', context, 'Дата…'),
                  selected: customSelected,
                  icon: Icons.calendar_month_outlined,
                  onTap: _pickDueDate,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 17, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  Translations.t('estimate', context, 'За сколько'),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: cs.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [15, 30, 60, 120, 240])
                  _DeadlineChip(
                    label: _estimateLabel(m),
                    selected: _estimateMinutes == m,
                    onTap: () => setState(
                      () => _estimateMinutes = _estimateMinutes == m ? null : m,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _estimateLabel(int minutes) =>
      minutes < 60 ? '$minutes мин' : '${minutes ~/ 60} ч';

  String _dueLabel(BuildContext context, DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff < 0) return Translations.t('overdue', context, 'Просрочено');
    if (diff == 0) return Translations.t('dueToday', context, 'Сегодня');
    if (diff == 1) return Translations.t('dueTomorrow', context, 'Завтра');
    return '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')}';
  }

  Future<void> _pickDueDate() async {
    final picked = await showDueDatePicker(context, _dueAt);
    if (picked == null || !mounted) return;
    setState(() {
      _dueAt = DateTime(picked.year, picked.month, picked.day, 23, 59);
    });
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
                                                final confirm =
                                                    await showAgyshaConfirm(
                                                      context,
                                                      title: Translations.t(
                                                        'deleteCategory',
                                                        context,
                                                      ),
                                                      body: _category,
                                                      icon: Icons
                                                          .delete_outline_rounded,
                                                      confirmLabel:
                                                          Translations.deleteOf(
                                                            context,
                                                          ),
                                                      destructive: true,
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
                          final showTrailing =
                              _taskSvc.categories.length <
                              _taskSvc.maxCategories;
                          final target = <String>[
                            ...cats,
                            if (showTrailing) '__new__',
                          ];
                          if (!_sameCatList(_catItems, target)) {
                            // Синхронизируем AnimatedList ПОСЛЕ кадра:
                            // внутри builder нельзя звать insert/remove.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _syncCatList(target);
                            });
                          }
                          return SizedBox(
                            height: 44,
                            child: AnimatedList(
                              key: _catListKey,
                              scrollDirection: Axis.horizontal,
                              initialItemCount: _catItems.length,
                              itemBuilder: (context, i, animation) {
                                final name = i < _catItems.length
                                    ? _catItems[i]
                                    : '__new__';
                                return _catItemBuilder(
                                  context,
                                  name,
                                  animation,
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Срок — ПОСЛЕ категории (категория теперь ниже приоритета):
            // «до какого дня» + «за сколько», короткими чипами.
            StaggerIn(index: 5, child: _deadlineCard(context, theme)),
          ],
        ),
      ),
    );
  }
}

/// Компактная чип-кнопка срока: выбранная заливается primary, остальные —
/// спокойные. 180 мс easeOutCubic — переключение читается мягко.
class _DeadlineChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _DeadlineChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  State<_DeadlineChip> createState() => _DeadlineChipState();
}

class _DeadlineChipState extends State<_DeadlineChip> {
  /// Палец на чипе: чип заметно «вдавливается» и подсвечивается — отдача,
  /// которой раньше не было. Listener только слушает, тап остаётся у
  /// GestureDetector.
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = widget.selected;
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.select();
          widget.onTap();
        },
        child: AnimatedScale(
          // Отчётливое «вдавливание» (0.92) — заметно глазу, в отличие от
          // прежних 0.96 на мелком чипе.
          scale: _pressed ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              // Отдача — только «вдавливание» (AnimatedScale ниже), без
              // подсветки фона: цветовая заливка читалась как «просто фон»,
              // а не как отклик на нажатие.
              color: selected ? cs.primary : cs.surfaceContainerHighest,
              border: Border.all(
                color: selected
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.72),
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 14,
                    color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    // Вес ПОСТОЯННЫЙ. Раньше выбранный чип становился жирнее
                    // (w500→w700) и ШИРЕ — соседи по Wrap сдвигались вправо,
                    // это и читалось как «дёргается вправо» при смене срока.
                    // Выбор показываем цветом и обводкой, а не набором веса.
                    fontWeight: FontWeight.w600,
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
