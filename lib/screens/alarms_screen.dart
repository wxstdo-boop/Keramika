import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/alarm.dart';
import '../models/app_timer.dart';
import '../models/wake_task.dart';
import '../services/alarm_service.dart';
import '../services/timer_service.dart';
import 'wake_task_screen.dart';
import '../services/settings_service.dart';
import '../main.dart';
import '../l10n/translations.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/volumetric_switch.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/drag_proxy.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/premium_empty_state.dart';
import 'add_alarm_screen.dart';
import 'add_timer_screen.dart';

class AlarmsScreen extends StatefulWidget {
  const AlarmsScreen({super.key});

  @override
  State<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends State<AlarmsScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = AlarmService();
  final _timerSvc = TimerService();
  // FAB-ряд прячется при прокрутке вниз и плавно возвращается у верха.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  @override
  void initState() {
    super.initState();
    _service.load();
    _timerSvc.load();
    SettingsService.loadExperimental();
    _timerSvc.onTimerDone = _onTimerDone;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SettingsService.loadExperimental();
    }
  }

  @override
  void dispose() {
    _timerSvc.onTimerDone = null;
    _fabVisible.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTimerDone(String id) {
    if (!mounted) return;
    final t = _timerSvc.timers.firstWhere(
      (t) => t.id == id,
      orElse: () => AppTimer(id: '', totalSeconds: 0),
    );
    // Вибрация при завершении таймера.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        Haptics.heavy();
      } catch (_) {}
    }
    notificationService.showInstant(
      70000 + id.hashCode % 10000,
      Translations.t('timers', context),
      '${t.displayLabel} — ${Translations.t('timerDone', context)}',
    );
    showBeautifulSnackBar(
      context,
      message: '${t.displayLabel} — ${Translations.t('timerDone', context)}',
    );
  }

  void _addAlarm() async {
    Haptics.light();
    if (_service.alarms.length >= 10) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxAlarms', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<Alarm>(slideUpRoute(const AddAlarmScreen()));
    if (result != null) {
      _service.add(result);
      if (result.enabled) {
        // Сначала мягкая проверка notifications. Если scheduleAlarm вернёт
        // false — значит нет exact-alarm permission; показываем снекбар
        // с action-кнопкой (не выкидываем в настройки автоматически).
        notificationService.requestPermissionsSoft();
        final ok = await notificationService.scheduleAlarm(result);
        if (!ok && mounted) {
          showBeautifulSnackBar(
            context,
            message: Translations.t('alarmNoExact', context),
            icon: Icons.warning_amber_outlined,
            iconColor: Colors.orange,
            actionLabel: Translations.t(
              'openSettings',
              context,
              'Открыть настройки',
            ),
            onAction: () => notificationService.requestPermissions(),
          );
        }
      }
    }
  }

  void _editAlarm(Alarm alarm) async {
    final result = await Navigator.of(
      context,
    ).push<Alarm>(slideUpRoute(AddAlarmScreen(existing: alarm)));
    if (result != null) {
      _service.update(result);
      await notificationService.cancelAlarm(result.id);
      if (result.enabled) {
        notificationService.requestPermissionsSoft();
        final ok = await notificationService.scheduleAlarm(result);
        if (!ok && mounted) {
          showBeautifulSnackBar(
            context,
            message: Translations.t('alarmNoExact', context),
            icon: Icons.warning_amber_outlined,
            iconColor: Colors.orange,
            actionLabel: Translations.t(
              'openSettings',
              context,
              'Открыть настройки',
            ),
            onAction: () => notificationService.requestPermissions(),
          );
        }
      }
    }
  }

  void _addTimer() async {
    if (_timerSvc.timers.length >= 5) {
      showBeautifulSnackBar(
        context,
        message: Translations.t('maxTimers', context),
        icon: Icons.warning_amber_outlined,
        iconColor: Colors.orange,
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push<AppTimer>(slideUpRoute(const AddTimerScreen()));
    if (result != null) _timerSvc.add(result);
  }

  void _editTimer(AppTimer timer) async {
    final result = await Navigator.of(
      context,
    ).push<AppTimer>(slideUpRoute(AddTimerScreen(existing: timer)));
    if (result != null) _timerSvc.update(result);
  }

  /// Запускает ТЕСТОВЫЙ будильник: сразу открывается экран пробуждения
  /// (математическая задача) со звуком по умолчанию, без планирования
  /// реального будильника. При закрытии звук плавно затухает, нативный
  /// будильниковый звук останавливается и alarm-уведомления чистятся
  /// (см. WakeTaskScreen._finish).
  void _testAlarm() {
    Haptics.light();
    Navigator.of(context).push(
      fadeRoute(
        WakeTaskScreen(
          taskType: WakeUpTask.math,
          isTest: true,
          soundName: 'Default',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        // Перезгружаем данные
        await _service.load();
        await _timerSvc.load();
        // Возвращаем Future, когда завершено
        return;
      },
      child: ListenableBuilder(
        listenable: Listenable.merge([
          _service,
          _timerSvc,
          SettingsService.experimentalEnabled,
        ]),
        builder: (context, _) {
          final alarms = _service.alarms;
          final timers = _timerSvc.timers;
          final hasAlarms = alarms.isNotEmpty;
          return Scaffold(
            appBar: AppBar(
              // Название раздела не показываем: оно дублирует таблетку
              // разделов над списком (пользователь просил убрать текст).
              centerTitle: true,
            ),
            body: FabScrollListener(
              visible: _fabVisible,
              child: Column(
                children: [
                  // Секция таймеров — по флагу «Экспериментальное» в настройках.
                  // Выключение тумблера только прячет секцию: сами таймеры
                  // остаются в хранилище и снова появляются при включении.
                  AnimatedSize(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeInOutCubic,
                    child: SettingsService.experimentalEnabled.value
                        ? _buildTimersSection(context, theme, timers)
                        : const SizedBox.shrink(),
                  ),
                  Expanded(
                    // Плавный кросс-фейд между списком и пустым состоянием:
                    // после удаления последнего будильника карточка-совет
                    // появляется, а не прыгает мгновенно.
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
                      child: hasAlarms
                          ? KeyedSubtree(
                              key: const ValueKey('alarms_list'),
                              child: _buildAlarmList(context, theme, alarms),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('alarms_empty'),
                              child: _buildAlarmEmpty(context, theme),
                            ),
                    ),
                  ),
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
                    // Долгое зажатие «плюса» открывает режим BERSERK.
                    child: GestureDetector(
                      onLongPress: () => showBerserkSheet(context),
                      child: FloatingActionButton(
                        onPressed: _addAlarm,
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

  Widget _buildAlarmEmpty(BuildContext context, ThemeData theme) {
    return PremiumEmptyState(
      icon: Icons.alarm_add_outlined,
      title: Translations.noAlarmsOf(context),
      hint: Translations.t('emptyAlarmHint', context),
      advice: Translations.t('emptyAlarmAdvice', context),
      actionLabel: Translations.t('newAlarm', context),
      accent: theme.colorScheme.primary,
      onPressed: _addAlarm,
    );
  }

  Widget _buildAlarmList(
    BuildContext context,
    ThemeData theme,
    List<Alarm> alarms,
  ) {
    // Горизонтальный отступ списка = бывший margin карточки: теперь
    // item занимает ровно ширину карточки, и drag-proxy (обводка + scale)
    // не выходит за боковые края при перетаскивании.
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: alarms.length,
      // Предзагрузка вне вьюпорта и изоляция отрисовки каждой карточки от
      // соседних — при прокрутке и драге список не «дёргается» на слабых
      // устройствах (Redmi Note 12).
      scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
      buildDefaultDragHandles: false,
      onReorderItem: (oldIndex, newIndex) =>
          _service.reorder(oldIndex, newIndex),
      proxyDecorator: (child, index, animation) =>
          buildDragProxy(child, theme, animation),
      itemBuilder: (context, i) {
        final alarm = alarms[i];
        return SwipeToDelete(
          // Ключ на ВНЕШНЕМ виджете: ReorderableListView берёт key от него.
          key: ValueKey('item_alarm_${alarm.id}'),
          dismissKey: ValueKey('dismiss_${alarm.id}'),
          horizontalInset: 0,
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(Translations.deleteOf(context)),
                content: Text(alarm.timeLabel),
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
          onDismissed: (_) {
            _service.remove(alarm.id);
            notificationService.cancelAlarm(alarm.id);
          },
          child: SmoothHover(
            child: Card(
              key: ValueKey('card_${alarm.id}'),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              // Небольшой зазор между будильниками (как у привычек):
              // без него карточки лежат вплотную, и при отпускании драга
              // список выглядит «склеенным», а места под палец нет.
              margin: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  // Drag handle слева — ReorderableDragStartListener включает
                  // перетаскивание (без него реордер не стартует).
                  ReorderableDragStartListener(
                    index: i,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 22,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  // Switch в левой колонке, как чекбокс в привычках
                  SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        VolumetricSwitch(
                          activeColor: Theme.of(context).colorScheme.primary,
                          value: alarm.enabled,
                          onChanged: (v) async {
                            final ctx = context;
                            _service.toggle(alarm.id);
                            final updated = _service.alarms.firstWhere(
                              (a) => a.id == alarm.id,
                            );
                            if (updated.enabled) {
                              notificationService.requestPermissionsSoft();
                              final noExactText = Translations.t(
                                'alarmNoExact',
                                ctx,
                              );
                              final ok = await notificationService
                                  .scheduleAlarm(updated);
                              if (!ok && mounted) {
                                showBeautifulSnackBar(
                                  ctx,
                                  message: noExactText,
                                  icon: Icons.warning_amber_outlined,
                                  iconColor: Colors.orange,
                                  actionLabel: Translations.t(
                                    'openSettings',
                                    ctx,
                                    'Открыть настройки',
                                  ),
                                  onAction: () =>
                                      notificationService.requestPermissions(),
                                );
                              }
                            } else {
                              notificationService.cancelAlarm(updated.id);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  // Основное содержимое
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _editAlarm(alarm),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Время и название будильника в центре;
                            // тестовый будильник — маленький значок только
                            // на ПЕРВОМ будильнике (не на всех карточках).
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    alarm.timeLabel,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                      color: alarm.enabled
                                          ? null
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                // Тестовый будильник — значок ТОЛЬКО на первом
                                // будильнике. При драге порядок меняется ЖИВО
                                // (onReorderItem), поэтому вместо резкого
                                // «телепорта» между карточками — плавный
                                // кроссфейд: старый значок тает, новый
                                // проявляется (карточки в этот момент уже
                                // скользят на свои места). Невидимая кнопка
                                // не ловит тапы (IgnorePointer).
                                IgnorePointer(
                                  ignoring: i != 0,
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 220,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      opacity: i == 0 ? 1.0 : 0.0,
                                      child: IconButton(
                                        onPressed: _testAlarm,
                                        tooltip: Translations.t(
                                          'testAlarm',
                                          context,
                                          'Тест будильника',
                                        ),
                                        icon: const Icon(
                                          Icons.notifications_active_outlined,
                                          size: 18,
                                        ),
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                        style: IconButton.styleFrom(
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Метка будильника (если есть)
                            if (alarm.label.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  alarm.label,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 20.5,
                                    color: theme.colorScheme.onSurface,
                                  ),
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
      },
    );
  }

  Widget _buildTimersSection(
    BuildContext context,
    ThemeData theme,
    List<AppTimer> timers,
  ) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Container(
        constraints: timers.isEmpty
            // Пустой таймер-секции нужно место под заголовок И текст
            // «Таймеров пока нет» — иначе текст переполняет контейнер
            // и «налезает» на будильники ниже при свайпе.
            ? const BoxConstraints(maxHeight: 120)
            // С таймерами секция растёт до 5 карточек (максимум)
            // и все они видны ЦЕЛИКОМ — не обрезаются и не «прилипают»
            // к будильникам снизу.
            : const BoxConstraints(maxHeight: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Text(
                    Translations.t('timers', context),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: FilledButton(
                      onPressed: _addTimer,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFFAB91),
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SizeTransition(
                  sizeFactor: anim,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
              ),
              child: timers.isEmpty
                  ? Padding(
                      key: const ValueKey('timers_empty'),
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
                      child: Text(
                        Translations.t('noTimers', context),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      key: const ValueKey('timers_list'),
                      shrinkWrap: true,
                      // На случай переполнения карточки прокручиваются
                      // ВНУТРИ секции, а не вылезают на будильники.
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      itemCount: timers.length,
                      itemBuilder: (context, i) {
                        final timer = timers[i];
                        final running = _timerSvc.isRunning(timer.id);
                        final rem = _timerSvc.remaining(timer.id);
                        return SwipeToDelete(
                          key: ValueKey('item_timer_${timer.id}'),
                          dismissKey: ValueKey('dismiss_${timer.id}'),
                          borderRadius: 16,
                          horizontalInset: 12,
                          confirmDismiss: (_) async => await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(Translations.deleteOf(context)),
                              content: Text(timer.displayLabel),
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
                          ),
                          onDismissed: (_) => _timerSvc.remove(timer.id),
                          child: Card(
                            key: ValueKey('card_${timer.id}'),
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () => _editTimer(timer),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              timer.displayLabel,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: running
                                                        ? theme
                                                              .colorScheme
                                                              .primary
                                                        : null,
                                                  ),
                                            ),
                                            if (timer.label.isNotEmpty)
                                              Text(
                                                timer.label,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      if (running || rem < timer.totalSeconds)
                                        // Живой счётчик: пока таймер идёт, цифры
                                        // мягко «дышат» (лёгкая пульсация) +
                                        // обновляются каждую секунду.
                                        _TimerPulse(
                                          active: running,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            child: ClipRect(
                                              // Каждая секунда счётчика
                                              // сменяется ПЛАВНО: цифры
                                              // «вкатываются» снизу/сверху
                                              // (fade + slide), а не
                                              // щёлкают резко.
                                              child: AnimatedSwitcher(
                                                duration: const Duration(
                                                  milliseconds: 320,
                                                ),
                                                switchInCurve:
                                                    Curves.easeOutCubic,
                                                switchOutCurve:
                                                    Curves.easeInCubic,
                                                transitionBuilder:
                                                    (child, animation) {
                                                      final t = Curves
                                                          .easeOutCubic
                                                          .transform(
                                                            animation.value,
                                                          );
                                                      return FadeTransition(
                                                        opacity: animation,
                                                        child:
                                                            Transform.translate(
                                                              offset: Offset(
                                                                0,
                                                                14 * (1 - t),
                                                              ),
                                                              child: child,
                                                            ),
                                                      );
                                                    },
                                                child: Text(
                                                  _timerSvc.remainingDisplay(
                                                    timer.id,
                                                  ),
                                                  key: ValueKey(
                                                    _timerSvc.remainingDisplay(
                                                      timer.id,
                                                    ),
                                                  ),
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontFeatures: const [
                                                          FontFeature.tabularFigures(),
                                                        ],
                                                        color: running
                                                            ? theme
                                                                  .colorScheme
                                                                  .primary
                                                            : theme
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                      ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (running)
                                        IconButton(
                                          iconSize: 28,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                          ),
                                          icon: Icon(
                                            Icons.pause_circle_filled,
                                            color: theme.colorScheme.primary,
                                          ),
                                          onPressed: () =>
                                              _timerSvc.pauseTimer(timer.id),
                                        )
                                      else
                                        IconButton(
                                          iconSize: 28,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                          ),
                                          icon: Icon(
                                            Icons.play_circle_fill,
                                            color: const Color(0xFFFFAB91),
                                          ),
                                          onPressed: () =>
                                              _timerSvc.startTimer(timer.id),
                                        ),
                                      if (rem < timer.totalSeconds && !running)
                                        IconButton(
                                          iconSize: 22,
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 36,
                                          ),
                                          icon: Icon(
                                            Icons.replay,
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          onPressed: () =>
                                              _timerSvc.resetTimer(timer.id),
                                        ),
                                    ],
                                  ),
                                ),
                                // Прогресс таймера: тонкая полоска на нижнем
                                // краю карточки плавно заполняется по мере
                                // отсчёта — у таймера появляется живая
                                // анимация, а не статичная цифра.
                                if (running || rem < timer.totalSeconds)
                                  LinearProgressIndicator(
                                    value: timer.totalSeconds > 0
                                        ? (timer.totalSeconds - rem) /
                                              timer.totalSeconds
                                        : 0,
                                    minHeight: 3,
                                    backgroundColor: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                    color: running
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.outline,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }



}

/// Лёгкая пульсация работающего таймера: цифры мягко «дышат»
/// (медленный цикл 1.4с, амплитуда ~4%) — живо, но ненавязчиво.
class _TimerPulse extends StatefulWidget {
  final bool active;
  final Widget child;

  const _TimerPulse({required this.active, required this.child});

  @override
  State<_TimerPulse> createState() => _TimerPulseState();
}

class _TimerPulseState extends State<_TimerPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.04,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 50,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.04,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 50,
    ),
  ]).animate(_ctrl);

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(_TimerPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.active && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
