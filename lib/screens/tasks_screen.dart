import 'package:flutter/material.dart';

import 'dart:async';
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
  /// Защита от двойного срабатывания: палец на слабом экране может
  /// «дрогнуть» и GestureDetector выдаст второй tap — значок мигал бы
  /// туда-обратно. Повторный toggle в течение 500 мс игнорируется.
  DateTime? _lastTaskTap;

  Future<void> _toggleTask(Task task) async {
    final now = DateTime.now();
    if (_lastTaskTap != null &&
        now.difference(_lastTaskTap!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastTaskTap = now;
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
                        FocusManager.instance.primaryFocus?.unfocus();
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
                      // Плавнее и красивее переключение категорий: новый
                      // список «всплывает» снизу (slide 28px + fade +
                      // лёгкий scale), старый плавно гаснет.
                      duration: const Duration(milliseconds: 460),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.035),
                            end: Offset.zero,
                          ).animate(animation),
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.985, end: 1.0)
                                .animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  ),
                                ),
                            child: child,
                          ),
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
                        onPressed: () {
                          Haptics.light();
                          _addTask();
                        },
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
      onPressed: () {
        Haptics.light();
        _addTask();
      },
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
      itemBuilder: (context, i) => KeyedSubtree(
        key: ValueKey('item_task_${tasks[i].id}'),
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
        child: _TaskHoldNote(
          onHold: () => _showTaskNote(task),
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
                // Чекбокс в левой колонке, как в привычках: колонка уже (40)
                // и значок крупнее (23) — иконка ближе к драг-хэндлу слева.
                SizedBox(
                  width: 40,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // (scale 0.9) — «чуть выделяется», без мигания и
                      // вспышек. Иконка меняется сразу (фон заливается
                      // плавно AnimatedContainer'ом).
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _toggleTask(task),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          width: 32,
                          height: 32,
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
                                  size: 23,
                                  color: Colors.white,
                                )
                              : Icon(
                                  task.icon,
                                  size: 23,
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
                                maxLines: 6,
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
                        // Приоритет (всегда показываем, включая low=0)
                        if (task.priority >= 0) ...[
                          const SizedBox(height: 8),
                          _priorityPill(task.priority, theme, context),
                        ],
                        // Заметка «Вспомнил, что использую…» — красивая
                        // плашка внизу карточки.
                        if (task.note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _noteChip(task.note, theme, context),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
    // ТО ЖЕ, что buildDragProxy: перетаскиваемый элемент монтируется
    // в оверлее ЗАНОВО, поэтому без подавления входной каскад StaggerIn
    // проигрывался бы прямо во время драга — текст «прыгал» и менял
    // положение, а после приземления возвращался. Плюс без инкремента
    // SmoothHover.dragProxyCount живая карточка не узнавала о драге,
    // оставалась увеличенной и «дублировалась» рядом с прокси.
    StaggerIn.suppressEntrance = true;
    SmoothHover.dragProxyCount.value++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StaggerIn.suppressEntrance = false;
      SmoothHover.dragProxyCount.value--;
    });
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
              // foregroundDecoration — обводка ПОВЕРХ, не участвует в layout
              // (как в buildDragProxy): размеры прокси = размеры карточки,
              // текст не перетекает на другие строки при драге.
              foregroundDecoration: BoxDecoration(
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

  /// Цвет приоритета: ярче и контрастнее.
  Color _priorityColor(int p, ThemeData theme) {
    switch (p) {
      case 2:
        return Colors.red.shade400;
      case 1:
        return Colors.orange.shade500;
      default:
        return Colors.green.shade500;
    }
  }

  /// Иконка приоритета: визуальный маркер.
  IconData _priorityIcon(int p) {
    switch (p) {
      case 2:
        return Icons.warning_amber_rounded;
      case 1:
        return Icons.hourglass_empty_rounded;
      default:
        return Icons.push_pin_rounded;
    }
  }

  /// Таблетка приоритета: градиентный фон, иконка + текст, плавное
  /// появление при добавлении задачи.
  Widget _priorityPill(int p, ThemeData theme, BuildContext context) {
    final color = _priorityColor(p, theme);
    final icon = _priorityIcon(p);
    final label = switch (p) {
      2 => Translations.t('priorityHigh', context),
      1 => Translations.t('priorityMedium', context),
      _ => Translations.t('priorityLow', context),
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey('priority_pill_$p'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.25),
              color.withValues(alpha: 0.15),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плашка заметки «Вспомнил, что использую…»: лавандовый градиент,
  /// иконка-лампочка и текст до 3 строк с многоточием.
  Widget _noteChip(String note, ThemeData theme, BuildContext context) {
    final lavender = const Color(0xFF9C6ADE);
    return TweenAnimationBuilder<double>(
      key: ValueKey('note_chip'),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              lavender.withValues(alpha: 0.22),
              const Color(0xFFFFB08A).withValues(alpha: 0.14),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: lavender.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lightbulb_outline_rounded,
                size: 14,
                color: Color(0xFF9C6ADE),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                note,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Меню быстрого списка «Вспомнил, что использую…»: красивое окно снизу
  /// с полем заметки до 150 символов. Открывается долгим зажатием задачи
  /// (5 секунд), когда режим включён в разработке.
  void _showTaskNote(Task task) {
    Haptics.medium();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskNoteSheet(task: task, service: _service),
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

/// Долгое зажатие задачи (5 секунд): плавный прогресс-кружок вокруг
/// карточки и открытие меню быстрого списка «Вспомнил, что использую…».
/// Работает только когда режим включён (SettingsService.taskNotesEnabled).
class _TaskHoldNote extends StatefulWidget {
  final Widget child;
  final VoidCallback onHold;
  const _TaskHoldNote({required this.child, required this.onHold});

  @override
  State<_TaskHoldNote> createState() => _TaskHoldNoteState();
}

class _TaskHoldNoteState extends State<_TaskHoldNote>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 5),
  );
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    if (!SettingsService.taskNotesEnabled.value) return;
    if (_timer != null) return;
    _ctrl.value = 0;
    _ctrl.forward();
    _timer = Timer(const Duration(seconds: 5), () {
      _timer = null;
      if (mounted) {
        Haptics.medium();
        widget.onHold();
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    _ctrl.stop();
    _ctrl.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: Stack(
        children: [
          widget.child,
          // Плавный прогресс-кружок, рисуется только во время зажатия.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  final v = _ctrl.value;
                  if (v <= 0.005) return const SizedBox.shrink();
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.black.withValues(alpha: 0.22 * v),
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 46,
                        height: 46,
                        child: CircularProgressIndicator(
                          value: v,
                          strokeWidth: 3.5,
                          color: const Color(0xFFFFD54F),
                          backgroundColor: Colors.white24,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Красивое окно заметки «Вспомнил, что использую…» (до 150 символов).
class _TaskNoteSheet extends StatefulWidget {
  final Task task;
  final TaskService service;
  const _TaskNoteSheet({required this.task, required this.service});

  @override
  State<_TaskNoteSheet> createState() => _TaskNoteSheetState();
}

class _TaskNoteSheetState extends State<_TaskNoteSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.task.note,
  );
  late final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final note = _ctrl.text.trim();
    if (note == widget.task.note) {
      Navigator.pop(context);
      return;
    }
    widget.task.note = note;
    await widget.service.update(widget.task);
    if (mounted) {
      Navigator.pop(context);
      showBeautifulSnackBar(
        context,
        message: note.isEmpty
            ? Translations.taskNoteClearedOf(context)
            : Translations.taskNoteSavedOf(context),
        icon: note.isEmpty
            ? Icons.delete_outline
            : Icons.lightbulb_outline_rounded,
        iconColor: const Color(0xFF9C6ADE),
      );
    }
  }

  void _clear() {
    _ctrl.clear();
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lavender = const Color(0xFF9C6ADE);
    final peach = const Color(0xFFFFB08A);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surfaceContainerHigh,
              Color.lerp(cs.surfaceContainerHigh, lavender, 0.10)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Верхняя шапка: градиент + лампочка.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(lavender, const Color(0xFF4A3A7A), 0.4)!,
                    Color.lerp(peach, lavender, 0.55)!,
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 1.4,
                      ),
                    ),
                    child: const Icon(
                      Icons.lightbulb_outline_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Translations.t('taskNoteSheetTitle', context),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 1.25,
                      shadows: [
                        Shadow(
                          color: Colors.black38,
                          blurRadius: 8,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Translations.t('taskNoteSheetSubtitle', context),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLength: 150,
                maxLines: 4,
                minLines: 2,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: Translations.t('taskNoteHint', context),
                  filled: true,
                  fillColor: cs.surfaceContainerLowest.withValues(alpha: 0.7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  counterStyle: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  if (widget.task.note.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(Translations.clearNoteOf(context)),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: lavender,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      Translations.saveOf(context),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
