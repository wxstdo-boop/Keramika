import 'dart:async';
import 'dart:math';
import '../services/haptics.dart';
import 'package:flutter/material.dart';
import '../widgets/smooth_tooltip.dart' show BackButtonTooltip;

import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../models/habit.dart';
import '../services/habit_service.dart';
import '../services/settings_service.dart';
import '../l10n/translations.dart';
import '../widgets/swipe_to_delete.dart';
import '../widgets/press_splat.dart' show OrganicFab, PressSplat;
import '../widgets/press_scale.dart';
import '../utils/page_transitions.dart';
import '../utils/snackbar.dart';
import '../widgets/smooth_hover.dart';
import '../widgets/drag_proxy.dart';
import '../widgets/animated_strike_text.dart';
import '../widgets/ai_guide.dart';
import '../widgets/animated_fab_row.dart';
import '../widgets/premium_empty_state.dart';
import '../widgets/section_pill.dart'
    show kSectionPillSlotHeight, sectionCurrentIndex;
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
  /// Персональный notifier скролла раздела (см. AlarmsScreen).
  final ValueNotifier<double>? scrollOffset;

  /// Индекс этого раздела в PageView — ключ в sectionOffsetByPage.
  final int pillIndex;
  const HabitsScreen({super.key, this.scrollOffset, this.pillIndex = 0});

  @override
  State<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends State<HabitsScreen>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin,
        TickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;
  final _service = HabitService();
  // FAB-ряд прячется при прокрутке вниз и плавно возвращается у верха.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);
  final Map<String, bool> _expandedNotes = {};
  Timer? _dayTimer;
  bool _perfectionismMode = false;
  bool _perfScreenOpened = false;

  // Long-press on the habit body toggles the pinned state.

  /// Плавная смена раскладки при закрепе/открепе: список мягко гаснет,
  /// применяется новый порядок и список так же мягко проявляется —
  /// БЕЗ одновременного показа двух раскладок (из-за него привычка
  /// «двоилась» и казалось, что она чуть-чуть смещается).
  late final AnimationController _pinFade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  /// Направление сдвига при появлении: +1 — список «поднимается» (закреп),
  /// -1 — «опускается» (откреп).
  double _pinDir = 1;

  /// Идёт анимация закрепа/открепа — второй тап не принимаем.
  bool _pinBusy = false;

  // Triple tap on habit card = smooth streak reset.
  // 3 taps within 600ms window on the same habit trigger update().
  // _lastResetAt provides a 1500ms cooldown so spam-tapping doesn't
  // fire multiple resets in a row.
  int _tapCount = 0;
  DateTime? _lastTapTime;
  String? _tappedHabitId;
  // Per-habit cooldown: 1500ms after reset, only blocks the SAME habit.
  final Map<String, DateTime> _lastResetByHabit = <String, DateTime>{};

  // Данные ещё не загружены: показываем пустоту вместо кросс-фейда
  // «пусто → список», который при старте выглядел как мигание после
  // сплэша.
  bool _loaded = false;

  // Контроллер основного скроллера раздела — источник правды для офсета
  // таблетки разделов (см. _syncPillOffset в AlarmsScreen).
  final ScrollController _pillCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pillCtrl.addListener(_syncPillOffset);
    // Свежий контроллер стоит на 0 — карта офсетов могла держать высоту
    // ПРЕДЫДУЩЕЙ жизни вкладки (её State пересоздан). Без сброса таблетка
    // разделов оставалась спрятанной, пока пользователь не начнёт крутить.
    sectionOffsetByPage[widget.pillIndex] = 0.0;
    sectionCurrentIndex.addListener(_onCurrentSectionChanged);
    // Данные уже загружены в main() до первого кадра — показываем их
    // СРАЗУ, без ожидания повторного load() (иначе после Splash раздел
    // привычек мигает: кадр пустоты → резкое появление списка).
    // Повторный load() всё равно делаем в фоне: он дешёвый и подхватит
    // изменения, если кто-то ещё писал в файл.
    if (_service.isLoaded) {
      _loaded = true;
    }
    _service.load().then((_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    });
    // Значение уже синхронно загружено в main() до первого кадра — берём
    // его СРАЗУ, а не после асинхронной загрузки. Иначе полоса «борьба с
    // неидеальным» на первом кадре отсутствует и потом резко впрыгивает
    // поверх списка (мигание/рывок после сплэша).
    _perfectionismMode = SettingsService.perfectionismEnabled.value;
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
    // Вредная привычка не закрепляется: при зажатии ничего не происходит.
    if (habit.type == 'bad') return;
    // Пока идёт анимация перестановки — второй тап игнорируем: иначе
    // быстрые тапы складывали очередь обновлений и привычка «дёргалась».
    if (_pinBusy) return;
    _pinBusy = true;
    Haptics.medium();
    final willPin = !habit.pinned;
    // Направление «подъезда»: закреп — список идёт вверх, откреп — вниз.
    _pinDir = willPin ? 1 : -1;
    // 1) Мягко гасим текущую раскладку.
    await _pinFade.reverse();
    if (!mounted) {
      _pinBusy = false;
      return;
    }
    // 2) Применяем новый порядок …
    await _service.update(habit.copyWith(pinned: willPin));
    if (!mounted) {
      _pinBusy = false;
      return;
    }
    // 3) … и проявляем его в новом порядке.
    _pinFade.forward();
    _pinBusy = false;
    showBeautifulSnackBar(
      context,
      // Одна группа: закреп↔откреп при частых тапах плавно меняет ТЕКСТ
      // висящей плашки, а не плодит дублирующиеся снекбары.
      groupKey: 'habit_pin',
      message: willPin
          ? Translations.t('habitPinned', context, 'Habit pinned')
          : Translations.t('habitUnpinned', context, 'Habit unpinned'),
      icon: Icons.push_pin,
    );
  }

  /// Раздел стал активным — форсируем ресинк офсета таблетки.
  ///
  /// Keep-alive вкладка не присылает событий скролла, пока на ней ничего не
  /// двигают, а общий [sectionScrollOffset] мог остаться с устаревшей высотой
  /// другого раздела. Из-за этого таблетка разделов иногда исчезала при
  /// перезаходе и возвращалась только после первого ручного скролла.
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
    // Позиция на миг отваливается при пересборке страницы — не зная реальной
    // позиции, держим последнюю (настоящая приедет своим событием скролла).
    if (_pillCtrl.positions.length != 1) return;
    final v = _pillCtrl.offset;
    // В общий офсет пишет [reportSectionPillOffset] и только когда раздел
    // активен и карусель стоит ровно на нём: во время переезда высоту
    // таблетки ведёт Home интерполяцией между соседними разделами.
    reportSectionPillOffset(widget.pillIndex, v < 0 ? 0.0 : v);
  }

  @override
  void dispose() {
    _dayTimer?.cancel();
    sectionCurrentIndex.removeListener(_onCurrentSectionChanged);
    _pillCtrl.removeListener(_syncPillOffset);
    _pillCtrl.dispose();
    _fabVisible.dispose();
    _pinFade.dispose();
    SettingsService.perfectionismEnabled.removeListener(
      _onPerfectionismChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    _dragProxyY.dispose();
    super.dispose();
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
              backgroundColor: theme.colorScheme.surface,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
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
                  ),
                  // Летящая стая за плашкой — «как в уголке разработчика»:
                  // птицы спокойно скользят слева направо, машут вразнобой
                  // и мягко подпрыгивают на восходящих потоках. Клик не
                  // перехватывают, на производительность не давят: один
                  // репейт-контроллер под своим RepaintBoundary.
                  const Positioned.fill(
                    child: IgnorePointer(child: _PerfBirdFlock()),
                  ),
                  Column(
                    children: [
                      // Верхняя панель — во ВСЮ ширину (бока «допилены»):
                      // раньше карточка с отступами 12 слева и справа не
                      // доставала до краёв, и по бокам оставались щели, через
                      // которые проглядывали птицы — шапка выглядела
                      // обрубленной. Теперь она перекрывает всё, скруглены
                      // только нижние углы, а фон — ПОЛУПРОЗРАЧНОЕ стекло:
                      // стая мягко проходит под шапкой, а не за ней.
                      Container(
                        key: const ValueKey('perf_top_bar'),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color.lerp(
                                color,
                                Colors.black,
                                0.12,
                              )!.withValues(alpha: 0.88),
                              color.withValues(alpha: 0.80),
                              Color.lerp(
                                color,
                                Colors.white,
                                0.10,
                              )!.withValues(alpha: 0.74),
                            ],
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.30),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.fromLTRB(2, 4, 6, 12),
                        child: SafeArea(
                          bottom: false,
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                // Белый «Назад» на цветной шапке: стрелка
                                // перекрашена через IconTheme, тултип —
                                // штатный SmoothTooltip.
                                IconTheme.merge(
                                  data: const IconThemeData(
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  child: const BackButtonTooltip(),
                                ),
                                Expanded(
                                  child: Text(
                                    title,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                // Симметрия к кнопке «Назад» — заголовок
                                // остаётся ровно по центру шапки.
                                const SizedBox(width: 48),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                20,
                                24,
                              ),
                              decoration: BoxDecoration(
                                // Цитата на своей плашке «округлённый квадрат»:
                                // стеклянный вкладыш цвета темы + рама цвета
                                // плашки + мягкая тень в тон акцента.
                                borderRadius: BorderRadius.circular(18),
                                color: theme.colorScheme.surface.withValues(
                                  alpha: 0.66,
                                ),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.5),
                                  width: 1.3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.28),
                                    blurRadius: 26,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Верхняя панель плашки: мини-«квадратик» с
                                  // иконкой цитаты — задаёт ритм и перекликается
                                  // с обводкой карточки.
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: color.withValues(alpha: 0.16),
                                      border: Border.all(
                                        color: color.withValues(alpha: 0.45),
                                        width: 1.1,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.format_quote,
                                      size: 18,
                                      color: color,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    body,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                          height: 1.6,
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
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
    final rng = Random(_perfSeed());
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

  /// «Час» подборки перфекционизма: день + час. Меняется раз в час — по этому
  /// же числу анимируется смена карточек (кросс-фейд), поэтому подборка не
  /// «прыгает», а мягко перетекает в новую.
  int _perfSeed() {
    final now = DateTime.now();
    return now.year * 1000000 + now.month * 10000 + now.day * 100 + now.hour;
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
          final habits = _orderForDisplay(_service.habits);
          return Scaffold(
            // Без своего AppBar: белая полоса под таблеткой разделов убрана,
            // контент начинается сразу под ней.
            body: FabScrollListener(
              visible: sectionPillVisible,
              child: FabScrollListener(
                visible: _fabVisible,
                child: Column(
                  children: [
                    Expanded(
                      // Пока данные не загрузились — ничего не показываем
                      // (без кросс-фейда «пусто → список» на старте). Как
                      // только загрузились — список появляется сразу.
                      child: !_loaded
                          ? const SizedBox.shrink(
                              key: ValueKey('habits_loading'),
                            )
                          : habits.isNotEmpty
                          ? SizedBox.expand(
                              key: const ValueKey('list'),
                              child: _buildBody(context, theme, habits),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(
                                top: kSectionPillSlotHeight,
                              ),
                              child: _buildEmpty(context, theme),
                            ),
                    ),
                  ],
                ),
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
                  OrganicFab(
                    seed: 7.7,
                    onTap: () {
                      Haptics.light();
                      _addHabit();
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
      controller: _pillCtrl,
      padding: const EdgeInsets.fromLTRB(16, kSectionPillSlotHeight, 16, 0),
      // AlwaysScrollable: потягивание для RefreshIndicator работает даже
      // при коротком списке — иначе жест «хватается» только у самого
      // края и при отпускании список дёргается.
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          // Плавная смена раскладки при закрепе/открепе: контент мягко гаснет
          // (фейд + лёгкий «подъезд») и так же мягко проявляется уже в новом
          // порядке. Последовательно, а не двумя раскладками сразу —
          // никакого «двоения» привычки.
          AnimatedBuilder(
            animation: _pinFade,
            builder: (context, child) {
              final t = Curves.easeOutCubic.transform(_pinFade.value);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * 12 * _pinDir),
                  child: child,
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Полоса «борьбы с неидеальным» раскрывается плавно (и на
                // старте синхронно уже присутствует — без резкого впрыгива-
                // ния и мигания после сплэша).
                AnimatedSize(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _perfectionismMode
                      ? _buildPerfectionismStrip(context, theme)
                      : const SizedBox.shrink(),
                ),
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
        ],
      ),
    );
  }

  /// Закреплённые и незакреплённые — ФИЗИЧЕСКИ РАЗНЫЕ списки (два
  /// ReorderableListView в одном Column). Незакреплённую из нижнего списка
  /// в верхнюю (pinned) зону перетащить невозможно в принципе — это разные
  /// списки, drag-прокси не пересекает границу. Внутри каждой зоны порядок
  /// можно менять.
  Widget _buildFlatList(
    BuildContext context,
    ThemeData theme,
    List<Habit> habits,
  ) {
    final pinned = habits.where((h) => h.pinned).toList();
    final unpinned = habits.where((h) => !h.pinned).toList();

    Widget zoneList(
      List<Habit> list, {
      required int base,
      required String idPrefix,
    }) {
      if (list.isEmpty) return const SizedBox.shrink();
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Clip.none: перетаскиваемая карточка НЕ аппаратно обрезается по
        // границе своего списка — при выезде за границу зоны (например,
        // над строкой-заголовком секции или вверх в pinned-зону) прокси
        // проходит через неё плавно, без резкого исчезновения на границе.
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: list.length,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
        buildDefaultDragHandles: false,
        onReorderItem: (oldLocal, newLocal) {
          // Перевод локального индекса зоны в глобальный (base = сдвиг).
          // Reorder внутри зоны: не-pinned физически не могут попасть в
          // pinned-зону (отдельный список), guard в service — защита.
          final oldGlobal = base + oldLocal;
          final newGlobal = base + newLocal.clamp(0, list.length - 1);
          if (newGlobal == oldGlobal) return;
          _service.reorder(oldGlobal, newGlobal);
        },
        proxyDecorator: (child, index, animation) =>
            buildDragProxy(child, theme, animation),
        itemBuilder: (context, i) => RepaintBoundary(
          key: ValueKey('${idPrefix}_${list[i].id}'),
          child: _buildHabitCard(context, theme, list, _FlatIndexSource(i)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        zoneList(pinned, base: 0, idPrefix: 'item_habit_pinned'),
        if (pinned.isNotEmpty && unpinned.isNotEmpty) const SizedBox(height: 8),
        zoneList(unpinned, base: pinned.length, idPrefix: 'item_habit'),
      ],
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
    final row = Padding(
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
    // Плавное «расступание»: пока перетаскиваемая карточка проходит сквозь
    // заголовок, текст мягко уходит в прозрачность — карточка проходит
    // «сквозь» него, а не резко вытесняет. Вне драга (proxyY == null)
    // заголовок полностью непрозрачен.
    return ValueListenableBuilder<double?>(
      valueListenable: _dragProxyY,
      child: row,
      builder: (context, proxyY, child) {
        double opacity = 1.0;
        if (proxyY != null) {
          final box = context.findRenderObject() as RenderBox?;
          if (box != null && box.attached && box.hasSize) {
            final top = box.localToGlobal(Offset.zero).dy;
            // Центр карточки-прокси: её верх плюс ~60 (высота карточки).
            final proxyCenter = proxyY + 60;
            final dist = ((top + box.size.height / 2) - proxyCenter).abs();
            // Вплотную — почти прозрачно; дальше ~150 px — нормально.
            final proximity = (1 - (dist - 30) / 120)
                .clamp(0.0, 1.0)
                .toDouble();
            opacity = 1.0 - 0.82 * proximity;
          }
        }
        return AnimatedOpacity(
          opacity: opacity,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: child,
        );
      },
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
    // Физическое разделение pinned/unpinned: два отдельных списка,
    // незакреплённую нельзя перетащить в pinned-зону.
    final pinnedHabits = habits.where((h) => h.pinned).toList();
    final unpinnedHabits = habits.where((h) => !h.pinned).toList();
    final pBase = pinnedHabits.isNotEmpty
        ? sorted.indexOf(pinnedHabits.first)
        : 0;
    final uBase = unpinnedHabits.isNotEmpty
        ? sorted.indexOf(unpinnedHabits.first)
        : 0;

    Widget zone(List<Habit> list, int base, String prefix) {
      if (list.isEmpty) return const SizedBox.shrink();
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Clip.none: перетаскиваемая карточка НЕ аппаратно обрезается по
        // границе своего списка — при выезде за границу зоны (например,
        // над строкой-заголовком секции или вверх в pinned-зону) прокси
        // проходит через неё плавно, без резкого исчезновения на границе.
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: list.length,
        scrollCacheExtent: const ScrollCacheExtent.pixels(1500),
        buildDefaultDragHandles: false,
        onReorderItem: (oldLocal, newLocal) {
          final oldGlobal = base + oldLocal;
          final newGlobal = base + newLocal.clamp(0, list.length - 1);
          if (newGlobal == oldGlobal) return;
          _service.reorder(oldGlobal, newGlobal);
        },
        proxyDecorator: (child, index, animation) =>
            buildDragProxy(child, theme, animation, trackY: _dragProxyY),
        itemBuilder: (context, i) => RepaintBoundary(
          key: ValueKey('${prefix}_${list[i].id}'),
          child: _buildHabitCard(
            context,
            theme,
            list,
            _SectionIndexSource(i, list),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        zone(pinnedHabits, pBase, 'sec_pinned'),
        if (pinnedHabits.isNotEmpty && unpinnedHabits.isNotEmpty)
          const SizedBox(height: 8),
        zone(unpinnedHabits, uBase, 'sec_unpinned'),
      ],
    );
  }

  /// Глобальная Y-позиция drag-прокси (null — драга нет): заголовки секций
  /// мягко «расступаются», пока карточка проходит сквозь них.
  final ValueNotifier<double?> _dragProxyY = ValueNotifier<double?>(null);

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
        // «Вдавливание» при зажатии (меньше 1 — карточка мягко
        // уменьшается, как значки в таблетке), а не «вздутие».
        hoverScale: 0.98,
        duration: const Duration(milliseconds: 160),
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
              // Фиксированная ширина слота: при смене пин↔драг-хэндл текст
              // не сдвигается, а сам значок меняется кросс-фейдом + scale.
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Галка СВЕРХУ драг-хэндла (одна колонка 46px): текст
                    // получает всю оставшуюся ширину и умещается целиком.
                    Column(
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
                            // Чистая тематическая обводка большого значка
                            // (без IconRing — он сдвигал layout). Кольцо на
                            // самом кружке, без внешнего зазора.
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: habit.doneToday
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                // Красивая обводка: выбранная — primary (яркая),
                                // не выбранная — тематический outline (мягкий).
                                border: Border.all(
                                  color: habit.doneToday
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outline,
                                  width: 2,
                                ),
                              ),
                              // Плавная смена значка: привычка → галка с лёгким
                              // «попом» (fade + scale), а не резкий щелчок.
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
                                child: habit.doneToday
                                    ? const Icon(
                                        Icons.check,
                                        key: ValueKey('habit_done_check'),
                                        size: 23,
                                        color: Colors.white,
                                      )
                                    : Icon(
                                        habit.icon,
                                        key: const ValueKey('habit_icon'),
                                        size: 23,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Драг-хэндл / пин — снизу.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: habit.pinned
                          ? const Padding(
                              key: ValueKey('pin'),
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.push_pin,
                                size: 24,
                                color: Colors.grey,
                              ),
                            )
                          : _HabitDragHandle(
                              index: dragIndex,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  Icons.drag_indicator,
                                  size: 24,
                                  color: Colors.grey,
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
                    // Тот же ритм отступов, что в задачах (4,12,12,8):
                    // карточка привычек не «скукожена» относительно задач.
                    padding: const EdgeInsets.fromLTRB(4, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row: name takes remaining width; compact actions on the right.
                        // Кнопки действий фиксированной ширины — не давят на
                        // текст, имя привычки занимает всё оставшееся место.
                        // ВАЖНО: выравнивание ПО ВЕРХУ (start), а не по центру:
                        // центр вдоль двухстрочного названия уводил значки
                        // (увед/раскрытие/карандаш) к середине строки и
                        // оставлял пустые «карманы» справа на каждом ряду —
                        // текст выглядел скукоженным. Сверху текст и значки
                        // сажаются на одну линию, и текст дотягивается до
                        // правого края.
                        // IntrinsicHeight — чтобы значок «Вспомнить всё»
                        // мог встать по ЦЕНТРУ высоты блока действий. Высота
                        // блока разная (одна кнопка или две), поэтому жёсткий
                        // отступ не подошёл бы: при одном карандаше значок
                        // уезжал бы вниз.
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                // Плавное зачёркивание: линия «рисуется» по
                                // тексту при отметке и «стирается» при снятии
                                // (см. AnimatedStrikeText).
                                child: AnimatedStrikeText(
                                  text: habit.name,
                                  style: theme.textTheme.titleMedium!.copyWith(
                                    fontSize: 22.5,
                                    height: 1.3,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                  // Тот же масштаб шрифта, что рендерит текст:
                                  // иначе линии зачёркивания при системном
                                  // масштабе ≠ 1.0 не совпадают со строками.
                                  textScaler: MediaQuery.textScalerOf(context),
                                  struck: habit.doneToday,
                                  // Текст в отмеченном состоянии — заметно
                                  // полупрозрачный (а не просто другой оттенок):
                                  // прозрачность едет вместе с линией.
                                  struckColor: theme
                                      .colorScheme
                                      .onSurfaceVariant
                                      .withValues(alpha: 0.42),
                                  strikeColor: Colors.red.shade500.withValues(
                                    alpha: 0.9,
                                  ),
                                  // Полный текст без троеточия: имя привычки
                                  // всегда видно целиком (как в задачах), а не
                                  // «скукожено» до двух строк. Действия справа
                                  // (колокольчик/раскрытие/карандаш) стоят в своей
                                  // зоне, а текст расширяется на всю оставшуюся
                                  // ширину через Expanded — и не налезает на них.
                                  maxLines: null,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Текст напоминания в списке НЕ показываем — только
                              // колокольчик времени ниже. Сам текст живёт в
                              // редактировании привычки и в самом уведомлении.
                              // Быстрое напоминание: маленький колокольчик в
                              // цвет темы, если у привычки задано «Вспомнить
                              // всё». Плотно прижат к кнопке разворота заметки.
                              if (habit.reminderTime != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  // Значок «Вспомнить всё» опущен к СЕРЕДИНЕ
                                  // кластера: вместе с раскрытием (сверху) и
                                  // карандашом (снизу) три значка садятся на
                                  // окружность, а не сбиваются в левый верхний
                                  // угол. Center тянется на всю высоту блока
                                  // (её задаёт IntrinsicHeight выше).
                                  child: Center(
                                    // Кружок в тон соседних кнопок (карандаш и
                                    // раскрытие): та же полупрозрачная
                                    // подложка primaryContainer 0.18, поэтому
                                    // колокольчик читается частью кластера, а
                                    // не «голым» значком на карточке. Размер
                                    // 26 = 18 (иконка) + 4+4 (отступы), как у
                                    // _compactIconButton.
                                    child: Container(
                                      key: const ValueKey('remind_all_chip'),
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.colorScheme.primaryContainer
                                            .withValues(alpha: 0.18),
                                      ),
                                      child: Icon(
                                        Icons.notifications_active_outlined,
                                        size: 17,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              // Значок закрепления справа убран: пин и так виден
                              // слева (drag-handle превращается в пин у
                              // закреплённой привычки) — дублировать не нужно.
                              //
                              // Действия идут ВЕРТИКАЛЬНО (раскрытие СВЕРХУ,
                              // карандаш ПОД ним), а не в ряд. Раньше ряд из двух
                              // кнопок съедал ~54 px по ширине, и имя привычки
                              // «скукоживалось», не доходя до правого края —
                              // хотя место справа было. Теперь блок действий
                              // шириной в одну кнопку, и текст занимает почти
                              // всю ширину карточки.
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Кнопка раскрытия есть только если реально
                                  // есть что показывать: заметки — всегда;
                                  // статус — только у полезной привычки (у
                                  // вредной статус не отображается, поэтому и
                                  // кнопки нет).
                                  if (habit.notes.isNotEmpty ||
                                      (habit.type == 'good' &&
                                          habit.status.isNotEmpty))
                                    _compactIconButton(
                                      cornerRipple: true,
                                      icon: Icons.keyboard_arrow_down,
                                      rotation:
                                          (_expandedNotes[habit.id] ?? false)
                                          ? 3.14159 // пи — стрелка вверх
                                          : 0,
                                      color: (_expandedNotes[habit.id] ?? false)
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                      onPressed: () => setState(
                                        () => _expandedNotes[habit.id] =
                                            !(_expandedNotes[habit.id] ??
                                                false),
                                      ),
                                    ),
                                  const SizedBox(height: 2),
                                  _compactIconButton(
                                    icon: Icons.edit_outlined,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    onPressed: () => _editHabit(habit),
                                  ),
                                ],
                              ),
                            ],
                          ),
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
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    // «Красная» таблетка-победа: глубокий
                                    // винный градиент + светлая кромка,
                                    // плотный светлый текст. Без размытий
                                    // (MaskFilter/boxShadow) — только чистые
                                    // заливки, поэтому «серых квадратов» нет.
                                    child: Container(
                                      // «Сегодня очищено»: на тёмной теме —
                                      // тонкое виноградное стекло (мягкий
                                      // блик + полупрозрачная заливка), на
                                      // светлой — плотная винная таблетка.
                                      // Никаких размытий и теней.
                                      decoration: _erasedDecoration(theme),
                                      // Мелкие «кровавые» пятнышки: painter
                                      // ложится ПОВЕРХ заливки, но ПОД текстом —
                                      // буквы остаются чистыми.
                                      child: CustomPaint(
                                        painter: _BloodSpeckPainter(
                                          isDark:
                                              theme.brightness ==
                                              Brightness.dark,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 7,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons
                                                    .check_circle_outline_rounded,
                                                size: 16,
                                                color: Color(0xFFFFE1E3),
                                              ),
                                              const SizedBox(width: 7),
                                              Text(
                                                Translations.t(
                                                  'todayErased',
                                                  context,
                                                  'Сегодня очищено',
                                                ),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: const Color(
                                                        0xFFFFEEF0,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(
                                  key: ValueKey('streak_empty'),
                                ),
                        ),
                        // Раскрытие/закрытие заметки: высота и прозрачность
                        // едут ВМЕСТЕ по одной кривой (Align.heightFactor +
                        // Opacity), поэтому при закрытии панель не «исчезает
                        // мгновенно», а так же плавно сжимается и растворяется,
                        // как раскрывалась.
                        // 760 мс (было 480): вход и выход — одна мягкая волна
                        // (easeInOutCubic), без рывка в конце.
                        if (habit.notes.isNotEmpty ||
                            (habit.type == 'good' && habit.status.isNotEmpty))
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              // begin всегда 0: при первом построении закрытая
                              // панель не «проигрывает» открытие. Когда end
                              // меняется, твин стартует с ТЕКУЩЕГО значения —
                              // поэтому закрытие идёт из 1 в 0 так же гладко.
                              begin: 0.0,
                              end: (_expandedNotes[habit.id] ?? false)
                                  ? 1.0
                                  : 0.0,
                            ),
                            duration: const Duration(milliseconds: 760),
                            curve: Curves.easeInOutCubic,
                            builder: (context, t, child) => ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                // Высота сжимается вместе с прозрачностью:
                                // панель уезжает вверх, а не пропадает.
                                heightFactor: t,
                                child: Opacity(
                                  opacity: t,
                                  child: Transform.translate(
                                    offset: Offset(0, (1.0 - t) * -12),
                                    child: child,
                                  ),
                                ),
                              ),
                            ),
                            // Панель строится ВСЕГДА (пока есть контент): заметки
                            // — всегда; статус — только у полезной привычки
                            // (у вредной статус не рисуется).
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 4),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (habit.type == 'good' &&
                                        habit.status.isNotEmpty) ...[
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.lightbulb,
                                            size: 16,
                                            color: theme.colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              habit.status,
                                              style: theme.textTheme.bodyMedium
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
                                              color:
                                                  theme.colorScheme.onSurface,
                                              height: 1.5,
                                            ),
                                        softWrap: true,
                                      ),
                                  ],
                                ),
                              ),
                            ),
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

  /// Оформление таблетки «Сегодня очищено».
  ///
  /// Светлая тема: плотная винная таблетка (заливка чуть прозрачная, чтобы
  /// карточка мягко проглядывала). Тёмная тема: тонкое «виноградное стекло» —
  /// заметно прозрачнее, с мягким бликом в левом верхнем углу и тонкой светлой
  /// кромкой: на тёмном фоне плотный красный выглядел грязно и бил по глазам.
  BoxDecoration _erasedDecoration(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final colors = isDark
        ? [
            // Блик «стекла»: чуть ярче и прозрачнее основной заливки.
            const Color(0xFFE86A72).withValues(alpha: 0.22),
            const Color(0xFFA0101C).withValues(alpha: 0.34),
            const Color(0xFF5E0710).withValues(alpha: 0.30),
          ]
        : [
            const Color(0xFFC0202C).withValues(alpha: 0.66),
            const Color(0xFF96101B).withValues(alpha: 0.62),
            const Color(0xFF6E0810).withValues(alpha: 0.58),
          ];
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
        stops: const [0.0, 0.42, 1.0],
      ),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: (isDark ? const Color(0xFFFFA2A8) : const Color(0xFFE0525C))
            .withValues(alpha: isDark ? 0.26 : 0.45),
        width: 1.2,
      ),
    );
  }

  /// Ряд дней недели: активные дни привычки подсвечены компактными кружками.
  Widget _daysRow(Habit habit, ThemeData theme, BuildContext context) {
    if (habit.activeDays.isEmpty) return const SizedBox.shrink();
    final names = Translations.dayNames(context);
    final cs = theme.colorScheme;
    return Padding(
      // Компактнее (было 24 px кружки с шагом 5): ряд дней стал мельче и
      // «спокойнее» по цвету — не спорит с названием привычки.
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: List.generate(7, (i) {
          final day = i + 1;
          final active = habit.activeDays.contains(day);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(right: 3.5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? cs.primary.withValues(alpha: 0.16)
                  : cs.onSurfaceVariant.withValues(alpha: 0.045),
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.42)
                    : cs.outlineVariant.withValues(alpha: 0.22),
                width: active ? 1.1 : 0.8,
              ),
            ),
            child: Text(
              names[i][0].toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                height: 1,
                letterSpacing: 0,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.42),
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
    double rotation = 0,
    // true — угловая кнопка раскрытия заметки: кнопка компактная и на своём
    // месте, а поверх неё живёт фирменное пятно (только на тап, не на
    // зажатие — см. PressSplat.bloomOnRelease).
    bool cornerRipple = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    // Иконка + плавный поворот — общая для обеих кнопок.
    final rotatingIcon = AnimatedRotation(
      turns: rotation / 3.14159 / 2,
      // Медленнее (было 240 мс): стрелка переворачивается так же плавно, как
      // раскрывается заметка, — без «щелчка» в конце.
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeInOutCubic,
      child: Icon(icon, size: 18, color: color),
    );

    // Компактная кнопка (карандаш и подобные): без ink-«пятен» — при
    // удержании мягко уменьшается сама кнопка (та же отдача, что у карандаша
    // и корзины в окне задачи).
    if (!cornerRipple) {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: PressScale(
          pressedScale: 0.9,
          duration: const Duration(milliseconds: 460),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: rotatingIcon,
              ),
            ),
          ),
        ),
      );
    }

    // Угловая кнопка (раскрытие заметки): иконка компактная и на месте, а
    // поверх — фирменное размашистое пятно, которое расцветает ВМЕСТЕ с
    // раскрытием заметки и так же мягко растворяется.
    //
    // ВАЖНО: пока палец ДЕРЖИТ кнопку, пятна нет (bloomOnRelease) — под
    // пальцем видна только плавная отдача самой кнопки. Пятно появляется на
    // отпускании, одновременно с раскрытием заметки.
    return PressScale(
      pressedScale: 0.9,
      duration: const Duration(milliseconds: 460),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          Positioned(
            top: -16,
            right: -20,
            width: 76,
            height: 76,
            child: PressSplat(
              color: cs.primary,
              maxRadius: 42,
              alpha: 0.06,
              seed: 47.9,
              smeary: 0.85,
              // Вспышка — 900 мс, уход — 1300 мс: пятно раскрывается медленно,
              // а уходит ещё медленнее и ровнее (мягкое растворение, без
              // «сдувания» в последних кадрах).
              duration: const Duration(milliseconds: 900),
              exitDuration: const Duration(milliseconds: 1300),
              hitBox: const Size(84, 84),
              bloomOnRelease: true,
              onTap: onPressed,
              child: const SizedBox(width: 76, height: 76),
            ),
          ),
          IgnorePointer(
            child: Material(
              color: cs.primaryContainer.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.none,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: rotatingIcon,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Полоса перфекционизма: 4-6 карточек-напоминаний на сегодня.
  Widget _buildPerfectionismStrip(BuildContext context, ThemeData theme) {
    final plaques = _todaysPlaques();
    final seed = _perfSeed();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      // Полоса перфекционизма — своя «сцена»: мягкая подложка цвета темы,
      // скруглённые углы и летящая стая НА ФОНЕ (как канарейка в уголке
      // разработчика). Птицы живут под содержимым, клики не ловят.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.075),
                      theme.colorScheme.tertiary.withValues(alpha: 0.045),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                // Стая тикает только когда раздел привычек реально на
                // экране: на других вкладках PageView держит страницу
                // живой, и вечный repeat() жег кадры впустую.
                child: ValueListenableBuilder<int>(
                  valueListenable: sectionCurrentIndex,
                  builder: (context, idx, _) =>
                      _PerfBirdFlock(key: const ValueKey('perf_birds'), active: idx == 1),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
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
                  // Смена подборки (раз в час) — мягким кросс-фейдом: старые
                  // карточки растворяются, новые так же плавно приходят на их место.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 700),
                    switchInCurve: Curves.easeInOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: SizedBox(
                      key: ValueKey('perf_strip_$seed'),
                      // 122 (было 118): содержимое карточки (бейдж иконки,
                      // заголовок и две строки текста) не помещалось в
                      // прежнюю высоту — колонка переполнялась на ~2 px и
                      // под текстом появлялась полоса обрезки.
                      height: 122,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        itemCount: plaques.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final p = plaques[i];
                          return SmoothHover(
                            hoverScale: 1.025,
                            duration: const Duration(milliseconds: 280),
                            pressAlignment: Alignment.center,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                splashFactory: InkRipple.splashFactory,
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          color: p.color.withValues(
                                            alpha: 0.14,
                                          ),
                                          border: Border.all(
                                            color: p.color.withValues(
                                              alpha: 0.4,
                                            ),
                                            width: 1.1,
                                          ),
                                        ),
                                        child: Icon(
                                          p.icon,
                                          size: 20,
                                          color: p.color,
                                        ),
                                      ),
                                      const SizedBox(height: 7),
                                      Text(
                                        Translations.t(p.titleKey, context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  theme.colorScheme.onSurface,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        Translations.t(p.shortKey, context),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              height: 1.2,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
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

/// Мелкие «кровавые» пятнышки на таблетке «Сегодня очищено».
///
/// Пятна рисуются ПОД текстом (painter у CustomPaint), поэтому буквы
/// остаются чистыми, а заливка выглядит подтёкшей. Никаких размытий —
/// только чистые заливки, чтобы на Adreno не появлялись «серые квадраты».
class _BloodSpeckPainter extends CustomPainter {
  const _BloodSpeckPainter({this.isDark = false});

  /// На тёмной теме заливка тонкая и тёмная, поэтому пятнышки чуть плотнее
  /// и светлее — иначе они пропадали вовсе.
  final bool isDark;

  /// x, y (доли ширины/высоты), радиус (доля высоты), плотность (0..1).
  static const List<List<double>> _spots = [
    [0.05, 0.34, 0.15, 0.85],
    [0.13, 0.74, 0.09, 0.55],
    [0.22, 0.30, 0.07, 0.45],
    [0.33, 0.78, 0.11, 0.65],
    [0.44, 0.26, 0.06, 0.40],
    [0.55, 0.72, 0.08, 0.52],
    [0.66, 0.34, 0.07, 0.44],
    [0.76, 0.76, 0.12, 0.60],
    [0.86, 0.32, 0.06, 0.38],
    [0.95, 0.62, 0.09, 0.50],
  ];

  static const Color _dry = Color(0xFF3C0206);
  static const Color _wet = Color(0xFFFF8A90);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    for (final s in _spots) {
      final center = Offset(size.width * s[0], size.height * s[1]);
      final r = size.height * s[2];
      final density = s[3];
      final dryPaint = Paint()
        ..color = _dry.withValues(alpha: (isDark ? 0.52 : 0.34) * density);
      // Основное пятнышко.
      canvas.drawCircle(center, r, dryPaint);
      // Мазок рядом — пятно получается неровным, «живым».
      canvas.drawCircle(
        center + Offset(r * 1.6, r * 0.5),
        r * 0.52,
        Paint()
          ..color = _dry.withValues(alpha: (isDark ? 0.40 : 0.24) * density),
      );
      // Влажный блик — чуть светлее заливки.
      canvas.drawCircle(
        center - Offset(r * 0.35, r * 0.4),
        r * 0.32,
        Paint()
          ..color = _wet.withValues(alpha: (isDark ? 0.22 : 0.14) * density),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BloodSpeckPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Летящая стая для фуллскрина таблички перфекционизма.
///
/// Птицы — лёгкие росчерки: точка-тельце и две дуги-крыла, взмах по
/// синусу, у каждой свой темп, высота и фаза. Один репейт-контроллер
/// на цикл в 11 секунд, стая живёт под RepaintBoundary — остальной
/// экран не перерисовывается. Раскладка детерминирована (фиксированные
/// параметры), поэтому между открытиями стая не «перепрыгивает».
class _PerfBirdFlock extends StatefulWidget {
  /// Тикать ли стаю. На невидимой вкладке контроллер стоит — иначе
  /// постоянный repeat() держит кадры и греет телефон.
  final bool active;
  const _PerfBirdFlock({super.key, this.active = true});

  @override
  State<_PerfBirdFlock> createState() => _PerfBirdFlockState();
}

class _PerfBirdFlockState extends State<_PerfBirdFlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 11000),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _PerfBirdFlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _ctrl.repeat();
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // В светлом фоне — приглушённый цвет чернил, в тёмном — белёсые
    // птицы: в обоих темах стая читается, но не кричит.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.black.withValues(alpha: 0.24);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _BirdFlockPainter(t: _ctrl.value, color: ink),
        ),
      ),
    );
  }
}

/// Параметры одной птицы стаи: старт по горизонтали, высота, темп
/// дрейфа (доля ширины за цикл), амплитуда/частота покачивания,
/// масштаб размаха, частота взмаха и фазовый сдвиг — всё константой,
/// без Random: раскладка стабильна между запусками.
class _FlockBird {
  final double x0;
  final double y0;
  final double drift;
  final double bobAmp;
  final double bobHz;
  final double scale;
  final double flapHz;
  final double phase;

  const _FlockBird({
    required this.x0,
    required this.y0,
    required this.drift,
    required this.bobAmp,
    required this.bobHz,
    required this.scale,
    required this.flapHz,
    required this.phase,
  });
}

/// Кромки окна стаи: у самых краёв прозрачность падает до нуля, поэтому
/// птица НЕ сечётся обрезкой плашки, а мягко входит в окно и так же мягко
/// уходит. Константа публичная — на неё опирается регресс-тест.
const List<double> perfFlockEdgeStops = <double>[0.0, 0.10, 0.90, 1.0];

class _BirdFlockPainter extends CustomPainter {
  final double t;
  final Color color;

  const _BirdFlockPainter({required this.t, required this.color});

  static const _birds = <_FlockBird>[
    _FlockBird(
      x0: 0.02,
      y0: 0.30,
      drift: 0.12,
      bobAmp: 0.018,
      bobHz: 0.30,
      scale: 1.00,
      flapHz: 1.9,
      phase: 0.0,
    ),
    _FlockBird(
      x0: 0.30,
      y0: 0.17,
      drift: 0.15,
      bobAmp: 0.026,
      bobHz: 0.22,
      scale: 0.76,
      flapHz: 2.4,
      phase: 2.1,
    ),
    _FlockBird(
      x0: 0.55,
      y0: 0.25,
      drift: 0.13,
      bobAmp: 0.022,
      bobHz: 0.27,
      scale: 0.90,
      flapHz: 2.1,
      phase: 4.2,
    ),
    _FlockBird(
      x0: 0.74,
      y0: 0.12,
      drift: 0.11,
      bobAmp: 0.020,
      bobHz: 0.19,
      scale: 0.64,
      flapHz: 2.7,
      phase: 1.1,
    ),
    _FlockBird(
      x0: 0.16,
      y0: 0.38,
      drift: 0.16,
      bobAmp: 0.030,
      bobHz: 0.24,
      scale: 0.84,
      flapHz: 2.2,
      phase: 5.3,
    ),
  ];

  /// Плавная кромка стаи: у самых краёв окна птицы проявляются и гаснут, а
  /// не «секаются» обрезкой по границе. Раньше [ClipRRect] рубил птицу
  /// пополам — на входе/выходе из плашки это читалось как мигание. Теперь
  /// одна и та же прозрачность на краях работает и для крыльев (штрих), и
  /// для телец (заливка) — птица мягко «входит» в окно и так же мягко уходит.
  Shader _edgeFade(Size size) {
    final clear = color.withValues(alpha: 0);
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [clear, color, color, clear],
      stops: perfFlockEdgeStops,
    ).createShader(Offset.zero & size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fade = _edgeFade(size);
    final paint = Paint()
      ..shader = fade
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final bird in _birds) {
      // Горизонталь: дрейф с заворотом за край (чуть за границу, чтобы
      // появление/исчезание не секало глаз).
      final fx = ((bird.x0 + t * bird.drift) % 1.3) - 0.15;
      final px = fx * size.width;
      // Вертикаль: базовая высота + покачивание на «потоках».
      final fy =
          bird.y0 +
          bird.bobAmp * sin(2 * pi * (t * bird.bobHz + bird.phase * 0.31));
      final py = fy * size.height;

      final span = size.width * 0.020 * bird.scale;
      final lift = sin(2 * pi * (t * bird.flapHz + bird.phase * 1.7));

      paint.strokeWidth = (span * 0.18).clamp(1.4, 2.2);

      final path = Path()
        // Левое крыло: от тела нарисованной дугой к концу.
        ..moveTo(px, py)
        ..quadraticBezierTo(
          px - span * 0.45,
          py - lift * span * 0.45 - span * 0.18,
          px - span,
          py - lift * span * 0.75 - span * 0.28,
        )
        // Правое крыло — зеркально.
        ..moveTo(px, py)
        ..quadraticBezierTo(
          px + span * 0.45,
          py - lift * span * 0.45 - span * 0.18,
          px + span,
          py - lift * span * 0.75 - span * 0.28,
        );
      canvas.drawPath(path, paint);

      // Тельце: маленькая капля под центром взмаха.
      canvas.drawCircle(
        Offset(px, py + span * 0.06),
        span * 0.11,
        Paint()..shader = fade,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BirdFlockPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
