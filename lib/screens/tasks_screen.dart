import 'package:flutter/material.dart';

import 'dart:async';
import '../services/haptics.dart';
import '../services/sounds.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/task.dart';
import '../services/task_service.dart';
import '../services/ai_guide_service.dart';
import '../services/settings_service.dart';
import '../l10n/translations.dart';
import '../utils/context_menu.dart';
import '../utils/markdown_text.dart' show sanitizeTextForWrap;
import '../widgets/drag_proxy.dart';
import '../widgets/swipe_to_delete.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../utils/wide_dash_formatter.dart';
import '../utils/wide_dash_controller.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/animated_strike_text.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/sliding_picker.dart';
import '../widgets/smooth_char_counter.dart';
import '../widgets/smooth_typing.dart';
import '../widgets/premium_empty_state.dart';
import '../utils/section_tints.dart';
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
        TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = TaskService();
  String _filter = '';

  // Данные ещё не загружены: показываем пустоту вместо кадра пустого
  // состояния, который при старте сменялся списком — читалось как мигание.
  bool _loaded = false;

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
  late final Animation<Offset> _revealSlide = Tween<Offset>(
    begin: const Offset(0, 0.02),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _reveal, curve: Curves.easeOutCubic));

  /// Плавное «рождение» полок «Активные»/«Выполненные»: пока выполнена хотя
  /// бы одна задача, между активными и выполненными появляется заголовок и
  /// воздух. Без анимации это был бы резкий «щелчок» раскладки (список
  /// мгновенно разъезжается на две полки). Анимируем появление полки
  /// «Выполненные»: заголовок и её список мягко проявляются, а сдвиг
  /// компенсирует [SizeTransition] в шапке — соседние карточки не прыгают.
  late final AnimationController _splitReveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );
  late final Animation<double> _splitFade = CurvedAnimation(
    parent: _splitReveal,
    curve: Curves.easeOutCubic,
  );

  /// «Опускание» только что выполненной задачи: карточка мягко съезжает
  /// вниз (из зоны активных в полку выполненных) и проявляется. Так
  /// переезд ОДНОЙ карточки читается как движение, а не как «исчезла там —
  /// возникла здесь». Запускается на каждую отметку.
  late final AnimationController _cardDrop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late final Animation<double> _cardDropT = CurvedAnimation(
    parent: _cardDrop,
    curve: Curves.easeOutCubic,
  );
  /// Вертикальный «приезд» карточки: доля высоты карточки, поэтому сдвиг
  /// сам масштабируется под её размер (без чтения .value в build — иначе
  /// смещение застыло бы на значении момента сборки).
  late final Animation<Offset> _cardDropSlide = Tween<Offset>(
    begin: const Offset(0, -0.16),
    end: Offset.zero,
  ).animate(_cardDropT);
  /// id только что выполненной задачи — её карточка анимируется в полке
  /// «Выполненные»; остальные рисуются сразу.
  String? _justCompletedId;
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
    // Общий ряд «плюс + Ада» на Home берёт действие именно этого раздела.
    sectionAddActions[widget.pillIndex] = _addTask;
    sectionCurrentIndex.addListener(_onCurrentSectionChanged);
    // Данные уже прочитаны в main() до первого кадра — показываем их сразу,
    // без кадра пустого состояния. Повторный load() в фоне дешёвый и
    // подхватит правки, если кто-то писал в файл извне.
    if (_service.isLoaded) _loaded = true;
    _service.load().then((_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    });
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
    // В общий офсет пишет [reportSectionPillOffset] и только когда раздел
    // активен и карусель стоит ровно на нём: во время переезда высоту
    // таблетки ведёт Home интерполяцией между соседними разделами.
    reportSectionPillOffset(widget.pillIndex, v < 0 ? 0.0 : v);
  }

  @override
  void dispose() {
    _pillCtrl.removeListener(_syncPillOffset);
    sectionAddActions.remove(widget.pillIndex);
    sectionCurrentIndex.removeListener(_onCurrentSectionChanged);
    _pillCtrl.dispose();
    _fabVisible.dispose();
    _reveal.dispose();
    _splitReveal.dispose();
    _cardDrop.dispose();
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

  /// Отметить задачу выполненной. Отметка НЕОБРАТИМА: повторный тап по уже
  /// выполненной задаче ничего не делает — галка не снимается. При выполнении
  /// Ада «реально» выдаёт награду — снекбаром, когда достигнута новая веха
  /// (все сделано / N всего / стрик).
  /// Защита от двойного срабатывания: палец на слабом экране может «дрогнуть»
  /// и GestureDetector выдаст второй tap — значок мигал бы туда-обратно.
  /// Повторный toggle в течение 500 мс игнорируется.
  DateTime? _lastTaskTap;

  Future<void> _toggleTask(Task task) async {
    // Снять галку нельзя: выполненная задача уходит на полку «Выполненные»
    // и остаётся там. Вернуть её в работу можно только правкой задачи.
    if (task.done) return;
    final now = DateTime.now();
    if (_lastTaskTap != null &&
        now.difference(_lastTaskTap!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastTaskTap = now;
    // Приятный тактильный отклик: лёгкий «клик» при отметке задачи.
    Haptics.select();
    // Парный мягкий звук — если человек включил звуки в настройках.
    Sounds.success();
    // Была ли полка «Выполненные» ДО отметки: деление списка появляется
    // ровно один раз (первая выполненная задача) — только тогда его и
    // раскрываем плавно, а не мигаем полкой на каждой отметке.
    final hadDone = _service.tasks.any((t) => t.done);
    // Показываем переезд ДО мутации: карточка в полке «Выполненные» должна
    // приехать анимированно (иначе полка уже стоит на экране, и вставка
    // читается как рывок).
    setState(() => _justCompletedId = task.id);
    _cardDrop.forward(from: 0).whenComplete(() {
      // Снимаем «анимируемую» метку: карточка больше не оборачивается
      // переходом (иначе один лишний набор слоёв висел бы на ней всегда).
      if (mounted && _justCompletedId == task.id) {
        setState(() => _justCompletedId = null);
      }
    });
    await _service.toggle(task.id);
    if (!mounted) return;
    // Первая выполненная задача рождает полку «Выполненные» — раскрываем её
    // плавно, чтобы список не «щелкнул» из одной полки в две.
    final hasDone = _service.tasks.any((t) => t.done);
    if (!hadDone && hasDone) {
      _splitReveal.forward(from: 0);
    }
    try {
      final lang = await SettingsService.loadLanguageCode();
      // Награды за вехи (все задачи выполнены / всего N) Ада забирает в чат —
      // отдельный слой, короткой похвале он не мешает.
      await AiGuideService.collectRewards(lang);
      // Короткая похвала — ОДНА строка и разная на каждую отметку (см.
      // [AiGuideService.taskDoneLine]). Раньше на обычной задаче не
      // показывалось ничего, а на вехе всплывало длинное поздравление.
      final line = await AiGuideService.taskDoneLine(lang);
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: line,
          icon: Icons.emoji_events,
          iconColor: Colors.amber,
          duration: const Duration(seconds: 3),
          groupKey: 'task_done',
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
            // Прозрачный фон: общая «skin»-подложка Home уже стоит ПОД
            // PageView — разделы показывают ОДНУ ту же поверхность, которая
            // «задвигается» при прокрутке (а не дорисовывает свой белый блок
            // под сворачивающейся таблеткой).
            backgroundColor: Colors.transparent,
            body: FabScrollListener(
              visible: sectionPillVisible,
              child: FabScrollListener(
                visible: _fabVisible,
                // ОДИН и тот же скролл-вью для списка и для пустого состояния
                // (пустое состояние — это 0 задач + карточка в header'е).
                // Поэтому карусель категорий живёт в дереве постоянно и при
                // переходе «непусто → пусто» не пересоздаётся.
                child: RepaintBoundary(
                  key: const ValueKey('tasks_scroll_view'),
                  // До загрузки данных — пустота: кадр пустого состояния,
                  // сменявшийся списком, читался как мигание после сплэша.
                  child: !_loaded
                      ? const SizedBox.shrink(key: ValueKey('tasks_loading'))
                      : _buildScrollList(context, theme, tasks, all),
                ),
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
          padding: EdgeInsets.only(top: kSectionPillSlotHeight + 8, bottom: 4),
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
                                // 180 мс: цвет выбранной категории успевает
                                // догнать карусель, а не «доцветает» после
                                // её остановки (тот самый лаг в конце).
                                duration: const Duration(milliseconds: 180),
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
  /// Сам список — [SliverReorderableList] внутри [CustomScrollView]: элементы
  /// строятся лениво, только видимые, поэтому прокрутка остаётся плавной и с
  /// десятками задач.
  ///
  /// Пока выполненных задач нет — один список без заголовков. Как только
  /// появляется хотя бы одна выполненная — список делится на две полки
  /// «Активные» и «Выполненные» (по образцу Полезные/Вредные в привычках).
  /// Полки — РАЗНЫЕ sliver-списки, поэтому выполненную задачу нельзя
  /// перетащить обратно в активные.
  Widget _buildScrollList(
    BuildContext context,
    ThemeData theme,
    List<Task> tasks,
    List<Task> all,
  ) {
    final empty = tasks.isEmpty;
    final active = tasks.where((t) => !t.done).toList();
    final done = tasks.where((t) => t.done).toList();
    // Делим на полки ровно тогда, когда есть что положить на «Выполненные».
    final split = done.isNotEmpty;

    // Полка «Выполненные» (заголовок + её список) появляется ПЛАВНО: фейд
    // целиком, а верхний зазор растёт через SizeTransition — список ниже не
    // «прыгает» вниз, а мягко разъезжается.
    final completedGroup = SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: SizeTransition(
            sizeFactor: _splitFade,
            alignment: Alignment.topCenter,
            child: const SizedBox(height: 14),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _shelfHeader(
              context,
              theme,
              'tasksSectionDone',
              SectionTints.completed(theme),
            ),
          ),
        ),
        _taskSliver(context, theme, done, all),
      ],
    );

    return CustomScrollView(
      key: const ValueKey('list'),
      controller: _pillCtrl,
      // AlwaysScrollable: иначе на пустом списке не работает pull-to-refresh.
      physics: const AlwaysScrollableScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
      slivers: [
        // Таблетка разделов + карусель категорий (+ карточка пустого
        // состояния, если задач нет) — первый (непереставляемый) элемент
        // списка: листаются вместе с задачами, как обычный контент.
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _buildHeader(context, theme, empty),
          ),
        ),
        if (split && active.isNotEmpty) ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _shelfHeader(
                context,
                theme,
                'tasksSectionActive',
                SectionTints.active(theme),
              ),
            ),
          ),
          _taskSliver(context, theme, active, all),
        ] else
          _taskSliver(context, theme, active, all),
        if (split) SliverFadeTransition(opacity: _splitFade, sliver: completedGroup),
        const SliverToBoxAdapter(child: SizedBox(height: 4)),
      ],
    );
  }

  /// Один переставляемый список задач (полка). Отдельный sliver на каждую
  /// полку — так сохраняется ленивая сборка и перетаскивание не пересекает
  /// границу между «Активными» и «Выполненными».
  Widget _taskSliver(
    BuildContext context,
    ThemeData theme,
    List<Task> list,
    List<Task> all,
  ) {
    if (list.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverReorderableList(
        itemCount: list.length,
        // Медленнее штатного автоскролла (по умолчанию 50 → ~1000 px/с):
        // 18 → ~360 px/с. При подтаскивании карточки к кромке список едет
        // спокойно и предсказуемо, а не «улетает» рывком.
        autoScrollerVelocityScalar: 18,
        proxyDecorator: (child, index, animation) =>
            buildDragProxy(child, theme, animation),
        onReorderItem: (oldLocal, newLocal) {
          // Локальный индекс (в полке) → глобальный (в полном списке),
          // чтобы reorder сохранял порядок и при активном фильтре категории.
          final oldGlobal = all.indexOf(list[oldLocal]);
          if (oldGlobal < 0) return;
          int newGlobal;
          if (newLocal >= list.length) {
            newGlobal = all.indexOf(list.last) + 1;
            if (newGlobal > all.length) newGlobal = all.length;
          } else {
            newGlobal = all.indexOf(list[newLocal]);
            if (newGlobal < 0) newGlobal = oldGlobal;
          }
          if (newGlobal == oldGlobal) return;
          _service.reorder(oldGlobal, newGlobal);
        },
        itemBuilder: (context, i) {
          final task = list[i];
          // Только что выполненная задача «приезжает» на полку выполненных:
          // мягко съезжает сверху и проявляется. Остальные карточки рисуются
          // сразу — анимируется ровно одна, переезд читается как движение.
          if (task.id == _justCompletedId && task.done) {
            return KeyedSubtree(
              key: ValueKey('item_task_${task.id}'),
              child: SlideTransition(
                position: _revealSlide,
                child: FadeTransition(
                  opacity: _cardDropT,
                  child: SizeTransition(
                    sizeFactor: _cardDropT,
                    alignment: Alignment.topCenter,
                    child: SlideTransition(
                      position: _cardDropSlide,
                      child: _buildTaskCard(context, theme, task, i),
                    ),
                  ),
                ),
              ),
            );
          }
          return KeyedSubtree(
            key: ValueKey('item_task_${task.id}'),
            // Плавная смена содержимого при переключении категории: только
            // лёгкий подъём (SlideTransition — чистая трансформация, без
            // saveLayer). FadeTransition на КАЖДОЙ карточке создавал по
            // слою прозрачности на карточку каждый кадр — на слабом GPU это
            // и был «тормоз в конце» переключения категорий.
            child: SlideTransition(
              position: _revealSlide,
              child: _buildTaskCard(context, theme, task, i),
            ),
          );
        },
      ),
    );
  }

  /// Заголовок полки: цветное название + растворяющаяся линия до края —
  /// тот же приём, что у «Полезные/Вредные» в привычках. Появляется мягко
  /// (фейд + подъём), чтобы деление списка на две полки не «щёлкало».
  Widget _shelfHeader(
    BuildContext context,
    ThemeData theme,
    String keyName,
    Color tint,
  ) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Row(
        children: [
          Text(
            Translations.t(keyName, context),
            style: theme.textTheme.titleSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: tint.withValues(alpha: 0.4))),
        ],
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      ),
      child: row,
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
      // Фон удаления = границы карточки: у [Card] стандартный margin 4 px,
      // без этого красная плашка выходила за карточку со всех сторон.
      inset: const EdgeInsets.all(4),
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
                              key: ValueKey('task_toggle_${task.id}'),
                              onTap: () => _toggleTask(task),
                              splashColor: theme.colorScheme.primary.withValues(
                                alpha: 0.14,
                              ),
                              highlightColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.06),
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
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
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
                                strikeColor: Colors.red.shade500.withValues(
                                  alpha: 0.9,
                                ),
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
                        // Приоритет + срок (если задан) — одной строкой.
                        if (task.priority >= 0 || task.dueAt != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (task.priority >= 0)
                                _priorityPill(task.priority, theme, context),
                              // Срок появляется/исчезает плавно и мягко
                              // раздвигает приоритет (SizeTransition по
                              // горизонтали), а не вставляется рывком.
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, anim) =>
                                    FadeTransition(
                                      opacity: anim,
                                      child: SizeTransition(
                                        sizeFactor: anim,
                                        axis: Axis.horizontal,
                                        child: child,
                                      ),
                                    ),
                                child: task.dueAt == null
                                    ? const SizedBox.shrink(
                                        key: ValueKey('no_due'),
                                      )
                                    : KeyedSubtree(
                                        key: ValueKey(
                                          task.dueAt!.toIso8601String(),
                                        ),
                                        child: _duePill(task, theme, context),
                                      ),
                              ),
                            ],
                          ),
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
    return Container(
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
    );
  }

  /// Срок задачи: «до какого дня» + «за сколько». Просроченная — красная,
  /// сегодняшняя — оранжевая, остальные — спокойные. Компактно, одной
  /// строкой с приоритетом.
  Widget _duePill(Task task, ThemeData theme, BuildContext context) {
    final cs = theme.colorScheme;
    final overdue = task.isOverdue;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = task.dueAt!;
    final dueDay = DateTime(due.year, due.month, due.day);
    final isToday = dueDay == today;
    final color = overdue
        ? cs.error
        : isToday
        ? const Color(0xFFE08A00)
        : cs.onSurfaceVariant;
    final label = overdue
        ? Translations.t('overdue', context, 'Просрочено')
        : isToday
        ? Translations.t('dueToday', context, 'Сегодня')
        : '${due.day.toString().padLeft(2, '0')}.'
              '${due.month.toString().padLeft(2, '0')}';
    final est = task.estimateMinutes;
    final estLabel = est == null
        ? null
        : est < 60
        ? '$est мин'
        : '${est ~/ 60} ч';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            overdue ? Icons.warning_amber_rounded : Icons.schedule,
            size: 13,
            color: color.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 5),
          Text(
            estLabel == null ? label : '$label · $estLabel',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color.withValues(alpha: 0.88),
            ),
          ),
        ],
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
    return Container(
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
              // плавно растёт под неё.
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
        // дёргаются скачком.
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
                  // текст без ограничения строк, а общее окно скроллится при
                  // нехватке места на экране.
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
