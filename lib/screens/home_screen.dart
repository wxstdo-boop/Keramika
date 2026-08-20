import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
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
    _pageController = PageController(initialPage: savedTab);
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
    _pageController.dispose();
    _animCtrl.dispose();
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

  void _onPageChanged(int index) {
    _currentIndex.value = index;
    globalPrefs.setInt('last_home_tab', index);
  }

  void _onTabTap(int index) {
    final current = _currentIndex.value;
    final distance = (index - current).abs();
    if (distance == 0) return;
    // Все страницы заранее построены (scrollCacheExtent ниже), поэтому
    // даже дальний переход «первый → последний» едет по готовым кадрам
    // и остаётся плавным. Длительность растёт с расстоянием.
    _pageController.animateToPage(
      index,
      duration: Duration(milliseconds: 180 + distance * 60),
      curve: Curves.easeOutCubic,
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

    final content = Scaffold(
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
                GestureDetector(
                  // Вертикальный свайп над областью чипов переключает табы.
                  // Горизонтальная прокрутка чипов остаётся у SingleChildScrollView.
                  onVerticalDragStart: (_) {
                    _dragActive = true;
                    _dragAccY = 0.0;
                  },
                  onVerticalDragUpdate: (details) {
                    _dragAccY += details.delta.dy;
                  },
                  onVerticalDragEnd: (_) {
                    _finishDrag();
                  },
                  behavior: HitTestBehavior.translucent,
                  child: Column(
                    children: [
                      // Разделы ближе к верху — уменьшенные отступы.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: ValueListenableBuilder<int>(
                          valueListenable: _currentIndex,
                          builder: (context, current, _) =>
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List.generate(tabs.length, (i) {
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: _TabChip(
                                        selected: current == i,
                                        icon: _icons[i],
                                        label: tabs[i],
                                        onTap: () => _onTabTap(i),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
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
              ],
            ),
            builder: (context, child) {
              final offset = _animCtrl.value;
              final absOffset = offset.abs().clamp(0.0, 320.0);

              // Закругление углов: растёт с натяжением (0 → 32px).
              final cornerRadius = (absOffset / 320.0 * 32.0).clamp(0.0, 32.0);

              // Масштаб слегка сжимается при натяжении (1.0 → 0.85).
              final tensionScale = 1.0 - (absOffset / 650.0).clamp(0.0, 0.15);

              // Прозрачность: контент чуть тускнеет при натяжении.
              final tensionOpacity = 1.0 - (absOffset / 380.0).clamp(0.0, 0.30);

              // Тень: появляется и растёт с натяжением.
              final shadowAlpha = (absOffset / 320.0 * 0.22).clamp(0.0, 0.22);
              final shadowBlur = (absOffset / 320.0 * 24.0).clamp(0.0, 24.0);
              final shadowDy = (absOffset / 320.0 * 12.0).clamp(0.0, 12.0);

              return Transform.translate(
                offset: Offset(0, offset),
                child: Transform.scale(
                  scale: tensionScale,
                  alignment: offset < 0
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: Opacity(
                    opacity: tensionOpacity,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: shadowAlpha),
                            blurRadius: shadowBlur,
                            offset: Offset(0, shadowDy),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(cornerRadius),
                        child: Container(
                          // Перекрываем фон Stack'а, иначе ClipRRect «покажет»
                          // skin даже когда тянули чуть-чуть.
                          color: Theme.of(context).scaffoldBackgroundColor,
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
    );
    // Пятна крови темы MUTILATED теперь рисуются ГЛОБАЛЬНО в корневом
    // builder (main.dart) — поверх Navigator, включая drag-прокси при
    // перетаскивании. Здесь Splatter больше не нужен (избегаем двойных пятен).
    return content;
  }
}

/// Плавный чип вкладки: фон, иконка и текст анимируются синхронно одним
/// tween'ом, поэтому при переключении разделов нет «мигания» предыдущего
/// чипа (у стандартного FilterChip иконка/текст меняются мгновенно,
/// пока фон ещё анимируется).
class _TabChip extends StatefulWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  State<_TabChip> createState() => _TabChipState();
}

class _TabChipState extends State<_TabChip>
    with SingleTickerProviderStateMixin {
  // Стартует с текущего состояния БЕЗ анимации, а при смене selected
  // плавно перетекает (раньше begin==end — фон «появлялся» мгновенно).
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.selected ? 1.0 : 0.0,
  );

  @override
  void didUpdateWidget(covariant _TabChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _ctrl.animateTo(widget.selected ? 1.0 : 0.0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseBg = isDark ? cs.surfaceContainerHighest : cs.secondaryContainer;
    final selectedBg = isDark ? cs.primary : cs.primaryContainer;
    final baseFg = cs.onSurfaceVariant;
    final selectedFg = isDark ? cs.onPrimary : cs.onPrimaryContainer;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        final bg = Color.lerp(baseBg, selectedBg, t)!;
        final fg = Color.lerp(baseFg, selectedFg, t)!;
        // Пружинный «поп» выбранной вкладки: лёгкое увеличение с
        // easeOutBack и плавным возвратом (без влияния на layout).
        return AnimatedScale(
          scale: widget.selected ? 1.07 : 1.0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutBack,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
