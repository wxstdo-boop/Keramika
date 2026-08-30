import 'package:flutter/material.dart';

import '../services/haptics.dart';
import '../models/reality_check.dart';
import '../main.dart';
import '../services/reality_check_service.dart';
import '../services/habit_service.dart';
import '../services/task_service.dart';
import '../l10n/translations.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/rolling_number.dart';
import '../widgets/volumetric_switch.dart';
import '../widgets/manual_time_dialog.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/premium_empty_state.dart';
import 'add_reality_check_screen.dart';

class RealityChecksScreen extends StatefulWidget {
  final VoidCallback? onExit;
  const RealityChecksScreen({super.key, this.onExit});

  @override
  State<RealityChecksScreen> createState() => _RealityChecksScreenState();
}

class _RealityChecksScreenState extends State<RealityChecksScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = RealityCheckService();
  final _habitSvc = HabitService();
  final _taskSvc = TaskService();
  // FAB-ряд прячется при прокрутке вниз и плавно возвращается у верха.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  // Ключ для AnimatedList точных времён — чтобы анимация
  // добавления/удаления плашки работала плавно при каждом
  // изменении модели.
  final GlobalKey<AnimatedListState> _exactTimesKey =
      GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    _service.load().then((_) => _scheduleReminders());
    _habitSvc.load();
    _taskSvc.load();
  }

  /// Потянуть вниз — обновить: перечитываем данные с диска и заново
  /// планируем уведомления (система могла потерять их за время в фоне).
  Future<void> _onRefresh() async {
    try {
      await _service.load();
    } catch (_) {}
    _scheduleReminders();
  }

  void _scheduleReminders() {
    // Если пользователь выключил раздел РП целиком — снимаем все
    // уведомления, чтобы случайные напоминания не приходили.
    // (История проверок и галочки «Сегодня очищено» сохранятся.)
    if (!_service.enabled) {
      notificationService.cancelAllRealityChecks();
      return;
    }
    // Проверки планируются только если пользователь добавил свою проверку.
    // Если проверок нет — отменяем все уведомления РП, чтобы не приходили
    // случайные напоминания со встроенным текстом.
    if (_service.checks.isEmpty) {
      notificationService.cancelAllRealityChecks();
      return;
    }
    // Если сегодня уже выполнен лимит — не перепланируем, просто отменим.
    if (_shouldCancelNotificationsToday()) {
      notificationService.cancelAllRealityChecks();
      return;
    }
    // Сброс флага отмены, чтобы оставшиеся проверки могли запланироваться
    // после изменений (добавления/удаления/редактирования).
    notificationService.resetRcCancellation();
    // Используем расписание из сервиса — уважает time range И exact times.
    final schedule = _service.todaySchedule;
    final questions = _service.checks.map((c) => c.question).toList();
    notificationService.scheduleRealityChecks(
      schedule,
      questions,
      title: Translations.t('rcNotificationTitle', context, 'Reality Check'),
      cancelExisting: true,
    );
  }

  void _addCheck() async {
    Haptics.light();
    if (_service.checks.isNotEmpty) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxRc', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<RealityCheck>(slideUpRoute(const AddRealityCheckScreen()));
    if (result != null) {
      _service.add(result);
      _scheduleReminders();
    }
  }

  void _editCheck(RealityCheck check) async {
    final result = await Navigator.of(
      context,
    ).push<RealityCheck>(slideUpRoute(AddRealityCheckScreen(existing: check)));
    if (result != null) {
      _service.update(result);
      _scheduleReminders();
    }
  }

  DateTime? _lastCheckTap;

  void _doCheck(RealityCheck check) async {
    // Защита от двойного срабатывания: второй tap в течение 500 мс
    // игнорируется — значок не мигает туда-обратно.
    final now = DateTime.now();
    if (_lastCheckTap != null &&
        now.difference(_lastCheckTap!) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastCheckTap = now;
    // Приятный тактильный отклик на отметку проверки.
    Haptics.light();
    await _service.doCheck(check.id);
    final shouldCancel = _shouldCancelNotificationsToday();
    if (shouldCancel) {
      notificationService.cancelAllRealityChecks();
    }
    showBeautifulSnackBar(
      context,
      message: Translations.t('rcDone', context),
      duration: const Duration(seconds: 1),
    );
  }

  bool _shouldCancelNotificationsToday() {
    if (!notificationService.enabled || !notificationService.isInitialized)
      return false;
    return _service.notificationsDoneForToday;
  }

  /// Long-press на любую точку включённой секции → подтверждение → секция
  /// плавно сворачивается в OFF-таблетку (AnimatedSwitcher делает кросс-фейд
  /// благодаря ValueKey).
  String _fmtTimeOfDay(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  /// Открывает time-picker и добавляет новое точное время. Анимация
  /// вставки плашки в список делается через [AnimatedList.insertItem]
  /// ПОСЛЕ того, как модель уже отсортировала новое значение: так
  /// indexOf возвращает правильную позицию и AnimatedList не
  /// рассинхронизируется с источником.
  Future<void> _addExactTime() async {
    final picked = await showManualTimePicker(
      context,
      initial: TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    _service.addExactTime(picked);
    final newIdx = _service.exactTimes.indexOf(picked);
    if (newIdx >= 0) {
      _exactTimesKey.currentState?.insertItem(
        newIdx,
        duration: const Duration(milliseconds: 280),
      );
    }
    _scheduleReminders();
  }

  /// Удаляет точное время по индексу. Сначала запускает анимацию
  /// исчезновения плашки в [AnimatedList.removeItem], и только после
  /// её завершения синхронизирует модель — иначе AnimatedList уйдёт
  /// в невалидное состояние (itemBuilder запросит элемент, которого
  /// уже нет).
  void _removeExactTime(int index) {
    if (index < 0 || index >= _service.exactTimes.length) return;
    final removed = _service.exactTimes[index];
    _exactTimesKey.currentState?.removeItem(
      index,
      (context, animation) => SizeTransition(
        sizeFactor: animation,
        axis: Axis.horizontal,
        child: FadeTransition(
          opacity: animation,
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Chip(
              label: Text(_fmtTimeOfDay(removed)),
              deleteIcon: const Icon(Icons.close, size: 16),
            ),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 280),
    );
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _service.removeExactTime(index);
      _scheduleReminders();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _service,
      builder: (context, _) {
        final checks = _service.checks;
        final hasChecks = checks.isNotEmpty;
        // Используем CustomScrollView вместо SingleChildScrollView + Column
        // чтобы избежать двойной прокрутки и проблем рендеринга, когда
        // ListView внутри SingleChildScrollView пытается занять место.
        return Scaffold(
          appBar: AppBar(
            // Название раздела не показываем: оно дублирует таблетку
            // разделов над списком (пользователь просил убрать текст).
            centerTitle: true,
            leading: widget.onExit == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: Translations.backOf(context),
                    onPressed: widget.onExit,
                  ),
          ),
          // Плавный кросс-фейд: список ↔ пустое состояние (удаление
          // последней проверки больше не дёргает экран).
          body: FabScrollListener(
            visible: _fabVisible,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 0.985,
                    end: 1.0,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                child: CustomScrollView(
                  key: ValueKey(hasChecks ? 'rc_list' : 'rc_empty'),
                  // Потянуть вниз для обновления работает всегда — даже
                  // когда контента мало (раньше жест «не ловился»).
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (!hasChecks) ...[
                      // Пустой экран целиком находится в общем scroll-контенте:
                      // совет больше не делит ограниченное место с футером и не
                      // залезает под него на маленьких экранах.
                      SliverToBoxAdapter(
                        child: _buildSettingsCard(context, theme),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 8),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: _buildEmptyChildren(context, theme),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(child: _footer(context, theme)),
                    ] else ...[
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSettingsCard(context, theme),
                            ..._buildListChildren(context, theme, checks),
                          ],
                        ),
                      ),
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: _footer(context, theme),
                        ),
                      ),
                    ],
                  ],
                ),
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
                BerserkFabStack(
                  // Долгое зажатие «плюса» открывает режим BERSERK.
                  child: GestureDetector(
                    onLongPress: () => showBerserkSheet(context),
                    child: FloatingActionButton(
                      onPressed: _addCheck,
                      child: const Icon(Icons.add),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildListChildren(
    BuildContext context,
    ThemeData theme,
    List<RealityCheck> checks,
  ) {
    return [
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: checks.length,
        itemBuilder: (context, i) {
          final check = checks[i];
          return SwipeToDelete(
            key: ValueKey('item_rc_${check.id}'),
            dismissKey: ValueKey('dismiss_${check.id}'),
            confirmDismiss: (_) async {
              return await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(Translations.deleteOf(context)),
                  content: Text(check.question),
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
            onDismissed: (_) async {
              await _service.remove(check.id);
              _scheduleReminders();
            },
            child: SmoothHover(
              child: Card(
                key: ValueKey(check.id),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                  // Долгое зажатие карточки — редактирование (кнопка-
                  // карандаш справа убрана).
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => _editCheck(check),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Кружок-галка: внутри — ВЫБРАННЫЙ значок проверки
                            // (раньше был «пальчик»), при отметке — галочка.
                            // сжимается (scale 0.9) — без мигания.
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _doCheck(check),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: check.isDoneToday
                                      ? Colors.pink[300]
                                      : theme.colorScheme.primary.withValues(
                                          alpha: 0.12,
                                        ),
                                  border: Border.all(
                                    color: check.isDoneToday
                                        ? Colors.pink[300]!
                                        : theme.colorScheme.primary,
                                    width: 2,
                                  ),
                                ),
                                child: check.isDoneToday
                                    ? const Icon(
                                        Icons.check,
                                        size: 22,
                                        color: Colors.white,
                                      )
                                    : Icon(
                                        check.icon,
                                        size: 21,
                                        color: theme.colorScheme.primary,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                check.question,
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        // Футер "N Сделано" — цифра меняется ПЛАВНО (ролик).
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Счётчик СБРАСЫВАЕТСЯ каждый день: если последняя
                              // отметка была вчера, сегодня показываем 0.
                              // (раньше висело вчерашнее значение до первой
                              // отметки нового дня).
                              _AnimatedCount(
                                value:
                                    check.lastDoneDate ==
                                        RealityCheck.todayKey()
                                    ? check.doneToday
                                    : 0,
                                style:
                                    theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ) ??
                                    const TextStyle(),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                Translations.t('doneToday', context),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
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
            ),
          );
        },
      ),
    ];
  }

  List<Widget> _buildEmptyChildren(BuildContext context, ThemeData theme) {
    return [
      PremiumEmptyState(
        icon: Icons.visibility_outlined,
        title: Translations.noRealityChecksOf(context),
        hint: Translations.t('emptyRealityHint', context),
        advice: Translations.t('emptyRealityAdvice', context),
        actionLabel: Translations.t('newRc', context),
        accent: const Color(0xFF7B6BB2),
        onPressed: _addCheck,
      ),
    ];
  }

  Widget _buildSettingsCard(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.repeat,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translations.t('rcChecksPerDay', context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    tooltip: Translations.t('rcReset', context),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          title: Text(Translations.t('rcReset', context)),
                          content: Text(Translations.t('rcResetBody', context)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(Translations.cancelOf(context)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(
                                Translations.t('rcReset', context),
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        _service.resetAllStats();
                        _scheduleReminders();
                      }
                    },
                  ),
                ],
              ),
              Row(
                children: [
                  // Цифра меняется плавным роликом, а не «щёлкает».
                  _AnimatedCount(
                    value: _service.checksPerDay,
                    style:
                        theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w800,
                        ) ??
                        const TextStyle(),
                  ),
                  Expanded(
                    child: Slider(
                      // БЕЗ divisions: ползунок едет непрерывно и очень
                      // плавно (с делениями он «прыгал» по ступенькам).
                      value: _service.checksPerDay.toDouble(),
                      min: 5,
                      max: 15,
                      label: '${_service.checksPerDay}',
                      onChanged: (v) {
                        // Во время драга — только перерисовка (дёшево),
                        // без записи в JSON на каждый пиксель.
                        _service.setChecksPerDayPreview(v.round());
                      },
                      // Сохраняем и перепланируем уведомления только по
                      // окончании жеста — иначе слабый телефон «спотыкался».
                      onChangeEnd: (_) {
                        _service.setChecksPerDay(_service.checksPerDay);
                        _scheduleReminders();
                      },
                    ),
                  ),
                  Text(
                    '5–15',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              // Режим: рандом или точное время.
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Translations.t('timeMode', context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  VolumetricSwitch(
                    activeColor: theme.colorScheme.primary,
                    value: _service.useExactTimes,
                    onChanged: (v) {
                      _service.setUseExactTimes(v);
                      _scheduleReminders();
                    },
                  ),
                ],
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(
                    sizeFactor: anim,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
                child: _service.useExactTimes
                    ? Column(
                        key: const ValueKey('rc_exact_times'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          // Точные времена — горизонтальный AnimatedList
                          // с плавной вставкой/удалением каждой плашки.
                          SizedBox(
                            height: 38,
                            child: AnimatedList(
                              key: _exactTimesKey,
                              scrollDirection: Axis.horizontal,
                              initialItemCount: _service.exactTimes.length,
                              itemBuilder: (context, index, animation) {
                                final t = _service.exactTimes[index];
                                return SizeTransition(
                                  sizeFactor: animation,
                                  axis: Axis.horizontal,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Chip(
                                        label: Text(_fmtTimeOfDay(t)),
                                        deleteIcon: const Icon(
                                          Icons.close,
                                          size: 16,
                                        ),
                                        onDeleted: () =>
                                            _removeExactTime(index),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 6),
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(Translations.t('addTime', context)),
                            onPressed: _addExactTime,
                          ),
                        ],
                      )
                    : Column(
                        key: const ValueKey('rc_time_range'),
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(height: 16),
                          Row(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Translations.t('rcTimeRange', context),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _timeChip(
                                context,
                                theme,
                                label: Translations.t('rcFrom', context),
                                time: TimeOfDay(
                                  hour: _service.timeFromHour,
                                  minute: _service.timeFromMinute,
                                ),
                                onTap: () async {
                                  final picked = await showManualTimePicker(
                                    context,
                                    initial: TimeOfDay(
                                      hour: _service.timeFromHour,
                                      minute: _service.timeFromMinute,
                                    ),
                                  );
                                  if (picked != null) {
                                    _service.setTimeFrom(picked);
                                    _scheduleReminders();
                                  }
                                },
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              _timeChip(
                                context,
                                theme,
                                label: Translations.t('rcTo', context),
                                time: TimeOfDay(
                                  hour: _service.timeToHour,
                                  minute: _service.timeToMinute,
                                ),
                                onTap: () async {
                                  final picked = await showManualTimePicker(
                                    context,
                                    initial: TimeOfDay(
                                      hour: _service.timeToHour,
                                      minute: _service.timeToMinute,
                                    ),
                                  );
                                  if (picked != null) {
                                    _service.setTimeTo(picked);
                                    _scheduleReminders();
                                  }
                                },
                              ),
                              const Spacer(),
                              if (_service.todaySchedule.isNotEmpty)
                                Text(
                                  '${_service.todaySchedule.length} ${Translations.t('rcScheduled', context)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: _service.todaySchedule.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: SizedBox(
                                      height: 32,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        itemCount:
                                            _service.todaySchedule.length,
                                        separatorBuilder: (_, si) =>
                                            const SizedBox(width: 6),
                                        itemBuilder: (_, i) {
                                          final t = _service.todaySchedule[i];
                                          final now = TimeOfDay.now();
                                          final isPast =
                                              t.hour * 60 + t.minute <=
                                              now.hour * 60 + now.minute;
                                          return AnimatedOpacity(
                                            duration: const Duration(
                                              milliseconds: 400,
                                            ),
                                            opacity: isPast ? 0.5 : 1.0,
                                            child: AnimatedScale(
                                              duration: const Duration(
                                                milliseconds: 300,
                                              ),
                                              scale: isPast ? 0.9 : 1.0,
                                              child: Chip(
                                                labelPadding: EdgeInsets.zero,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                label: Text(
                                                  _fmtTimeOfDay(t),
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: isPast
                                                            ? theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant
                                                            : theme
                                                                  .colorScheme
                                                                  .onPrimary,
                                                        fontWeight: isPast
                                                            ? null
                                                            : FontWeight.bold,
                                                      ),
                                                ),
                                                backgroundColor: isPast
                                                    ? theme
                                                          .colorScheme
                                                          .surfaceContainerHighest
                                                    : theme.colorScheme.primary,
                                                side: BorderSide.none,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                    ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ], // close Column2 children list
                      ), // close Column2 constructor
              ), // close AnimatedSwitcher
            ], // close parent Column children list
          ),
        ),
      ),
    );
  }

  Widget _timeChip(
    BuildContext context,
    ThemeData theme, {
    required String label,
    required TimeOfDay time,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            // Время меняется плавно (fade + лёгкий сдвиг), а не прыгает.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.25),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                _fmtTimeOfDay(time),
                key: ValueKey('${time.hour}:${time.minute}'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Translations.madeWithLoveOf(context),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.6,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.favorite, size: 14, color: Colors.pink[300]),
          ],
        ),
      ),
    );
  }
}

/// Плавная смена числа (ролик): при изменении значения цифра въезжает
/// сверху/снизу вместо мгновенного «щёлка». Переиспользует RollingNumber.
class _AnimatedCount extends StatefulWidget {
  final int value;
  final TextStyle style;
  const _AnimatedCount({required this.value, required this.style});

  @override
  State<_AnimatedCount> createState() => _AnimatedCountState();
}

class _AnimatedCountState extends State<_AnimatedCount> {
  int _prev = 0;

  @override
  void initState() {
    super.initState();
    _prev = widget.value;
  }

  @override
  void didUpdateWidget(covariant _AnimatedCount oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _prev = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    return RollingNumber(
      value: '${widget.value}',
      delta: (widget.value - _prev).sign,
      style: widget.style,
      padding: EdgeInsets.zero,
      duration: const Duration(milliseconds: 180),
    );
  }
}
