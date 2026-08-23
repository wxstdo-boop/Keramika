import 'dart:async';
import 'dart:math';
import '../services/haptics.dart';
import 'package:flutter/material.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/habit.dart';
import '../services/habit_service.dart';
import '../services/settings_service.dart';
import '../l10n/translations.dart';
import '../widgets/swipe_to_delete.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/drag_proxy.dart';
import '../widgets/animated_strike_text.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/premium_empty_state.dart';
import 'add_habit_screen.dart';

class _PerfPlaque {
  final String titleKey;
  final String bodyKey;
  final String shortKey;
  final IconData icon;
  final Color color;
  const _PerfPlaque({
    required this.titleKey,
    required this.bodyKey,
    required this.shortKey,
    required this.icon,
    required this.color,
  });
}

const _perfPlaques = [
  _PerfPlaque(
    titleKey: 'perfTitle1',
    bodyKey: 'perf1Full',
    shortKey: 'perf1Short',
    icon: Icons.psychology_outlined,
    color: Color(0xFFB39DDB),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle2',
    bodyKey: 'perf2Full',
    shortKey: 'perf2Short',
    icon: Icons.gradient_outlined,
    color: Color(0xFF7B61FF),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle3',
    bodyKey: 'perf3Full',
    shortKey: 'perf3Short',
    icon: Icons.ac_unit_outlined,
    color: Color(0xFF80D8FF),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle4',
    bodyKey: 'perf4Full',
    shortKey: 'perf4Short',
    icon: Icons.aspect_ratio_outlined,
    color: Color(0xFFFFAB91),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle5',
    bodyKey: 'perf5Full',
    shortKey: 'perf5Short',
    icon: Icons.hourglass_empty_outlined,
    color: Color(0xFFFFD54F),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle6',
    bodyKey: 'perf6Full',
    shortKey: 'perf6Short',
    icon: Icons.favorite_border_outlined,
    color: Color(0xFFFF8A80),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle7',
    bodyKey: 'perf7Full',
    shortKey: 'perf7Short',
    icon: Icons.loop_outlined,
    color: Color(0xFF80CBC4),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle8',
    bodyKey: 'perf8Full',
    shortKey: 'perf8Short',
    icon: Icons.help_outline_outlined,
    color: Color(0xFFFFB74D),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle9',
    bodyKey: 'perf9Full',
    shortKey: 'perf9Short',
    icon: Icons.tune_outlined,
    color: Color(0xFF90A4AE),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle10',
    bodyKey: 'perf10Full',
    shortKey: 'perf10Short',
    icon: Icons.spa_outlined,
    color: Color(0xFFAED9E0),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle11',
    bodyKey: 'perf11Full',
    shortKey: 'perf11Short',
    icon: Icons.self_improvement,
    color: Color(0xFFCE93D8),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle12',
    bodyKey: 'perf12Full',
    shortKey: 'perf12Short',
    icon: Icons.track_changes,
    color: Color(0xFF80DEEA),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle13',
    bodyKey: 'perf13Full',
    shortKey: 'perf13Short',
    icon: Icons.visibility_outlined,
    color: Color(0xFFF06292),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle14',
    bodyKey: 'perf14Full',
    shortKey: 'perf14Short',
    icon: Icons.sensors,
    color: Color(0xFF4DD0E1),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle15',
    bodyKey: 'perf15Full',
    shortKey: 'perf15Short',
    icon: Icons.lightbulb_outline,
    color: Color(0xFFFFCA28),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle16',
    bodyKey: 'perf16Full',
    shortKey: 'perf16Short',
    icon: Icons.self_improvement_outlined,
    color: Color(0xFF9FA8DA),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle17',
    bodyKey: 'perf17Full',
    shortKey: 'perf17Short',
    icon: Icons.balance_outlined,
    color: Color(0xFF81C784),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle18',
    bodyKey: 'perf18Full',
    shortKey: 'perf18Short',
    icon: Icons.explore,
    color: Color(0xFFFF8A65),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle19',
    bodyKey: 'perf19Full',
    shortKey: 'perf19Short',
    icon: Icons.auto_awesome,
    color: Color(0xFFBA68C8),
  ),
  _PerfPlaque(
    titleKey: 'perfTitle20',
    bodyKey: 'perf20Full',
    shortKey: 'perf20Short',
    icon: Icons.emoji_objects,
    color: Color(0xFF4DB6AC),
  ),
];

class HabitsScreen extends StatefulWidget {
  const HabitsScreen({super.key});
  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = HabitService();
  // FAB-ряд прячется при прокрутке вниз и плавно возвращается у верха.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  final Map<String, bool> _expandedNotes = {};
  Timer? _dayTimer;
  // Ревизия порядка: при закрепе/открепе список привычек плавно
  // «перетекает» в новую раскладку (кросс-фейд), а не прыгает позициями.
  int _pinRev = 0;
  bool _perfectionismMode = false;
  bool _perfScreenOpened = false;

  // Long-press on the habit body toggles the pinned state.

  // Triple tap on habit card = smooth streak reset.
  // 3 taps within 600ms window on the same habit trigger update().
  // _lastResetAt provides a 1500ms cooldown so spam-tapping doesn't
  // fire multiple resets in a row.
  int _tapCount = 0;
  DateTime? _lastTapTime;
  String? _tappedHabitId;
  // Per-habit cooldown: 1500ms after reset, only blocks the SAME habit.
  Map<String, DateTime> _lastResetByHabit = <String, DateTime>{};

  @override
  void initState() {
    super.initState();
    _service.load();
    _loadPerfectionismMode();
    SettingsService.perfectionismEnabled.addListener(_onPerfectionismChanged);
    // Проверка смены дня: приложение может жить в фореграунде через полночь —
    // нормализуем doneToday/стрик прямо здесь, чтобы карточка никогда не
    // показывала ВЧЕРАШНЮЮ галочку как сегодняшнюю. Иначе первый тап сегодня
    // «съедается» как отмена вчерашней отметки, и стрик выглядит сбитым
    // (пользователь видит «считает как два»).
    _dayTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final before = _service.habits
          .map((h) => '${h.id}:${h.doneToday}:${h.streak}')
          .join('|');
      _service.normalizeIfDayChanged();
      final after = _service.habits
          .map((h) => '${h.id}:${h.doneToday}:${h.streak}')
          .join('|');
      if (before != after) setState(() {});
    });
  }

  void _addHabit() async {
    Haptics.light();
    if (_service.habits.length >= 100) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxHabits', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<Habit>(slideUpRoute(const AddHabitScreen()));
    if (result != null) _service.add(result);
  }

  void _editHabit(Habit habit) async {
    final result = await Navigator.of(
      context,
    ).push<Habit>(slideUpRoute(AddHabitScreen(existing: habit)));
    if (result != null) _service.update(result);
  }

  void _loadPerfectionismMode() {
    SettingsService.loadPerfectionism().then((v) {
      if (mounted) setState(() => _perfectionismMode = v);
    });
  }

  void _onPerfectionismChanged() {
    if (mounted) {
      setState(
        () => _perfectionismMode = SettingsService.perfectionismEnabled.value,
      );
    }
  }

  /// Triple tap on habit card = smooth streak reset with streak-dots fade
  /// (AnimatedContainer 320ms easeOut). On 3rd tap within 600ms we
  /// reset streak/doneToday/lastDoneDate via _service.update().
  /// 1500ms cooldown prevents repeated resets when user keeps tapping.
  void _handleHabitTap(Habit habit) {
    // Triple-tap streak reset only works for good habits.
    if (habit.type != 'good') return;
    final now = DateTime.now();
    final lastReset = _lastResetByHabit[habit.id];
    if (lastReset != null &&
        now.difference(lastReset) < const Duration(milliseconds: 1500)) {
      return;
    }
    final sameHabit = _tappedHabitId == habit.id;
    final withinWindow =
        _lastTapTime != null &&
        now.difference(_lastTapTime!) <= const Duration(milliseconds: 500);
    if (!sameHabit || !withinWindow) {
      _tapCount = 1;
      _tappedHabitId = habit.id;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    // Сброс — только после 4 быстрых тапов (раньше 3: случайные',
    // «топтания» по карточке стирали стрик — «то исчезает, то ещё что»).',
    if (_tapCount >= 4) {
      _tapCount = 0;
      _tappedHabitId = null;
      _lastResetByHabit[habit.id] = now;
      // copyWith умеет очищать lastDoneDate (null через сентинел) —
      // сброс стрика делает state честным: streak=0, дата пуста.
      _service.update(
        habit.copyWith(streak: 0, doneToday: false, lastDoneDate: null),
      );
      Haptics.select();
      if (mounted) {
        showBeautifulSnackBar(
          context,
          message: Translations.t('streakResetDone', context, 'Streak reset'),
          icon: Icons.restart_alt,
          iconColor: Theme.of(context).colorScheme.primary,
        );
      }
    }
  }

  void _togglePin(Habit habit) async {
    Haptics.medium();
    final updated = habit.copyWith(pinned: !habit.pinned);
    await _service.update(updated);
    if (!mounted) return;
    // Плавный кросс-фейд списка в новую раскладку (закреплённая карточка
    // оказывается сверху). Без снимков, «перелётов» и вспышек: ничего не
    // растягивается, не дёргается и не подтормаживает (раньше тут был
    // полный toImage карточки + полёт RawImage поверх списка).
    setState(() => _pinRev++);
    showBeautifulSnackBar(
      context,
      message: updated.pinned
          ? Translations.t('habitPinned', context, 'Habit pinned')
          : Translations.t('habitUnpinned', context, 'Habit unpinned'),
      icon: Icons.push_pin,
    );
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    _fabVisible.dispose();
    SettingsService.perfectionismEnabled.removeListener(
      _onPerfectionismChanged,
    );
    super.dispose();
  }

  void _showPerfFullScreen(String body, String title, Color color) {
    if (_perfScreenOpened) return;
    _perfScreenOpened = true;
    final theme = Theme.of(context);
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            fullscreenDialog: true,
            transitionDuration: const Duration(milliseconds: 280),
            reverseTransitionDuration: const Duration(milliseconds: 220),
            pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
              appBar: AppBar(
                backgroundColor: color,
                foregroundColor: Colors.white,
                title: Text(title),
                centerTitle: true,
              ),
              body: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      color.withValues(alpha: 0.3),
                      color.withValues(alpha: 0.05),
                    ],
                  ),
                ),
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      height: 1.6,
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeInOut,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.96, end: 1.0).animate(curved),
                      child: child,
                    ),
                  );
                },
          ),
        )
        .then((_) => _perfScreenOpened = false);
  }

  List<_PerfPlaque> _todaysPlaques() {
    final now = DateTime.now();
    // День + час — меняем подборку каждый час.
    final seed =
        now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
    final rng = Random(seed);
    final shuffled = List<_PerfPlaque>.from(_perfPlaques);
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    // Каждый день 4-6 карточек вместо 3 — более глубокий рандом.
    final count = min(shuffled.length, rng.nextInt(3) + 4);
    return shuffled.sublist(0, count);
  }

  /// Глобальная сортировка привычек: pinned сверху, затем полезные перед
  /// вредными, внутри группы — по createdAt. Используется одновременно
  /// для отображения одной секции (если есть только один тип) и для
  /// маппинга локальных↔глобальных индексов при reorder в секциях.
  List<Habit> _orderForDisplay(List<Habit> habits) {
    // HabitService keeps the backing list with pinned items first.
    // Do not re-sort here, otherwise manual drag order is lost.
    return List<Habit>.from(habits);
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
          final habits = _orderForDisplay(_service.habits);
          return Scaffold(
            appBar: AppBar(
              title: Text(Translations.habitsOf(context)),
              centerTitle: true,
            ),
            body: FabScrollListener(
              visible: _fabVisible,
              child: Column(
                children: [
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
                      child: habits.isNotEmpty
                          ? SizedBox.expand(
                              key: const ValueKey('list'),
                              child: _buildBody(context, theme, habits),
                            )
                          : _buildEmpty(context, theme),
                    ),
                  ),
                ],
              ),
            ),
            // SingleChildScrollView is now inside _buildBody and _buildEmpty
            floatingActionButton: AnimatedFabRow(
              visible: _fabVisible,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const AiGuideFloatingButton(),
                  const SizedBox(width: 10),
                  BerserkFabStack(
                    // Долгое зажатие «плюса» открывает режим BERSERK.
                    child: GestureDetector(
                      onLongPress: () => showBerserkSheet(context),
                      child: FloatingActionButton(
                        onPressed: () {
                          Haptics.light();
                          _addHabit();
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
      key: const ValueKey('empty'),
      icon: Icons.spa_outlined,
      title: Translations.noHabitsOf(context),
      hint: Translations.t('emptyHabitHint', context),
      advice: Translations.t('emptyHabitAdvice', context),
      actionLabel: Translations.t('newHabit', context),
      accent: const Color(0xFF8E6DB8),
      onPressed: _addHabit,
    );
  }

  /// Тело списка привычек: либо один список, либо две секции Полезные/Вредные.
  Widget _buildBody(BuildContext context, ThemeData theme, List<Habit> sorted) {
    final goodHabits = sorted.where((h) => h.type == 'good').toList();
    final badHabits = sorted.where((h) => h.type != 'good').toList();
    final splitSections = goodHabits.isNotEmpty && badHabits.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      // AlwaysScrollable: потягивание для RefreshIndicator работает даже
      // при коротком списке — иначе жест «хватается» только у самого
      // края и при отпускании список дёргается.
      physics: const AlwaysScrollableScrollPhysics(),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        // Ключ меняется при каждом закрепе/открепе: список плавно
        // «перетекает» в новую раскладку, а не прыгает позициями.
        child: KeyedSubtree(
          key: ValueKey('pin_rev_$_pinRev'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_perfectionismMode) _buildPerfectionismStrip(context, theme),
              splitSections
                  ? _buildSectionedList(
                      context,
                      theme,
                      sorted,
                      goodHabits,
                      badHabits,
                    )
                  : _buildFlatList(context, theme, sorted),
            ],
          ),
        ),
      ),
    );
  }

  /// Один ReorderableListView (только один тип привычек существует).
  Widget _buildFlatList(
    BuildContext context,
    ThemeData theme,
    List<Habit> habits,
  ) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // Бывший горизонтальный margin карточки перенесён сюда: item = карточка,
      // drag-proxy не выходит за края и не перекрывает обводку.
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: habits.length,
      // Плавная прокрутка при 4+ привычках: предзагрузка вне вьюпорта
      // и изоляция отрисовки каждой карточки от соседних.
      scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _service.reorder(oldIndex, newIndex),
      proxyDecorator: (child, index, animation) =>
          buildDragProxy(child, theme, animation),
      // Ключ на ВНЕШНЕМ виджете: ReorderableListView берёт key от него.
      // (KeyedSubtree внутри RepaintBoundary Flutter не видит — каждый
      // элемент списка превращался бы в ErrorWidget «Every item of
      // ReorderableListView must have a key».)
      itemBuilder: (context, i) => RepaintBoundary(
        key: ValueKey('item_habit_${habits[i].id}'),
        child: _buildHabitCard(context, theme, habits, _FlatIndexSource(i)),
      ),
    );
  }

  /// Две независимые секции с собственными ReorderableListView. Возвращаются
  /// в общем Column — пользователь видит один непрерывный список «Полезные»,
  /// затем — «Вредные». Reorder внутри секции переводится в глобальные
  /// индексы через [SectionIndexSource] и идёт в [HabitService.reorder].
  Widget _buildSectionedList(
    BuildContext context,
    ThemeData theme,
    List<Habit> sorted,
    List<Habit> goodHabits,
    List<Habit> badHabits,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, theme, 'habitsSectionGood', Colors.green),
        _sectionReorderable(
          context: context,
          theme: theme,
          habits: goodHabits,
          sorted: sorted,
        ),
        const SizedBox(height: 12),
        _sectionHeader(context, theme, 'habitsSectionBad', Colors.red),
        _sectionReorderable(
          context: context,
          theme: theme,
          habits: badHabits,
          sorted: sorted,
        ),
      ],
    );
  }

  Widget _sectionHeader(
    BuildContext context,
    ThemeData theme,
    String keyName,
    Color tint,
  ) {
    return Padding(
      // Выравнивание с карточками: их отступ теперь в padding списка (12).
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
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
  }

  /// Удобный мини-список (без скролла — внешний ListView владеет прокруткой),
  /// но с поддержкой drag-handle и onReorder, идентичной полному
  /// ReorderableListView. Используем встроенный [ReorderableListView]
  /// с [shrinkWrap: true] в обёртке, отключая собственный скролл.
  Widget _sectionReorderable({
    required BuildContext context,
    required ThemeData theme,
    required List<Habit> habits,
    required List<Habit> sorted,
  }) {
    if (habits.isEmpty) return const SizedBox.shrink();
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      buildDefaultDragHandles: false,
      itemCount: habits.length,
      scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
      proxyDecorator: (child, index, animation) =>
          buildDragProxy(child, theme, animation),
      onReorderItem: (oldLocal, newLocal) {
        // Локальный→Глобальный: просим сервис переставить элемент между
        // соответствующими глобальными позициями.
        final oldGlobal = sorted.indexOf(habits[oldLocal]);
        if (oldGlobal < 0) return;
        int newGlobal;
        if (newLocal >= habits.length) {
          newGlobal = sorted.indexOf(habits.last) + 1;
          if (newGlobal > sorted.length) newGlobal = sorted.length;
        } else {
          newGlobal = sorted.indexOf(habits[newLocal]);
          if (newGlobal < 0) newGlobal = oldGlobal;
        }
        if (newGlobal == oldGlobal) return;
        _service.reorder(oldGlobal, newGlobal);
      },
      // Ключ на ВНЕШНЕМ виджете: ReorderableListView берёт key от него.
      itemBuilder: (context, i) => RepaintBoundary(
        key: ValueKey('item_habit_${habits[i].id}'),
        child: _buildHabitCard(
          context,
          theme,
          habits,
          _SectionIndexSource(i, habits),
        ),
      ),
    );
  }

  DateTime? _lastHabitTap;

  Future<void> _tapHabitOnce(Habit habit) async {
    final now = DateTime.now();
    if (_lastHabitTap != null &&
        now.difference(_lastHabitTap!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastHabitTap = now;
    await _service.toggle(habit.id);
    if (!mounted) return;
    setState(() {});
  }

  /// Карточка привычки. Используется и в плоском списке (Flat),
  /// и в секционном (Section). Получает [source] — объект, который
  /// знает, какой использовать drag-handle (по i в общем списке
  /// для flat, по локальному i в списке секции для section).
  Widget _buildHabitCard(
    BuildContext context,
    ThemeData theme,
    List<Habit> habits,
    IndexSource source,
  ) {
    final habit = habits[source.localIndex(context, habits)];
    final dragIndex = source.dragIndex(context, habits);
    // RepaintBoundary изолирует карточку: при скролле список двигается
    // готовой текстурой, а не перерисовывает каждую карточку каждый кадр.
    final inner = SwipeToDelete(
      // Ключ теперь на внешнем StaggerIn (см. itemBuilder).
      // Ключ обязан быть уникальным в пределах всего поддерева,
      // поэтому используем сам id привычки — он одинаков для Flat и Section.
      dismissKey: ValueKey('dismiss_${habit.id}'),
      horizontalInset: 0,
      confirmDismiss: (direction) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(Translations.deleteOf(context)),
            content: Text('${habit.name}?'),
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
        return confirmed ?? false;
      },
      onDismissed: (_) => _service.remove(habit.id),
      child: SmoothHover(
        child: Card(
          key: ValueKey('card_${habit.id}'),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          // Горизонтальный отступ перенесён в padding списка — карточка
          // вплотную к item'у, обводка при драге её не перекрывает.
          margin: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              // Bigger hit-target (padding 6+8, icon 26) matches what works
              // in tasks/alarms screen — same Dismissible wrapper,
              // immediate drag works there, so we keep that here.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: habit.pinned
                    ? const Padding(
                        key: ValueKey('pin'),
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                        child: Icon(
                          Icons.push_pin,
                          size: 26,
                          color: Colors.grey,
                        ),
                      )
                    : _HabitDragHandle(
                        index: dragIndex,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 26,
                            color: Colors.grey,
                          ),
                        ),
                      ),
              ),
              // Чекбокс (сверху) + тип привычки (снизу).
              // Колонка уже (40) и значок крупнее (23) — иконка ближе
              // к драг-хэндлу слева, тексту — больше места.
              SizedBox(
                width: 40,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: EdgeInsets.zero,
                      // (scale 0.9) — «чуть выделяется», без мигания.
                      // Защита от двойного срабатывания — в _tapHabitOnce.
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tapHabitOnce(habit),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: habit.doneToday
                                ? theme.colorScheme.primary
                                : Colors.transparent,
                            border: Border.all(
                              color: habit.doneToday
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              width: 2,
                            ),
                          ),
                          child: habit.doneToday
                              ? const Icon(
                                  Icons.check,
                                  size: 23,
                                  color: Colors.white,
                                )
                              : Icon(
                                  habit.icon,
                                  size: 23,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // onTap: triple tap = reset streak (_handleHabitTap).
                  // onLongPress: hold 6s = pin/unpin habit.
                  // Drag-handle uses ReorderableDelayedDragStartListener
                  // (long-press first) so Dismissible horizontal
                  // swipe-to-delete on the Card stays unambiguous.
                  onTap: () => _handleHabitTap(habit),
                  onLongPress: () => _togglePin(habit),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 8, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row: name takes remaining width; compact actions on the right.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              // Плавное зачёркивание: линия «рисуется» по
                              // тексту при отметке и «стирается» при снятии
                              // (см. AnimatedStrikeText).
                              child: AnimatedStrikeText(
                                text: habit.name,
                                style: theme.textTheme.titleMedium!.copyWith(
                                  height: 1.25,
                                  color: theme.colorScheme.onSurface,
                                ),
                                // Тот же масштаб шрифта, что рендерит текст:
                                // иначе линии зачёркивания при системном
                                // масштабе ≠ 1.0 не совпадают со строками.
                                textScaler: MediaQuery.textScalerOf(context),
                                struck: habit.doneToday,
                                struckColor: theme.colorScheme.onSurfaceVariant,
                                strikeColor: theme.colorScheme.outline,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // Текст напоминания в списке НЕ показываем — только
                            // колокольчик времени ниже. Сам текст живёт в
                            // редактировании привычки и в самом уведомлении.
                            // Быстрое напоминание: маленький колокольчик в
                            // цвет темы, если у привычки задано «Вспомнить
                            // всё». Плотно прижат к кнопке разворота заметки.
                            if (habit.reminderTime != null)
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: Icon(
                                  Icons.notifications_active_outlined,
                                  size: 17,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            // Значок закрепления справа убран: пин и так виден
                            // слева (drag-handle превращается в пин у
                            // закреплённой привычки) — дублировать не нужно.
                            if (habit.notes.isNotEmpty ||
                                habit.status.isNotEmpty)
                              _compactIconButton(
                                icon: (_expandedNotes[habit.id] ?? false)
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: (_expandedNotes[habit.id] ?? false)
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                                onPressed: () => setState(
                                  () => _expandedNotes[habit.id] =
                                      !(_expandedNotes[habit.id] ?? false),
                                ),
                              ),
                            _compactIconButton(
                              icon: Icons.edit_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                              onPressed: () => _editHabit(habit),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Полезная → 7 точек стрика. Вредная → бейдж
                        // «Сегодня очищено» только при отметке; в остальных
                        // случаях — пусто. Стрик у вредной привычки НЕ
                        // показываем: человек НЕ «зарабатывает очки», борясь
                        // с пагубной привычкой, бейдж фиксирует сам факт
                        // победы над ней сегодня. Переключается AnimatedSwitcher
                        // для плавности.
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  alignment: Alignment.topCenter,
                                  child: child,
                                ),
                              ),
                          child: habit.type == 'good'
                              ? Padding(
                                  key: const ValueKey('streak_dots'),
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 2,
                                  ),
                                  child: Row(
                                    children: List.generate(7, (index) {
                                      // lastDoneDate == null → история пуста
                                      // (никогда не отмечалась или был сброс).
                                      // Осиротевший streak>0 без даты — артефакт
                                      // старой версии/импорта: точки не должны
                                      // «нарисоваться» из мёртвого счётчика.
                                      //
                                      // ВАЖНО: точки = streak БЕЗ вычитания.
                                      // Стрик-счётчик уже включает последний
                                      // завершённый день (он растёт в момент
                                      // отметки, а не в полночь). Раньше здесь
                                      // было `doneToday ? streak : streak - 1`,
                                      // и каждое утро до отметки левый кружок
                                      // «съедался» — при стрике 7 показывалось
                                      // 6, при стрике 1 не показывалось ничего,
                                      // хотя стрик не отменялся. Счётчик и точки
                                      // теперь всегда совпадают.
                                      final effectiveStreak =
                                          habit.lastDoneDate == null
                                          ? 0
                                          : habit.streak;
                                      final isDone =
                                          effectiveStreak > (6 - index);
                                      return AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 320,
                                        ),
                                        curve: Curves.easeOut,
                                        margin: const EdgeInsets.only(right: 6),
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isDone
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .surfaceContainerHighest,
                                        ),
                                      );
                                    }),
                                  ),
                                )
                              : habit.doneToday
                              ? Padding(
                                  key: const ValueKey('erased_badge'),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(20),
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Colors.red.shade400,
                                          Colors.deepOrange.shade400,
                                        ],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.shield_outlined,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          Translations.t(
                                            'todayErased',
                                            context,
                                            'Today cleared',
                                          ),
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: const ValueKey('streak_empty'),
                                ),
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          child:
                              (_expandedNotes[habit.id] ?? false) &&
                                  (habit.notes.isNotEmpty ||
                                      habit.status.isNotEmpty)
                              ? Padding(
                                  padding: const EdgeInsets.only(
                                    top: 6,
                                    bottom: 4,
                                  ),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (habit.status.isNotEmpty) ...[
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(
                                                Icons.lightbulb,
                                                size: 16,
                                                color:
                                                    theme.colorScheme.primary,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  habit.status,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: theme
                                                            .colorScheme
                                                            .onSurface,
                                                        height: 1.5,
                                                      ),
                                                  softWrap: true,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (habit.notes.isNotEmpty)
                                            const SizedBox(height: 8),
                                        ],
                                        if (habit.notes.isNotEmpty)
                                          Text(
                                            habit.notes,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurface,
                                                  height: 1.5,
                                                ),
                                            softWrap: true,
                                          ),
                                      ],
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        _daysRow(habit, theme, context),
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
    return inner;
  }

  /// Ряд дней недели: активные дни привычки подсвечены кружками.
  Widget _daysRow(Habit habit, ThemeData theme, BuildContext context) {
    if (habit.activeDays.isEmpty) return const SizedBox.shrink();
    final names = Translations.dayNames(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: List.generate(7, (i) {
          final day = i + 1;
          final active = habit.activeDays.contains(day);
          return Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? theme.colorScheme.primary.withValues(alpha: 0.14)
                  : Colors.transparent,
              border: Border.all(
                color: active
                    ? theme.colorScheme.primary.withValues(alpha: 0.55)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Text(
              names[i][0].toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 13,
                height: 1,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.55,
                      ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _compactIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: InkResponse(
        onTap: onPressed,
        radius: 18,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  /// Полоса перфекционизма: 4-6 карточек-напоминаний на сегодня.
  Widget _buildPerfectionismStrip(BuildContext context, ThemeData theme) {
    final plaques = _todaysPlaques();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 15,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  Translations.t('perfectionism', context),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: plaques.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final p = plaques[i];
                return SmoothHover(
                  hoverScale: 1.03,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _showPerfFullScreen(
                        Translations.t(p.bodyKey, context),
                        Translations.t(p.titleKey, context),
                        p.color,
                      ),
                      child: Container(
                        width: 160,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              p.color.withValues(alpha: 0.22),
                              p.color.withValues(alpha: 0.06),
                            ],
                          ),
                          border: Border.all(
                            color: p.color.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(p.icon, size: 22, color: p.color),
                            const SizedBox(height: 8),
                            Text(
                              Translations.t(p.titleKey, context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              Translations.t(p.shortKey, context),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.2,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
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
    );
  }

}

/// Drag-ручка карточки привычки: долгое нажатие начинает перетаскивание
/// в ReorderableListView (index — позиция в текущем списке).
class _HabitDragHandle extends StatelessWidget {
  final int index;
  final Widget child;
  const _HabitDragHandle({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return ReorderableDelayedDragStartListener(index: index, child: child);
  }
}

/// Абстракция «какой индекс использовать для карточки»: для плоского списка
/// локальный и drag-индекс совпадают; для секции это локальный индекс
/// внутри секции.
abstract class IndexSource {
  int localIndex(BuildContext context, List<Habit> habits);
  int dragIndex(BuildContext context, List<Habit> habits);
}

class _FlatIndexSource implements IndexSource {
  final int index;
  const _FlatIndexSource(this.index);

  @override
  int localIndex(BuildContext context, List<Habit> habits) => index;

  @override
  int dragIndex(BuildContext context, List<Habit> habits) => index;
}

class _SectionIndexSource implements IndexSource {
  final int index;
  final List<Habit> sectionHabits;
  const _SectionIndexSource(this.index, this.sectionHabits);

  @override
  int localIndex(BuildContext context, List<Habit> habits) => index;

  @override
  int dragIndex(BuildContext context, List<Habit> habits) {
    final habit = sectionHabits[index];
    final global = habits.indexOf(habit);
    return global < 0 ? index : global;
  }
}
