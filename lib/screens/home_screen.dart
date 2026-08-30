import 'dart:math';

import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
import '../widgets/smooth_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/physics.dart';
import 'alarms_screen.dart';
import 'habits_screen.dart';
import 'reality_checks_screen.dart';
import '../services/reality_check_service.dart';
import 'tasks_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'nutrition_screen.dart';
import '../main.dart';
import '../l10n/translations.dart';
import '../utils/android_settings.dart';
import '../services/prefs.dart';
import '../utils/page_transitions.dart';
import '../widgets/animated_blur_title.dart';
import '../widgets/animated_fab_row.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ValueNotifier вместо setState: смена страницы обновляет ТОЛЬКО чипы,
  // а не весь home (при быстром свайпе «первый → последний» раньше было
  // 2–3 полных пересборки home за свайп — отсюда подлагивания).
  late final ValueNotifier<int> _currentIndex;
  late final ValueNotifier<double> _railPage;
  late final PageController _pageController;
  late final AnimationController _animCtrl;
  // Ленивый прогрев вкладок: первый кадр Home строит только текущую и
  // соседнюю вкладки, остальные достраиваются через полсекунды в фоне.
  // Раньше все 4 раздела (со списками и их каскадными анимациями)
  // строились в ОДНОМ кадре — на слабых телефонах вход в приложение
  // «подтормаживал» именно в момент перехода сплэш → главная.
  bool _cacheWarmed = false;
  double _dragVelocity = 0.0;
  bool _animating = false;
  bool _dragActive = false;
  double _dragAccY = 0.0;

  static const _icons = [
    Icons.alarm_outlined,
    Icons.auto_awesome_outlined,
    Icons.checklist_outlined,
    Icons.psychology_outlined,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Запускаемся в том разделе, где пользователь был в прошлый раз.
    final savedTab = (globalPrefs.getInt('last_home_tab') ?? 0).clamp(0, 3);
    _currentIndex = ValueNotifier<int>(savedTab);
    _railPage = ValueNotifier<double>(savedTab.toDouble());
    _pageController = PageController(initialPage: savedTab)
      ..addListener(_onPageScroll);
    // AnimationController используется как Value<double> — без setState!
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 0.0,
    );
    // РП-тумблер живёт в ChangeNotifier — слушаем его, чтобы вкладка
    // появлялась/исчезала СРАЗУ при переключении в настройках.
    RealityCheckService().addListener(_onRcChanged);
    _showWelcomeOnce();
    // Первый кадр — только видимые вкладки; через полсекунды расширяем
    // кэш до всех четырёх, чтобы дальние свайпы оставались плавными.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _cacheWarmed = true);
      });
    });
  }

  void _onRcChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealityCheckService().removeListener(_onRcChanged);
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _animCtrl.dispose();
    _railPage.dispose();
    _currentIndex.dispose();
    super.dispose();
  }

  // «Двоение» содержимого в недавных: когда приложение сворачивается
  // посреди анимации (переход между вкладками PageView 180–420 мс или
  // пружина натяжения), MIUI снимает снапшот в этот момент — в кадр
  // попадают сразу две страницы/два состояния, и карточка выглядит
  // «двоящейся». При уходе в фон мгновенно доводим анимации до конца:
  // снапшот всегда получает чистый, устоявшийся кадр одной страницы.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Останавливаем незавершённый переход между вкладками и встаём
      // ровно на текущую страницу (ту, что уже выбрана чипами).
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex.value);
      }
      // Пружину натяжения доводим до нуля мгновенно — контент не
      // «зависает» сдвинутым/уменьшенным в снапшоте недавных.
      _animCtrl.value = 0.0;
      _animating = false;
      _dragActive = false;
      _dragAccY = 0.0;
    }
  }

  void _showWelcomeOnce() async {
    // defaultTargetPlatform не бросает на web (в отличие от dart:io Platform).
    // Web не показывает Android-специфичное приветствие.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final dismissed = globalPrefs.getBool('welcome_dismissed') ?? false;
    if (dismissed || !mounted) return;
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.notifications_active_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(Translations.welcomeTitleOf(context)),
        content: Text(Translations.welcomeBodyOf(context)),
        actions: [
          TextButton(
            onPressed: () async {
              await globalPrefs.setBool('welcome_dismissed', true);
              if (mounted) Navigator.pop(ctx);
            },
            child: Text(Translations.t('dontShowAgain', context)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.welcomeSkipOf(context)),
          ),
          FilledButton(
            onPressed: () async {
              await globalPrefs.setBool('welcome_dismissed', true);
              if (mounted) {
                Navigator.pop(ctx);
                Navigator.of(
                  context,
                ).push(slideSideRoute(const SettingsScreen()));
              }
            },
            child: Text(Translations.welcomeGoOf(context)),
          ),
        ],
      ),
    ).then((_) => _showPopupWarning());
  }

  void _showPopupWarning() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final shown = globalPrefs.getBool('popup_warning_shown') ?? false;
    if (shown || !mounted) return;
    await globalPrefs.setBool('popup_warning_shown', true);
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber, size: 48, color: Colors.orange),
        title: Text(Translations.t('popupWarningTitle', context)),
        content: Text(Translations.t('popupWarningBody', context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(Translations.t('popupWarningDismiss', context)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openFullScreenNotifSettings();
            },
            child: Text(Translations.t('popupWarningOpen', context)),
          ),
        ],
      ),
    );
  }

  void _onPageScroll() {
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    final page = _pageController.page;
    if (page != null && page.isFinite &&
        (_railPage.value - page).abs() > 0.001) {
      _railPage.value = page;
    }
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
    // НЕ дёргаем индикатор к цели: он и так непрерывно следует за page
    // через _onPageScroll. Раньше onPageChanged срабатывал при пересечении
    // каждой границы во время animateToPage и телепортировал таблетку
    // обратно к целочисленному индексу посреди перелёта — отсюда «дёрганье».
    globalPrefs.setInt('last_home_tab', index);
  }

  void _onTabTap(int index) {
    final fromPage = _pageController.hasClients
        ? (_pageController.page ?? _currentIndex.value.toDouble())
        : _currentIndex.value.toDouble();
    final distance = (index - fromPage).abs();
    if (distance < 0.01) return;
    Haptics.select();
    // Индикатор не перескакивает к цели: он продолжает следовать page
    // напрямую, пока PageView доезжает до выбранного раздела.
    // Отменяем незавершённый переход перед новым: иначе несколько быстрых
    // тапов складывали очереди animateToPage и таблетка дёргалась.
    _pageController.jumpTo(_pageController.position.pixels);
    _currentIndex.value = index;
    _pageController.animateToPage(
      index,
      duration: Duration(
        milliseconds: (300 + distance.round() * 70).clamp(300, 500),
      ),
      curve: Curves.easeInOutCubic,
    );
  }

  void _snapBack() {
    if (_animating) return;
    _animating = true;
    // Мягкая пружина с лёгким bounce — приятный отскок при отпускании.
    // stiffness: 28 — достаточно мягко, damping: 8 — позволяет один-два подскока.
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 28.0, damping: 8.0),
      _animCtrl.value,
      0.0,
      _dragVelocity * 80,
    );
    _animCtrl.animateWith(simulation).then((_) => _animating = false);
  }

  void _finishDrag() {
    if (!_dragActive) return;
    _dragActive = false;
    final dy = _dragAccY;
    _dragAccY = 0.0;
    // Вертикальный свайп на области разделов переключает табы:
    // вверх — следующий раздел, вниз — предыдущий.
    final rcOn = RealityCheckService().enabled;
    final tabCount = 3 + (rcOn ? 1 : 0);
    if (dy < -40.0) {
      final next = (_currentIndex.value + 1).clamp(0, tabCount - 1);
      if (next != _currentIndex.value) {
        Haptics.medium();
        _onTabTap(next);
      }
    } else if (dy > 40.0) {
      final prev = (_currentIndex.value - 1).clamp(0, tabCount - 1);
      if (prev != _currentIndex.value) {
        Haptics.medium();
        _onTabTap(prev);
      }
    } else {
      Haptics.light();
    }
    _snapBack();
  }

  @override
  Widget build(BuildContext context) {
    final rcSvc = RealityCheckService();
    final rcOn = rcSvc.enabled;
    // When user disables Reality Checks in Settings, the 'Rb' tile is
    // hidden from Home -- both the top chip and the PageView entry.
    final tabs = <String>[
      Translations.alarmsOf(context),
      Translations.habitsOf(context),
      Translations.tasksOf(context),
      if (rcOn) Translations.rcOf(context),
    ];

    // If user is on the 'Rb' tab and toggles it off in Settings (so the
    // tab list shrinks from 4 to 3), the underlying PageController
    // silently clamps the page index but _currentIndex stays stale.
    // Schedule a redirect after the current build so the chip-row and
    // PageView stay in sync.
    if (_currentIndex.value >= tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pageController.jumpToPage(0);
          _currentIndex.value = 0;
        }
      });
    }

    final screens = <Widget>[
      // RepaintBoundary изолирует перерисовку вкладок: свайп/анимация на
      // одной вкладке не перерисовывает остальные (меньше работы на GPU).
      const RepaintBoundary(child: AlarmsScreen()),
      const RepaintBoundary(child: HabitsScreen()),
      const RepaintBoundary(child: TasksScreen()),
      if (rcOn)
        RepaintBoundary(child: RealityChecksScreen(onExit: () => _onTabTap(0))),
    ];

    // Скругляем ВСЕ углы главного экрана (не только глобальным ClipRRect
    // на корне): на MIUI статус-бар остаётся отдельной чёрной полосой, и
    // при оттягивании крайних разделов (Будильники/РП) квадратные верхние
    // углы AppBar/подложки выглядели незакруглёнными. Скруглённый Scaffold
    // даёт аккуратную дугу во всех углах — и при обычном виде, и при
    // оттягивании полосы.
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Scaffold(
      // НЕ уменьшать экран при появлении клавиатуры: иначе при открытом
      // ИИ-чате (bottom sheet) весь экран под ним пересчитывает layout на
      // каждом кадре подъёма/опускания IME — чат «тормозил». Клавиатуру
      // обслуживает сам лист (bodyInsets), фону ресайз не нужен.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.refresh_outlined),
          tooltip: '${Translations.refreshOf(context)} (save files + restart)',
          onPressed: () => KeramikaApp.of(context).refreshApp(),
        ),
        title: const AnimatedBlurTitle(),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RealityCheckStatsScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const NutritionScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(slideSideRoute(const SettingsScreen())),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Фоновая «skin» подложка. Проявляется при натяжении экрана вниз —
          // между верхним AppBar и едущим вниз блоком разделов появляется
          // естественный «зазор», который и создаёт эффект «экран тянется».
          Positioned.fill(
            child: Container(color: Theme.of(context).scaffoldBackgroundColor),
          ),

          // Один AnimatedBuilder на ВЕСЬ body-блок (chips + ручка + PageView).
          // Когда палец тянет вниз за chips/ручку — едет не только контент,
          // а весь «экран разделов» целиком: закругляется, получает тень,
          // слегка сжимается и тускнеет, а сверху проступает skin.
          AnimatedBuilder(
            animation: _animCtrl,
            child: Column(
              children: [
                // Жест натяжения — ловится из области чипов + невидимой ручки
                // под ними. NotificationListener НЕ работает на Android: там
                // ClampingScrollPhysics и нет overscroll. Поэтому жест только
                // через GestureDetector на чипах.
                // Таблетка разделов вместе с белым фоном плавно сворачивается
                // вверх при прокрутке вниз (как кнопки «плюс» и Ада) и
                // возвращается при долистывании до верха.
                ValueListenableBuilder<bool>(
                  valueListenable: sectionPillVisible,
                  builder: (context, pillOn, _) => AnimatedSlide(
                    offset: pillOn ? Offset.zero : const Offset(0, -1.4),
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: pillOn ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      child: IgnorePointer(
                        ignoring: !pillOn,
                        child: GestureDetector(
                          // Вертикальный свайп над областью чипов переключает табы.
                          // Горизонтальная прокрутка чипов остаётся у SingleChildScrollView.
                          onVerticalDragStart: (_) {
                            _dragActive = true;
                            _dragAccY = 0.0;
                            _animCtrl.stop();
                            _animCtrl.value = 0.0;
                          },
                          onVerticalDragUpdate: (details) {
                            _dragAccY += details.delta.dy;
                            // Натяжение используется только как лёгкая отдача;
                            // горизонтальное/вертикальное движение PageView не
                            // должно уносить саму капсулу за экран.
                            final stretch = (_dragAccY / 220.0).clamp(-0.16, 0.16);
                            _animCtrl.value = stretch;
                          },
                          onVerticalDragEnd: (_) {
                            _finishDrag();
                          },
                          onVerticalDragCancel: () {
                            _dragActive = false;
                            _dragAccY = 0.0;
                            _animCtrl.animateTo(
                              0.0,
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          behavior: HitTestBehavior.translucent,
                          child: Column(
                            children: [
                              // Разделы ближе к верху — уменьшенные отступы:
                              // сама таблетка чуть выше, белый фон на месте.
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    ValueListenableBuilder<int>(
                                      valueListenable: _currentIndex,
                                      builder: (context, current, _) =>
                                          ValueListenableBuilder<double>(
                                        valueListenable: _railPage,
                                        builder: (context, page, __) =>
                                            _SectionRail(
                                              current: current,
                                              page: page,
                                              // Подписи доступны только внутри
                                              // тултипов; отдельного ряда названий
                                              // под таблеткой нет.
                                              labels: tabs,
                                              icons: _icons.sublist(
                                                0,
                                                tabs.length,
                                              ),
                                              onTap: _onTabTap,
                                            ),
                                      ),
                                    ),
                                    // Управление категориями — на уровне таблетки,
                                    // справа; виден только на разделе Задач.
                                    Positioned(
                                      right: 2,
                                      child: ValueListenableBuilder<int>(
                                        valueListenable: _currentIndex,
                                        builder: (context, current, _) =>
                                            AnimatedOpacity(
                                              opacity: current == 2 ? 1.0 : 0.0,
                                              duration: const Duration(
                                                milliseconds: 220,
                                              ),
                                              curve: Curves.easeOutCubic,
                                              child: IgnorePointer(
                                                ignoring: current != 2,
                                                child: IconButton(
                                                  icon: const Icon(
                                                    Icons.folder_outlined,
                                                  ),
                                                  tooltip: Translations.t(
                                                    'manageCategories',
                                                    context,
                                                  ),
                                                  onPressed: () =>
                                                      manageCategoriesTick.value++,
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  constraints:
                                                      const BoxConstraints(
                                                        minWidth: 34,
                                                        minHeight: 34,
                                                      ),
                                                ),
                                              ),
                                            ),
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
                ),
                Expanded(
                  // ClipRRect вокруг PageView скругляет края при
                  // overscroll (BouncingScrollPhysics) — когда тянем
                  // влево на Будильниках или вправо на РП, видимый
                  // контент за краем остаётся скруглённым.
                  child: ClipRRect(
                    // PageView должен клипаться именно в родительском
                    // контейнере: его собственный overscroll иначе рисует
                    // соседний кадр поверх квадратного края.
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                      bottom: Radius.circular(22),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RepaintBoundary(
                      // При выезде чата/другого route слой текущего раздела
                      // двигается готовой текстурой, без повторной отрисовки
                      // четырёх заранее созданных экранов.
                      child: PageView(
                        controller: _pageController,
                        onPageChanged: _onPageChanged,
                        // Соседние разделы строятся/раскладываются ЗАРАНЕЕ (до
                        // появления на экране), а не в момент свайпа. Без этого
                        // быстрый свайп «первый → последний» каждый раз рендерил
                        // новую страницу на лету — отсюда подлагивания.
                        allowImplicitScrolling: true,
                        // Кэш на 3 вьюпорта (после прогрева): при 4 разделах
                        // строятся ВСЕ страницы заранее, поэтому дальний переход
                        // «первый → последний» анимируется по готовым кадрам.
                        // На первом кадре — 1 вьюпорт (текущая + соседняя),
                        // остальные достраиваются в фоне, не нагружая вход.
                        scrollCacheExtent: ScrollCacheExtent.viewport(
                          _cacheWarmed ? 3.0 : 1.0,
                        ),
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        children: screens,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            builder: (context, child) {
              final offset = _animCtrl.value;
              final absOffset = offset.abs().clamp(0.0, 320.0);

              // Закругление углов: растёт с натяжением (0 → 32px).
              // Радиус не должен исчезать в нулевой точке: при pull край
              // всё равно должен оставаться круглым, иначе видны острые углы.
              // Этот радиус относится только к движущемуся блоку разделов,
              // а не к корню приложения. Не округляем весь экран: именно
              // это давало мигание при запуске.
              final cornerRadius = 22.0 + (absOffset / 320.0 * 10.0).clamp(0.0, 10.0);

              // Тень: появляется и растёт с натяжением.
              final shadowAlpha = (absOffset / 320.0 * 0.22).clamp(0.0, 0.22);
              final shadowBlur = (absOffset / 320.0 * 24.0).clamp(0.0, 24.0);
              final shadowDy = (absOffset / 320.0 * 12.0).clamp(0.0, 12.0);

              return Transform.translate(
                // Ограничиваем оттягивание. Капсула остаётся привязанной к
                // своему месту и не «уезжает» при pull слева/справа.
                offset: Offset(0, offset.clamp(0.0, 42.0)),
                child: Transform.scale(
                  scale: 1.0 - (absOffset / 900.0).clamp(0.0, 0.045),
                  alignment: Alignment.topCenter,
                  child: Opacity(
                    opacity: 1.0 - (absOffset / 900.0).clamp(0.0, 0.08),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha * 0.55),
                            blurRadius: shadowBlur * 0.65,
                            offset: Offset(0, shadowDy * 0.55),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        clipBehavior: Clip.antiAlias,
                        borderRadius: BorderRadius.circular(cornerRadius),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(cornerRadius),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.18),
                              width: 0.8,
                            ),
                          ),
                          child: child,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    ),
    );
    // Пятна крови темы MUTILATED теперь рисуются ГЛОБАЛЬНО в корневом
    // builder (main.dart) — поверх Navigator, включая drag-прокси при
    // перетаскивании. Здесь Splatter больше не нужен (избегаем двойных пятен).
    return content;
  }
}

/// Единая объемная капсула разделов главного экрана. Названия остаются
/// доступны в tooltip/semantics, но визуально показываются только иконки:
/// так ряд не распадается на отдельные кнопки и не скачет по ширине.
class _SectionRail extends StatefulWidget {
  final int current;
  final double page;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onTap;

  const _SectionRail({
    required this.current,
    required this.page,
    required this.labels,
    required this.icons,
    required this.onTap,
  });

  @override
  State<_SectionRail> createState() => _SectionRailState();
}

class _SectionRailState extends State<_SectionRail> {
  int? _pressedIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = widget.icons.length;
    if (count == 0) return const SizedBox.shrink();

    final rawPage = widget.page.isFinite
        ? widget.page
        : widget.current.toDouble();
    final page = rawPage.clamp(0.0, (count - 1).toDouble());
    final selectedIndex = page.round().clamp(0, count - 1);
    final indicatorAlignment = count == 1
        ? 0.0
        : -1.0 + (2.0 * page / (count - 1));

    return SizedBox(
      width: 282,
      height: 48,
      // Эффект «стекла»: полупрозрачная капсула с лёгким размытием того, что
      // за ней, — будто видишь сквозь неё контент позади.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surfaceContainerHighest.withValues(alpha: 0.42),
              cs.surfaceContainerLow.withValues(alpha: 0.55),
            ],
          ),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.55),
            width: 1.3,
          ),
          // Мягкий объём без тяжёлой нижней полосы: основной shadow
          // рассеянный, а светлый блик остаётся только внутри верхнего края.
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 12,
              spreadRadius: -3,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.07),
              blurRadius: 8,
              spreadRadius: -4,
              offset: const Offset(0, -1),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19.5),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              fit: StackFit.expand,
              children: [
                // Позиция индикатора берётся прямо из PageView. Здесь
                // намеренно нет AnimatedAlign: implicit-анимации поверх
                // page-скролла и создавали скачок при переходе через 1-2 таба.
                Align(
                  alignment: Alignment(indicatorAlignment, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18.5),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            cs.primary,
                            Color.lerp(cs.primary, cs.tertiary, 0.42)!,
                          ],
                        ),                          boxShadow: [
                          BoxShadow(
                            color: cs.primary.withValues(alpha: 0.34),
                            blurRadius: 6,
                            spreadRadius: -2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(count, (i) {
                    final label = i < widget.labels.length
                        ? widget.labels[i]
                        : '';
                    final proximity = (1.0 - (page - i).abs()).clamp(0.0, 1.0);
                    final iconColor = Color.lerp(
                      cs.onSurfaceVariant,
                      cs.onPrimary,
                      proximity,
                    );
                    final isPressed = _pressedIndex == i;
                    final isSelected = selectedIndex == i;
                    // Фон фигуры следует за положением страницы (непрерывно),
                    // а не за дискретным isSelected: при переключении разделов
                    // подсветка фигур переливается плавно вместе с индикатором.
                    final badgeT = proximity;
                    // Единственный scale-таргет: выбранный чуть увеличен,
                    // остальные 1.0. При нажатии — плавное единое сжатие
                    // (выбранный чуть меньше, чтобы не «нырять» глубоко),
                    // а не два переключения, которые выглядели как мигание.
                    final restingScale = isSelected ? 1.05 : 1.0;
                    final pressedScale = isSelected ? 0.96 : 0.90;
                    return Expanded(
                      // Подсказка-пояснение у кнопки раздела: плавная и под тему
                      // (светлая на светлых, тёмная на тёмных). Отдельные тексты
                      // под таблеткой не показываем.
                      child: SmoothTooltip(
                        message: label,
                        waitDuration: const Duration(milliseconds: 350),
                        child: Semantics(
                          button: true,
                          selected: isSelected,
                          label: label,
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18.5),
                              splashColor: Colors.transparent,
                              highlightColor: Colors.transparent,
                              onTapDown: (_) =>
                                  setState(() => _pressedIndex = i),
                              onTapCancel: () {
                                if (mounted) {
                                  setState(() => _pressedIndex = null);
                                }
                              },
                              onTap: () {
                                setState(() => _pressedIndex = null);
                                widget.onTap(i);
                              },
                              child: Center(
                                child: AnimatedScale(
                                  scale: isPressed
                                      ? pressedScale
                                      : restingScale,
                                  duration: const Duration(milliseconds: 160),
                                  curve: Curves.easeOutCubic,
                                  child: _GeoBadge(
                                    index: i,
                                    size: 27,
                                    color: Color.lerp(
                                      cs.primary.withValues(alpha: 0.13),
                                      cs.onPrimary.withValues(alpha: 0.30),
                                      badgeT,
                                    )!,
                                    child: Icon(
                                      widget.icons[i],
                                      size: 15,
                                      color: iconColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
      ),
    );
  }
}

/// Значок раздела в главной таблетке: иконка сидит внутри своей геометри-
/// ческой фигуры (круг, квадрат, ромб, гексагон) — у каждого раздела свой
/// контур, так получилось нагляднее и красивее.
class _GeoBadge extends StatelessWidget {
  final int index;
  final double size;
  final Color color;
  final Widget child;

  const _GeoBadge({
    required this.index,
    required this.size,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShapePainter(index, color),
        child: Center(
          child: SizedBox(
            width: size * 0.58,
            height: size * 0.58,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final int index;
  final Color color;

  const _ShapePainter(this.index, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // У каждого раздела свой контур: 🔵 круг, ⬜ квадрат, 💠 ромб, ⬡ гексагон.
    if (index == 0) {
      canvas.drawCircle(center, r, paint);
      return;
    }
    final n = index == 3 ? 6 : 4;
    final rot = index == 2 ? pi / 4 : 0.0;
    final start = -pi / 2 + rot;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final a = start + 2 * pi * i / n;
      final p = Offset(center.dx + r * cos(a), center.dy + r * sin(a));
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.index != index || oldDelegate.color != color;
}
