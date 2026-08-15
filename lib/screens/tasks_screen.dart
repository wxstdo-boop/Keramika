import 'package:flutter/material.dart';
import '../services/haptics.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/ai_guide_service.dart';
import '../services/settings_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/swipe_to_delete.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_strike_text.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/sliding_picker.dart';
import '../widgets/stagger_in.dart';
import '../widgets/premium_empty_state.dart';
import 'add_task_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = TaskService();
  String _filter = '';
  // Hide FAB row on scroll: smoothly slides down + fades when scrolled past
  // 8px; comes back when scrolled to top. Используем NotificationListener
  // (как на экране будильников), а НЕ ScrollController на внутреннем
  // SingleChildScrollView — при переключении фильтра категории
  // AnimatedSwitcher держит два скролл-вью одновременно, и один
  // контроллер на двух позициях ломал прокрутку.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    _service.load();
  }

  @override
  void dispose() {
    _fabVisible.dispose();
    super.dispose();
  }

  void _addTask() async {
    Haptics.light();
    if (_service.tasks.length >= 150) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxTasks', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<Task>(slideUpRoute(const AddTaskScreen()));
    if (result != null) {
      await _service.add(result);
    }
  }

  void _editTask(Task task) async {
    final result = await Navigator.of(
      context,
    ).push<Task>(slideUpRoute(AddTaskScreen(existing: task)));
    if (result != null) {
      await _service.update(result);
    }
  }

  /// Отметить/снять задачу. При выполнении Ада «реально» выдаёт награду —
  /// снекбаром, когда достигнута новая веха (все сделано / N всего / стрик).
  /// Сохраняем `wasDone` ДО toggle: после возврата из сервиса у задачи
  /// уже инвертирован .done — иначе легко ошибиться и награждать за снятие.
  Future<void> _toggleTask(Task task) async {
    // Приятный тактильный отклик: лёгкий «клик» при отметке задачи.
    Haptics.select();
    final wasDone = task.done;
    await _service.toggle(task.id);
    if (!mounted || !wasDone) return; // награждаем только за ВЫПОЛНЕНИЕ
    try {
      final lang = await SettingsService.loadLanguageCode();
      final rewards = await AiGuideService.collectRewards(lang);
      if (rewards.isNotEmpty && mounted) {
        showBeautifulSnackBar(
          context,
          message: rewards.first,
          icon: Icons.emoji_events,
          iconColor: Colors.amber,
          duration: const Duration(seconds: 4),
          groupKey: 'ada_reward',
        );
      }
    } catch (_) {}
  }

  void _manageCategories() async {
    final ctrl = TextEditingController();
    // Локальная копия + AnimatedList: появление категории разворачивается,
    // удаление плавно сжимается по высоте (служба хранит готовый список
    // без анимаций, а тут мы хотим «живые» переходы).
    final listKey = GlobalKey<AnimatedListState>();
    final cats = List<String>.of(_service.categories);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          // Появление/удаление категории: разворот по высоте + fade.
          Widget buildCategoryTile(String c, Animation<double> anim) {
            return SizeTransition(
              sizeFactor: anim,
              child: FadeTransition(
                opacity: anim,
                child: ListTile(
                  title: Text(c),
                  trailing: IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: ctx,
                        builder: (dctx) => AlertDialog(
                          title: Text(
                            Translations.t('deleteCategory', context),
                          ),
                          content: Text(c),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: Text(Translations.cancelOf(context)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: Text(Translations.deleteOf(context)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final idx = cats.indexOf(c);
                        if (idx == -1) return;
                        cats.removeAt(idx);
                        listKey.currentState?.removeItem(
                          idx,
                          (context, animation) =>
                              buildCategoryTile(c, animation),
                          duration: const Duration(milliseconds: 260),
                        );
                        setSt(() {});
                        _service.removeCategory(c);
                      }
                    },
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(Translations.t('manageCategories', context)),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          magnifierConfiguration:
                              TextMagnifierConfiguration.disabled,
                          controller: ctrl,
                          contextMenuBuilder: minimalContextMenuBuilder,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(15),
                          ],
                          decoration: InputDecoration(
                            labelText: Translations.t('categoryName', context),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          if (await _service.addCategory(ctrl.text)) {
                            final name = ctrl.text;
                            ctrl.clear();
                            final idx = cats.length;
                            cats.add(name);
                            listKey.currentState?.insertItem(
                              idx,
                              duration: const Duration(milliseconds: 260),
                            );
                            setSt(() {});
                          } else {
                            showBeautifulSnackBar(
                              ctx,
                              message: Translations.t('categoryExists', ctx),
                              icon: Icons.warning_amber_outlined,
                              iconColor: Colors.orange,
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: AnimatedList(
                      key: listKey,
                      shrinkWrap: true,
                      initialItemCount: cats.length,
                      itemBuilder: (context, index, animation) =>
                          buildCategoryTile(cats[index], animation),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(Translations.okOf(context)),
              ),
            ],
          );
        },
      ),
    );
    if (_filter != '' && !_service.categories.contains(_filter)) {
      _filter = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        await _service.load();
        return;
      },
      child: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final all = _service.tasks;
          final chips = <String>['', ..._service.categories];
          final tasks = all.where((t) {
            if (_filter == '') return true;
            if (_filter == '__uncat__') return t.category.isEmpty;
            return t.category == _filter;
          }).toList();
          final hasTasks = tasks.isNotEmpty;
          return Scaffold(
            appBar: AppBar(
              title: Text(Translations.tasksOf(context)),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: Translations.t('manageCategories', context),
                  onPressed: _manageCategories,
                ),
              ],
            ),
            body: FabScrollListener(
              visible: _fabVisible,
              child: Column(
                children: [
                  if (_service.categories.isNotEmpty)
                    SlidingPicker<String>(
                      items: chips,
                      selected: _filter,
                      height: 52,
                      viewportFraction: 0.55,
                      onChanged: (c) => setState(() => _filter = c),
                      itemBuilder: (context, c, selected) {
                        final label = c == '' ? Translations.allOf(context) : c;
                        return Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceContainerHighest,
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.25),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: selected
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(
                            begin: 0.98,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: hasTasks
                          ? KeyedSubtree(
                              // Ключ меняется вместе с фильтром: AnimatedSwitcher
                              // плавно переводит список при переключении
                              // категорий (раньше ключ был константным —
                              // список просто прыгал без анимации).
                              key: ValueKey('task_list_$_filter'),
                              child: _buildList(context, theme, tasks, all),
                            )
                          : _buildEmpty(context, theme),
                    ),
                  ),
                  _footer(context, theme),
                ],
              ),
            ),
            floatingActionButton: AnimatedFabRow(
              visible: _fabVisible,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const AiGuideFloatingButton(),
                  const SizedBox(width: 10),
                  BerserkFabStack(
                    // Долгое зажатие «плюса» открывает BERSERK.
                    child: GestureDetector(
                      onLongPress: () => showBerserkSheet(context),
                      child: FloatingActionButton(
                        onPressed: _addTask,
                        child: const Icon(Icons.add),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, ThemeData theme) {
    return PremiumEmptyState(
      key: ValueKey('empty_$_filter'),
      icon: Icons.task_alt_outlined,
      title: Translations.noTasksOf(context),
      hint: Translations.t('emptyTaskHint', context),
      advice: Translations.t('emptyTaskAdvice', context),
      actionLabel: Translations.t('newTask', context),
      accent: const Color(0xFF5E8FB5),
      onPressed: _addTask,
    );
  }

  Widget _buildList(
    BuildContext context,
    ThemeData theme,
    List<Task> tasks,
    List<Task> all,
  ) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    // Сам ReorderableListView — основной скроллер (без shrinkWrap и без
    // вложенного SingleChildScrollView): элементы строятся лениво, только
    // видимые. На слабых телефонах длинный список раньше собирался целиком
    // за один кадр и «замирал» — теперь прокручивается плавно даже с
    // десятками задач.
    return ReorderableListView.builder(
      key: const ValueKey('list'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
      buildDefaultDragHandles: false,
      itemCount: tasks.length,
      proxyDecorator: (child, index, animation) =>
          _taskDragProxy(child, theme, animation),
      onReorderItem: (oldLocal, newLocal) {
        // Локальный индекс (в отфильтрованном списке) → глобальный
        // (в полном списке), чтобы reorder сохранял порядок и при
        // активном фильтре категории.
        final oldGlobal = all.indexOf(tasks[oldLocal]);
        if (oldGlobal < 0) return;
        int newGlobal;
        if (newLocal >= tasks.length) {
          newGlobal = all.indexOf(tasks.last) + 1;
          if (newGlobal > all.length) newGlobal = all.length;
        } else {
          newGlobal = all.indexOf(tasks[newLocal]);
          if (newGlobal < 0) newGlobal = oldGlobal;
        }
        if (newGlobal == oldGlobal) return;
        _service.reorder(oldGlobal, newGlobal);
      },
      itemBuilder: (context, i) => StaggerIn(
        key: ValueKey('item_task_${tasks[i].id}'),
        index: i,
        extraDelay: const Duration(milliseconds: 320),
        child: _buildTaskCard(context, theme, tasks[i], i),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    ThemeData theme,
    Task task,
    int index,
  ) {
    return SwipeToDelete(
      // Ключ теперь на внешнем StaggerIn (см. itemBuilder).
      dismissKey: ValueKey('dismiss_${task.id}'),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(Translations.deleteOf(context)),
            content: Text(task.title),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(Translations.cancelOf(context)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(Translations.deleteOf(context)),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => _service.remove(task.id),
      child: SmoothHover(
        child: Card(
          key: ValueKey(task.id),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              // Drag handle слева — ReorderableDragStartListener включает
              // перетаскивание (как в привычках).
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 24,
                    color: Colors.grey,
                  ),
                ),
              ),
              // Чекбокс в левой колонке, как в привычках (уже, чтобы
              // больше ширины оставалось тексту)
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => _toggleTask(task),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: task.done
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: task.done
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outline,
                            width: 2,
                          ),
                        ),
                        child: task.done
                            ? const Icon(
                                Icons.check,
                                size: 20,
                                color: Colors.white,
                              )
                            : Icon(
                                task.icon,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              // Основное содержимое
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Строка заголовка: текст задачи + компактная кнопка редактирования
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            // Плавное зачёркивание: линия «рисуется» по тексту
                            // при отметке и «стирается» при снятии (см.
                            // AnimatedStrikeText) — вместо мгновенного
                            // TextDecoration.lineThrough.
                            child: AnimatedStrikeText(
                              text: task.title,
                              style: theme.textTheme.titleMedium!.copyWith(
                                height: 1.25,
                                color: theme.colorScheme.onSurface,
                              ),
                              struck: task.done,
                              struckColor: theme.colorScheme.onSurfaceVariant,
                              strikeColor: theme.colorScheme.outline,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _editTask(task),
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            style: IconButton.styleFrom(
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      // Приоритет (если есть)
                      if (task.priority > 0) ...[
                        const SizedBox(height: 8),
                        _priorityPill(task.priority, theme, context),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _taskDragProxy(
    Widget child,
    ThemeData theme,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        final scale = 1.0 + 0.03 * t;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: 2 + 10 * t,
            shadowColor: theme.colorScheme.primary.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.surface,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(
                    alpha: 0.15 + 0.55 * t,
                  ),
                  width: 1.5 + t,
                ),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Color _priorityColor(int p, ThemeData theme) {
    switch (p) {
      case 2:
        return Colors.red.shade300;
      case 1:
        return Colors.amber.shade400;
      default:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Widget _priorityPill(int p, ThemeData theme, BuildContext context) {
    final color = _priorityColor(p, theme);
    final label = switch (p) {
      2 => Translations.t('priorityHigh', context),
      1 => Translations.t('priorityMedium', context),
      _ => Translations.t('priorityLow', context),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Translations.madeWithLoveOf(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.favorite, size: 14, color: Colors.pink[300]),
        ],
      ),
    );
  }
}
