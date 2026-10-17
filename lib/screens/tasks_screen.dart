import 'package:flutter/material.dart';

import 'dart:async';
import '../services/haptics.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/ai_guide_service.dart';
import '../services/settings_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../widgets/press_splat.dart' show OrganicFab;
import '../utils/markdown_text.dart' show sanitizeTextForWrap;
import '../widgets/swipe_to_delete.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_strike_text.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/sliding_picker.dart';
import '../widgets/stagger_in.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/premium_empty_state.dart';
import '../widgets/section_pill.dart'
    show kSectionPillSlotHeight, sectionCurrentIndex;
import 'add_task_screen.dart';

class TasksScreen extends StatefulWidget {
  /// Персональный notifier скролла раздела (см. AlarmsScreen).
  final ValueNotifier<double>? scrollOffset;

  /// Индекс этого раздела в PageView — ключ в sectionOffsetByPage.
  final int pillIndex;
  const TasksScreen({super.key, this.scrollOffset, this.pillIndex = 0});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin,
        SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = TaskService();
  String _filter = '';

  /// Плавная смена содержимого при переключении категории: и список задач, и
  /// пустое состояние мягко «проявляются» (фейд + лёгкий подъём). Карусель
  /// категорий при этом не пересоздаётся и никуда не прыгает.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 1,
  );
  late final Animation<double> _revealFade = Tween<double>(
    // Начинаем не с нуля: если пользователь тапает по категориям подряд,
    // список не «пропадает в пустоту», а лишь мягко подсвечивается.
    begin: 0.35,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _reveal, curve: Curves.easeOut));
  late final Animation<Offset> _revealSlide =
      Tween<Offset>(
        begin: const Offset(0, 0.02),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic));
  // Hide FAB row on scroll: smoothly slides down + fades when scrolled past
  // 8px; comes back when scrolled to top. Используем NotificationListener
  // (как на экране будильников), а НЕ ScrollController на внутреннем
  // SingleChildScrollView — при переключении фильтра категории
  // AnimatedSwitcher держит два скролл-вью одновременно, и один
  // контроллер на двух позициях ломал прокрутку.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  // Контроллер ОСНОВНОГО списка задач — источник правды для офсета таблетки
  // разделов (см. _syncPillOffset в AlarmsScreen). При смене категории
  // AnimatedSwitcher пересоздаёт список на 0 — контроллер пере-привязывается
  // и пишет 0, таблетка не «застревает» скрытой.
  final ScrollController _pillCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pillCtrl.addListener(_syncPillOffset);
    // Свежий контроллер стоит на 0 — карта офсетов могла держать высоту
    // ПРЕДЫДУЩЕЙ жизни вкладки. Без сброса таблетка разделов оставалась
    // спрятанной, пока пользователь не начнёт крутить.
    sectionOffsetByPage[widget.pillIndex] = 0.0;
    sectionCurrentIndex.addListener(_onCurrentSectionChanged);
    _service.load();
  }

  /// Раздел стал активным — форсируем ресинк офсета таблетки (keep-alive
  /// вкладка не присылает событий скролла, а общий notifier мог остаться с
  /// устаревшей высотой: таблетка разделов исчезала до первого скролла).
  void _onCurrentSectionChanged() {
    if (sectionCurrentIndex.value != widget.pillIndex) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPillOffset();
    });
  }

  /// Пишет РЕАЛЬНУЮ позицию основного скроллера в персональный notifier
  /// раздела (см. _syncPillOffset в AlarmsScreen).
  void _syncPillOffset() {
    final target = widget.scrollOffset;
    if (target == null) return;
    if (_pillCtrl.positions.length != 1) return;
    final v = _pillCtrl.offset;
    final vv = v < 0 ? 0.0 : v;
    sectionOffsetByPage[widget.pillIndex] = vv;
    // Пишем в общий sectionScrollOffset только активная вкладка:
    // неактивные keep-alive экраны иначе сбрасывают его на свой офсет и
    // таблетка вылазит на весь рост поверх прокрученного списка.
    if (sectionCurrentIndex.value == widget.pillIndex &&
        (target.value - vv).abs() > 0.5) {
      target.value = vv;
    }
  }

  @override
  void dispose() {
    _pillCtrl.removeListener(_syncPillOffset);
    sectionCurrentIndex.removeListener(_onCurrentSectionChanged);
    _pillCtrl.dispose();
    _fabVisible.dispose();
    _reveal.dispose();
        WidgetsBinding.instance.removeObserver(this);
super.dispose();
  }

  /// Смена категории: сначала меняем фильтр, затем мягко проявляем новое
  /// содержимое. Карусель живёт своим ходом (SlidingPicker сам подъезжает к
  /// выбранной таблетке) — она не входит в анимацию проявления.
  void _setFilter(String value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    // Волна проявления НЕ перезапускается с нуля, пока идёт предыдущая: при
    // быстром тапании по двум категориям список иначе мигал бы (туда-сюда),
    // каждый раз снова уезжая в прозрачность и обратно. Новое содержимое
    // просто вливается в текущую волну.
    if (!_reveal.isAnimating) _reveal.forward(from: 0);
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Возврат из фона: keep-alive восстановил позицию скролла, а общий
    // sectionScrollOffset мог остаться stale. Форсируем ресинк с реального
    // контроллера, чтобы таблетка встала по месту сразу, без пролистывания.
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncPillOffset();
      });
    }
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // После перестроения синхронизируем офсет с реальной позицией скроллера:
    // свежий список стоит на 0 — таблетка должна «вернуться», а не держать
    // старую позицию.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPillOffset();
    });
    final theme = Theme.of(context);

    return RefreshIndicator(
      // Кружок выезжает из-под таблетки разделов, а не появляется за ней
      // (поверх её) - как на экране будильников.
      edgeOffset: kSectionPillSlotHeight,
      onRefresh: () async {
        await _service.load();
        return;
      },
      child: ListenableBuilder(
        listenable: _service,
        builder: (context, _) {
          final all = _service.tasks;
          final tasks = all.where((t) {
            if (_filter == '') return true;
            if (_filter == '__uncat__') return t.category.isEmpty;
            return t.category == _filter;
          }).toList();
          return Scaffold(
            // Без своего AppBar: белая полоса под таблеткой убрана.
            // Карусель категорий лежит в header'е списка/пустого состояния —
            // листается вместе с содержимым, а не стоит фиксированной полосой.
            body: FabScrollListener(
              visible: sectionPillVisible,
              child: FabScrollListener(
                visible: _fabVisible,
                // ОДИН и тот же скролл-вью для списка и для пустого состояния
                // (пустое состояние — это 0 задач + карточка в header'е).
                // Поэтому карусель категорий живёт в дереве постоянно, при
                // переходе «непусто → пусто» НЕ пересоздаётся и не «скачет»
                // (раньше пустое состояние было другим виджетом и карусель
                // прыгала вместе с пересозданием).
                child: RepaintBoundary(
                  key: const ValueKey('tasks_scroll_view'),
                  child: _buildScrollList(context, theme, tasks, all),
                ),
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
                  // Кнопка-«плюс» как на экране будильников: обычная круглая
                  // FAB + мелкие размашистые пятнышки на её поверхности. Долгое
                  // зажатие — режим BERSERK (showBerserkSheet сам проверяет,
                  // включён ли режим в настройках).
                  OrganicFab(
                    seed: 5.2,
                    onTap: () {
                      Haptics.light();
                      _addTask();
                    },
                    onLongPress: () => showBerserkSheet(context),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Карточка пустого состояния (та же, что в [PremiumEmptyState]) — но как
  /// обычный блок ВНУТРИ скролла: без Expanded и без своего скролла.
  Widget _buildEmptyCard(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 28, 4, 32),
      child: Center(
        child: PremiumEmptyCard(
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
        ),
      ),
    );
  }

  /// Header скролла: карусель категорий всегда, а под ней — карточка пустого
  /// состояния (только когда задач нет). Структура одна и та же, поэтому
  /// карусель НЕ пересоздаётся при переходе «непусто ↔ пусто».
  Widget _buildHeader(BuildContext context, ThemeData theme, bool empty) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildCategoryHeader(context, theme),
        if (empty)
          FadeTransition(
            opacity: _revealFade,
            child: SlideTransition(
              position: _revealSlide,
              child: _buildEmptyCard(context, theme),
            ),
          ),
      ],
    );
  }

  /// Выбор категорий + кнопка управления (создание, удаление). Живёт в
  /// header скролла задач — листается вместе с ними.
  Widget _buildCategoryHeader(BuildContext context, ThemeData theme) {
    final chips = <String>['', ..._service.categories];
    // Центрированная карусель категорий + корзина (удаление выбранной).
    // Без кнопки «управление» — добавление только в форме задачи.
        // Блок категорий: верхний слот kSectionPillSlotHeight оставляем
        // для таблетки разделов (как раньше делал padding списка) —
        // карусель стоит ПОД таблеткой, а не налезает на неё.
        return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: kSectionPillSlotHeight + 8,
            bottom: 4,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: _service.categories.isEmpty
                    ? const SizedBox.shrink()
                    : SlidingPicker<String>(
                        key: const ValueKey('cat_carousel'),
                        items: chips,
                        selected: _filter,
                        height: 34,
                        viewportFraction: 0.50,
                        onChanged: _setFilter,
                        itemBuilder: (context, c, selected) {
                          final label = c == ''
                              ? Translations.allOf(context)
                              : c;
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: AnimatedContainer(
                                // Без boxShadow (размытая тень давала
                                // «серый квадрат»). Только чистый цвет
                                // + тонкая обводка у выбранного.
                                // 450 → 220 мс: старая таблетка успевала
                                // «гаснуть» целых 450 мс и всё это время
                                // ехала рядом с новой — читалось как
                                // «призрак/дубль» таблетки за категорией.
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : Colors.transparent,
                                  border: selected
                                      ? Border.all(
                                          color: theme.colorScheme.primary,
                                          width: 2,
                                        )
                                      : null,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    label,
                                    softWrap: false,
                                    textAlign: TextAlign.center,
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
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Единственный скролл раздела задач: и для списка, и для пустого состояния.
  /// Сам ReorderableListView — основной скроллер (без shrinkWrap и без
  /// вложенного SingleChildScrollView): элементы строятся лениво, только
  /// видимые. На слабых телефонах длинный список раньше собирался целиком
  /// за один кадр и «замирал» — теперь прокручивается плавно даже с
  /// десятками задач.
  Widget _buildScrollList(
    BuildContext context,
    ThemeData theme,
    List<Task> tasks,
    List<Task> all,
  ) {
    final empty = tasks.isEmpty;
    return ReorderableListView.builder(
      key: const ValueKey('list'),
      scrollController: _pillCtrl,
      // Таблетка разделов + карусель категорий (+ карточка пустого состояния,
      // если задач нет) — первый (непереставляемый) элемент списка: листаются
      // вместе с задачами, как обычный контент.
      header: _buildHeader(context, theme, empty),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      // AlwaysScrollable: иначе на пустом списке не работает pull-to-refresh
      // (раньше это делал SingleChildScrollView пустого состояния).
      physics: const AlwaysScrollableScrollPhysics(),
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
        // Плавная смена содержимого при переключении категории: задачи мягко
        // проявляются (фейд + лёгкий подъём), а не подменяются рывком.
        child: FadeTransition(
          opacity: _revealFade,
          child: SlideTransition(
            position: _revealSlide,
            child: _buildTaskCard(context, theme, tasks[i], i),
          ),
        ),
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    ThemeData theme,
    Task task,
    int index,
  ) {
    // Ключ карточки привязан к фильтру: при переключении категории
    // карточка ПЕРЕСОЗДАЁТСЯ мгновенно (без чаcтичного слипания
    // состояний SwipeToDelete/AnimatedSize между категориями).
    // Сам список при этом переключается атомарно — без анимации.
    final cardKey = ValueKey('card_${_filter}_${task.id}');
    return SwipeToDelete(
      key: cardKey,
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
        // «Вдавливание» при зажатии — карточка мягко уменьшается.
        hoverScale: 0.98,
        duration: const Duration(milliseconds: 160),
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
                SizedBox(
                width: 46,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Галка СВЕРХУ драг-хэндла (одна колонка 46px).
                    Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // (scale 0.9) — «чуть выделяется», без мигания и
                      // вспышек. Иконка меняется сразу (фон заливается
                      // плавно AnimatedContainer'ом).
                      Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _toggleTask(task),
                          splashColor: theme.colorScheme.primary.withValues(alpha: 0.14),
                          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(16),
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
                          // Плавная смена значка: иконка задачи → галка с
                          // лёгким «попом» (fade + scale), как в привычках.
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 280),
                            switchInCurve: Curves.easeOutBack,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                            child: task.done
                                ? const Icon(
                                    Icons.check,
                                    key: ValueKey('task_done_check'),
                                    size: 23,
                                    color: Colors.white,
                                  )
                                : Icon(
                                    task.icon,
                                    key: const ValueKey('task_icon'),
                                    size: 23,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    ],
                  ),
                    const SizedBox(height: 6),
                    // Драг-хэндл — снизу.
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
                                  fontSize: 22.5,
                                  height: 1.25,
                                  color: theme.colorScheme.onSurface,
                                ),
                                // Тот же масштаб шрифта, что рендерит текст:
                                // иначе линии зачёркивания при системном
                                // масштабе ≠ 1.0 не совпадают со строками.
                                textScaler: MediaQuery.textScalerOf(context),
                                struck: task.done,
                                // Текст в отмеченном состоянии — заметно
                                // полупрозрачный (а не просто другой оттенок):
                                // прозрачность едет вместе с линией.
                                struckColor: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.42),
                                strikeColor:
                                    Colors.red.shade500.withValues(alpha: 0.9),
                                // Полный текст без троеточия: заголовок
                                // задачи всегда виден целиком, а не обрезан.
                                maxLines: null,
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
      tween: Tween(begin: 1.0, end: 1.0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.88 + 0.12 * t, child: child),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.5, -0.5),
            radius: 1.15,
            colors: [
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.10),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28), width: 1),
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

  /// Плашка заметки «Вспомнил, что использую…»: лавандовый градиент под
  /// тему, иконка-лампочка и ВЕСЬ текст заметки (до 150 символов) —
  /// без обрезки: длинная заметка просто растягивает карточку.
  Widget _noteChip(String note, ThemeData theme, BuildContext context) {
    final lavender = Color.lerp(
      theme.colorScheme.primary,
      const Color(0xFF9C6ADE),
      0.45,
    )!;
    final peach = Color.lerp(
      theme.colorScheme.primary,
      const Color(0xFFFFB08A),
      0.4,
    )!;
    return TweenAnimationBuilder<double>(
      key: ValueKey('note_chip'),
      tween: Tween(begin: 1.0, end: 1.0),
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
              peach.withValues(alpha: 0.14),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: lavender.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.lightbulb_outline_rounded,
                size: 14,
                color: lavender,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                sanitizeTextForWrap(note),
                // ВЕСЬ текст заметки всегда виден: без maxLines длинная
                // заметка (до 150 символов) переносится целиком, а карточка
                // плавно растёт под неё. Раньше кап 3 строки резал текст
                // многоточием — «видно не все 150 символов».
                // NBSP/невидимые символы из копипасты вычищаем, иначе
                // слова «слипаются» и длинное слово сползает на новую
                // строку, хотя на текущей полно места.
                maxLines: null,
                softWrap: true,
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

  /// Меню быстрого списка «Вспомнил, что использую…»: красивое статичное
  /// окно по центру с полем заметки до 150 символов (весь текст виден).
  /// Открывается долгим зажатием задачи (3 секунды), когда режим включён.
  void _showTaskNote(Task task) {
    Haptics.medium();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (ctx, _, _) => Center(
        // Окно плавно поднимается ВМЕСТЕ с клавиатурой: нижние кнопки
        // («Сохранить», «Очистить») никогда не оказываются под ней и не
        // дёргаются скачком — раньше низ окна уезжал под клавиатуру.
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: _TaskNoteSheet(task: task, service: _service),
        ),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// Долгое зажатие задачи (3 секунды): без пульсации, кружка прогресса
/// и потемнения — карточка просто остаётся на месте, и по истечении 3
/// секунд плавно открывается меню заметки «Вспомнил, что использую…».
/// Работает всегда (в настройках остался только старый переключатель).
class _TaskHoldNote extends StatefulWidget {
  final Widget child;
  final VoidCallback onHold;
  const _TaskHoldNote({required this.child, required this.onHold});

  @override
  State<_TaskHoldNote> createState() => _TaskHoldNoteState();
}

class _TaskHoldNoteState extends State<_TaskHoldNote> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    if (_timer != null) return;
    _timer = Timer(const Duration(seconds: 3), () {
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
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: widget.child,
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
  late final TextEditingController _ctrl = WideDashController(
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
    // Лаванда и персик из темы — плавно «перетекают» в фирменные тона.
    final lavender = Color.lerp(cs.primary, const Color(0xFF9C6ADE), 0.45)!;
    final peach = Color.lerp(cs.primary, const Color(0xFFFFB08A), 0.4)!;
    final base = Color.lerp(
      cs.surfaceContainerLow,
      const Color(0xFF2A2140),
      0.4,
    )!;
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            base,
            Color.lerp(base, lavender, 0.22)!,
            Color.lerp(base, peach, 0.12)!,
          ],
        ),
        border: Border.all(
          color: Color.lerp(
            lavender,
            Colors.white,
            0.35,
          )!.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
          BoxShadow(
            color: lavender.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 0),
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
                  Color.lerp(lavender, const Color(0xFF4A3A7A), 0.35)!,
                  Color.lerp(peach, lavender, 0.6)!,
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
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: SmoothTyping(
                controller: _ctrl,
                builder: (style) => TextField(
                  style: style,
                  cursorOpacityAnimates: true,
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLength: 150,
                  inputFormatters: [WideDashFormatter()],
                  enableSuggestions: false,
                  autocorrect: false,
                  // ВСЕ строки заметки всегда видны: поле растёт под весь
                  // текст без ограничения строк (раньше кап 10 строк срезал
                  // длинные заметки), а общее окно скроллится при нехватке
                  // места на экране.
                  maxLines: null,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  magnifierConfiguration: TextMagnifierConfiguration.disabled,
                  contextMenuBuilder: minimalContextMenuBuilder,
                  buildCounter: smoothCharCounterBuilder,
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
    );
  }
}
