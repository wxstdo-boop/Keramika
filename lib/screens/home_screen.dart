import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
import '../widgets/section_pill.dart';
import '../widgets/animated_fab_row.dart'
    show sectionOffsetByPage, sectionScrollOffset;
import '../widgets/press_scale.dart';
import 'package:flutter/material.dart';
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
import '../utils/jank_probe.dart';
import '../widgets/animated_blur_title.dart';
import '../widgets/new_year_event_banner.dart';
import '../services/new_year_event_service.dart';
import '../widgets/smooth_tooltip.dart' show SmoothTooltip;
import '../widgets/page_spring.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // Таблетка разделов теперь живёт ВНУТРИ скролл-контента каждого экрана
  // (листается вместе с ним) и читает общие notifier-ы из section_pill.dart.
  // Здесь — те же notifier-ы: Home пишет в них позицию PageView, а тап по
  // разделу слушает через sectionTabTap. ValueNotifier вместо setState:
  // смена страницы обновляет только таблетку, а не весь home.
  late final ValueNotifier<int> _currentIndex = sectionCurrentIndex;
  late final ValueNotifier<double> _railPage = sectionRailPage;
  late final PageController _pageController;
  late final AnimationController _animCtrl;
  // Плавный перелёт разделов пружиной: повторный тап по другой вкладке лишь
  // МЕНЯЕТ ЦЕЛЬ, а движение продолжается с текущей скоростью. Было: каждый
  // тап заново запускал animateToPage, скорость обнулялась — при частых тапах
  // по двум вкладкам таблетка «заедала» и ехала по чуть-чуть.
  late final PageSpring _pageSpring = PageSpring(
    vsync: this,
    controller: _pageController,
    // Мягче и медленнее, чем карусель категорий: разделы большие, и
    // «камень» таблетки должен именно ПРОСКОЛЬЗИТЬ между вкладками
    // (≈440 мс, без отскока), а не перескочить.
    stiffness: 170,
    dampingRatio: 0.9,
  );

  /// Сколько сейчас разделов (нужно пружине, чтобы не уехать за край).
  int _pagesCount = 4;
  // Раздел, на котором PageView УСТАНОВИЛСЯ (после анимации/свайпа).
  // Сброс таблетки в видимое состояние делается только при смене этого
  // значения — не при каждом пересечении границы (иначе «скачки»).
  int _lastSettledPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Запускаемся в том разделе, где пользователь был в прошлый раз.
    final savedTab = (globalPrefs.getInt('last_home_tab') ?? 0).clamp(0, 3);
    _lastSettledPage = savedTab;
    sectionCurrentIndex.value = savedTab;
    sectionRailPage.value = savedTab.toDouble();
    // Первый раздел тоже подписываем: после разблокировки ПИН-экрана
    // домашний экран монтируется впервые, а `_onPageChanged` на этом не
    // срабатывает. Это БАЗОВАЯ метка: вкладки — не роуты, и наблюдатель за
    // роутами откатывается к ней после закрытия любого диалога.
    JankProbe.setBaseLabel(
      const ['home:alarms', 'home:habits', 'home:tasks', 'home:rc'][savedTab],
    );
    // Сплэш/PIN разблокируют Home: разделы (keepAlive) уже прокручены,
    // а common sectionScrollOffset при пересоздании State остаётся 0 —
    // таблетка на 100 % высоты налезала на прокрученный контент до первого
    // ручного скролла. Сразу восстанавливаем сохранённый офсет вкладки.
    sectionScrollOffset.value = sectionOffsetByPage[savedTab] ?? 0;
    // Тап по разделу таблетки (таблетка живёт в скролл-контенте экранов)
    // приходит сюда тиком — доезжаем до выбранной страницы.
    sectionTabTap.addListener(_onSectionTabTap);
    sectionDragPage.addListener(_onSectionDragPage);
    _pageController = PageController(initialPage: savedTab)
      ..addListener(_onPageScroll);
    // AnimationController используется как Value<double> — без setState!
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 0.0,
    );
    // РП-тумблер живёт в ChangeNotifier — слушаем его, чтобы вкладка
    // появлялась/исчезала СРАЗУ при переключении в настройках.
    RealityCheckService().addListener(_onRcChanged);
    _showWelcomeOnce();
  }

  void _onRcChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// Тап по разделу в таблетке (она внутри скролл-контента экранов).
  void _onSectionTabTap() {
    _onTabTap(sectionCurrentIndex.value);
  }

  /// Палец ведёт камень по таблетке — двигаем саму карусель, чтобы разделы
  /// ехали под пальцем, а не ждали отпускания.
  ///
  /// Пружину обязательно останавливаем: иначе она каждый кадр тянула бы
  /// карусель к своей старой цели и спорила с пальцем (камень «дрожал»).
  void _onSectionDragPage() {
    final page = sectionDragPage.value;
    if (page == null || !page.isFinite) return;
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    _pageSpring.stop();
    final pos = _pageController.position;
    final current = _pageController.page;
    if (current == null || !current.isFinite) return;
    final perPage = pos.viewportDimension * _pageController.viewportFraction;
    if (perPage <= 0) return;
    final delta = (page - current) * perPage;
    if (delta.abs() < 0.01) return;
    pos.jumpTo(pos.pixels + delta);
    // Пустая «заявка на удержание»: заменяет баллистику страницы, которую
    // та создала бы сама, иначе она подтягивала бы карусель к ближайшей
    // странице прямо под пальцем.
    pos.hold(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealityCheckService().removeListener(_onRcChanged);
    sectionTabTap.removeListener(_onSectionTabTap);
    sectionDragPage.removeListener(_onSectionDragPage);
    _pageController.removeListener(_onPageScroll);
    _pageSpring.dispose();
    _pageController.dispose();
    _animCtrl.dispose();
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
    if (state == AppLifecycleState.resumed) {
      // Возврат из фона: общие офсеты разделов могли остаться stale.
      // Принудительно восстанавливаем общий sectionScrollOffset, чтобы
      // таблетка сразу встала по месту (без пролистывания списка).
      sectionScrollOffset.value = sectionOffsetByPage[_currentIndex.value] ?? 0;
    }
    if (state == AppLifecycleState.inactive) {
      // Останавливаем незавершённый переход между вкладками и встаём
      // ровно на текущую страницу (ту, что уже выбрана чипами).
      _pageSpring.stop();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentIndex.value);
      }
      // Пружину натяжения доводим до нуля мгновенно — контент не
      // «зависает» сдвинутым/уменьшенным в снапшоте недавных.
      _animCtrl.value = 0.0;
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
              if (ctx.mounted) Navigator.pop(ctx);
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
              if (mounted && ctx.mounted) {
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

  /// Показывает окно ивента «Новый год» по тапу на Деду Морозу в
  /// заголовке. НЕ автоматически при запуске.
  /// Гвард _eventModalOpen предотвращает двойной диалог (из-за
  /// которого «фон оставался» после закрытия).
  bool _eventModalOpen = false;
  void _showEventModal() {
    if (!NewYearEventService.isActive) return;
    if (_eventModalOpen || !mounted) return;
    _eventModalOpen = true;
    // Роут с ПРОЗРАЧНЫМ барьером: затемнение рисует сам баннер своим
    // контроллером. Иначе роут гасит фон отдельно от карточки — два
    // разнесённых по времени фейда («выход дерганый, фон догоняет»).
    // Тут скрим и карточка живут на одной таймлайне: фон гаснет быстрее,
    // карточка мягко долетает до конца.
    showGeneralDialog<void>(
      context: context,
      // Закрыть можно только кнопкой X в окне (не тапом по фону).
      barrierDismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      // Имя роута нужно jank-пробе: без него окно ивента и все прочие
      // `showGeneralDialog` пишутся в лог одним `RawDialogRoute<void>`, и
      // «тормозит ивент» неотличимо от «тормозит меню языка».
      routeSettings: const RouteSettings(name: 'dlg:event'),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, _) => NewYearEventBanner(
        onClose: () {
          // Гарантированное закрытие: даже если диалог уже в процессе
          // закрытия — не роняем и не оставляем «фон».
          if (Navigator.canPop(ctx)) Navigator.of(ctx).pop();
        },
      ),
      transitionBuilder: (ctx, _, _, child) => child,
    ).whenComplete(() => _eventModalOpen = false);
  }

  void _onPageScroll() {
    if (!_pageController.hasClients ||
        !_pageController.position.hasContentDimensions) {
      return;
    }
    final page = _pageController.page;
    if (page != null &&
        page.isFinite &&
        (_railPage.value - page).abs() > 0.001) {
      _railPage.value = page;
    }
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
    // Подпись раздела для jank-пробы (lib/utils/jank_probe.dart): вкладки —
    // не роуты, NavigatorObserver их не видит, а «тормозит на привычках» и
    // «тормозит на будильниках» — это разные чины и разные правки.
    JankProbe.setLabel(
      const ['home:alarms', 'home:habits', 'home:tasks', 'home:rc'][index],
    );
    // НЕ пишем globalPrefs.setInt здесь: onPageChanged fires на КАЖДОЙ
    // границе (0→3 = три platform channel вызова). Запись перенесена в
    // _onPageScrollEnd, где она одна — на settled страницу. Это снимает
    // накопленный джанк при быстрых тапах.
  }

  /// Раздел окончательно остановился на новой странице (свайп или конец
  /// анимации) — только тогда таблетка стартует видимой. Промежуточные
  /// пересечения границ во время перелёта её не дёргают.
  bool _onPageScrollEnd(ScrollEndNotification n) {
    if (_pageController.hasClients &&
        _pageController.position.hasContentDimensions) {
      final page = _pageController.page;
      if (page != null && page.isFinite) {
        final settled = page.round();
        if (settled != _lastSettledPage) {
          _lastSettledPage = settled;
          // Не 0: вкладка keepAlive, её список остался прокрученным, и
          // события скролла от неё не придут. Возвращаем планшетке её
          // сохранённую высоту — иначе она налезала на контент до
          // первого скролла.
          sectionScrollOffset.value = sectionOffsetByPage[settled] ?? 0;
          // Пишем в SharedPreferences только на settled странице
          // (не на каждом пересечении границ PageView — так было 3
          // async platform channel calls на один дальний перелёт).
          globalPrefs.setInt('last_home_tab', settled);
        }
      }
    }
    return false;
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
    // Таблетка сразу показывает сохранённую высоту ЦЕЛЕВОГО раздела: он
    // keepAlive и мог остаться прокрученным. Ставим 0 нельзя — до приезда
    // событий скролла планшетка налезала на уже прокрученный контент.
    sectionScrollOffset.value = sectionOffsetByPage[index] ?? 0;
    // Мягкий перелёт пружиной. При частых тапах по двум вкладкам пружина не
    // «перезапускается с нуля» (как делал animateToPage), а плавно доворачивает
    // с уже набранной скоростью — без заеданий и «езды по чуть-чуть».
    _pageSpring.to(index.toDouble(), maxPage: (_pagesCount - 1).toDouble());
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
          _pageSpring.stop();
          _pageController.jumpToPage(0);
          _currentIndex.value = 0;
        }
      });
    }

    final screens = <Widget>[
      // RepaintBoundary изолирует перерисовку вкладок: свайп/анимация на
      // одной вкладке не перерисовывает остальные (меньше работы на GPU).
      RepaintBoundary(
        child: AlarmsScreen(scrollOffset: sectionScrollOffset, pillIndex: 0),
      ),
      RepaintBoundary(
        child: HabitsScreen(scrollOffset: sectionScrollOffset, pillIndex: 1),
      ),
      RepaintBoundary(
        child: TasksScreen(scrollOffset: sectionScrollOffset, pillIndex: 2),
      ),
      if (rcOn)
        RepaintBoundary(
          child: RealityChecksScreen(
            onExit: () => _onTabTap(0),
            scrollOffset: sectionScrollOffset,
            pillIndex: 3,
          ),
        ),
    ];

    _pagesCount = screens.length;

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
          // Плавная отдача при зажатии у всех значков шапки (обновить,
          // статистика, питание, настройки) — мягко вдавливаются.
          leading: PressScale(
            pressedScale: 0.90,
            duration: const Duration(milliseconds: 200),
            child: SmoothTooltip(
              message: Translations.refreshOf(context),
              preferredAbove: true,
              child: IconButton(
                icon: const Icon(Icons.refresh_outlined),
                onPressed: () => KeramikaApp.of(context).refreshApp(),
              ),
            ),
          ),
          // Тап по Деду Морозу в заголовке открывает окно ивента.
          title: AnimatedBlurTitle(onSantaTap: _showEventModal),
          centerTitle: false,
          actions: [
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: SmoothTooltip(
                message: Translations.t('statistics', context, 'Статистика'),
                preferredAbove: true,
                child: IconButton(
                  icon: const Icon(Icons.bar_chart_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RealityCheckStatsScreen(),
                    ),
                  ),
                ),
              ),
            ),
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: SmoothTooltip(
                message: Translations.t('nutrition', context, 'Питание'),
                preferredAbove: true,
                child: IconButton(
                  icon: const Icon(Icons.restaurant_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NutritionScreen()),
                  ),
                ),
              ),
            ),
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: SmoothTooltip(
                message: Translations.t('settings', context, 'Настройки'),
                preferredAbove: true,
                child: IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(
                    context,
                  ).push(slideSideRoute(const SettingsScreen())),
                ),
              ),
            ),
          ],
        ),
        body: Stack(
          children: [
            // Фоновая «skin» подложка. Проявляется при натяжении экрана вниз —
            // между верхним AppBar и едущим вниз блоком разделов появляется
            // естественный «зазор», который и создаёт эффект «экран тянется».
            Positioned.fill(
              child: Container(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),

            // Таблетка разделов больше НЕ фиксирована сверху: она живёт внутри
            // скролл-контента каждого экрана (см. SectionPill) и листается
            // вместе с ним, как обычный контент. Здесь остаётся только
            // PageView с разделами на весь body — свайп пальцем работает
            // по всей высоте, включая область над таблеткой.
            // AnimatedBuilder сам растянут на весь Stack (Positioned.fill),
            // а его child заполняет его через SizedBox.expand: Expanded тут
            // нельзя — AnimatedBuilder не Flex, и Expanded под ним падал
            // с «ParentData is not a subtype of FlexParentData».
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _animCtrl,
                // Таблетка разделов — НАД PageView, в обычном потоке (не поверх
                // контента): при переключении разделов она остаётся на месте,
                // а листается только содержимое под ней — как было раньше.
                // При прокрутке вниз таблетка вместе с фоном сворачивается
                // (AnimatedSize), при долистывании до верха — возвращается.
                // Таблетка разделов — СТЕКЛО ПОВЕРХ контента: она лежит в Stack
                // над PageView, а каждый экран резервирует сверху
                // [kSectionPillSlotHeight] своего скролла. В покое список
                // начинается под капсулой, при прокрутке уходит ПОД неё — и
                // blur размывает реальный контент, а не сплошную подложку.
                // Opacity вокруг BackdropFilter ставить нельзя: слой
                // прозрачности лишает blur валидного бэкдропа и заливает
                // экран серым — сворачивание сделано обрезком (ClipRect+Align).
                child: ClipRRect(
                  // ClipRRect вокруг PageView скругляет края при
                  // overscroll (BouncingScrollPhysics) — когда тянем
                  // влево на Будильниках или вправо на РП, видимый
                  // контент за краем остаётся скруглённым.
                  // PageView должен клипаться именно в родительском
                  // контейнере: его собственный overscroll иначе рисует
                  // соседний кадр поверх квадратного края.
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                    bottom: Radius.circular(22),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      RepaintBoundary(
                        // При выезде чата/другого route слой текущего раздела
                        // двигается готовой текстурой, без повторной отрисовки
                        // четырёх заранее созданных экранов.
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            // Палец повёл разделы — пружина уступает жесту.
                            if (notification is ScrollStartNotification &&
                                notification.dragDetails != null) {
                              _pageSpring.stop();
                            }
                            if (notification is ScrollEndNotification) {
                              return _onPageScrollEnd(notification);
                            }
                            return false;
                          },
                          child: PageView(
                            controller: _pageController,
                            onPageChanged: _onPageChanged,
                            // Соседние разделы строятся/раскладываются ЗАРАНЕЕ (до
                            // появления на экране), а не в момент свайпа. Без этого
                            // быстрый свайп «первый → последний» каждый раз рендерил
                            // новую страницу на лету — отсюда подлагивания.
                            allowImplicitScrolling: true,
                            // Кэш на 3 вьюпорта: при 4 разделах строятся ВСЕ
                            // страницы заранее, поэтому дальний переход «первый →
                            physics: const BouncingScrollPhysics(
                              parent: AlwaysScrollableScrollPhysics(),
                            ),
                            children: screens,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        // Таблетка «уезжает» вместе с прокруткой: высота среза
                        // пропорциональна скроллу. Align+ClipRect режут готовый
                        // слой — сама таблетка не перекладывается.
                        //
                        // Линейное окно в kSectionPillSlotHeight, а НЕ easeOutCubic
                        // по 72 px:easeOut почти не убирал высоту в первых кадрах,
                        // а зазор между нижним краем капсулы (58) и началом списка
                        // (68) — всего 10 px. Заголовок секции успевал въехать
                        // прямо на ещё полную таблетку. При f = 1 - off/64 клиренс
                        // 58·f ≤ 68 - off держится на всём прокрутке.
                        child: ValueListenableBuilder<double>(
                          valueListenable: sectionScrollOffset,
                          // САМА таблетка передаётся через `child:` и
                          // пересобирается ОДИН РАЗ: builder вызывается на
                          // каждый кадр скролла, и без этого под каждый кадр
                          // создавался новый экземпляр SectionPill → заново
                          // прогонялось всё её стекло (StainedGlassPainter +
                          // 4 _ShapePainter + куча Color.lerp). На Adreno 610
                          // это и были микрофризы вертикального скролла:
                          // двигать готовый слой дёшево, перекладывать — нет.
                          // Таблетка передаётся через `child:`, то есть
                          // пересобирается при пересборке HomeScreen, а НЕ при
                          // каждом кадре скролла: builder вызывается на каждый
                          // кадр, и без этого под каждый кадр создавался свежий
                          // SectionPill → заново прогонялось всё её стекло
                          // (StainedGlassPainter + 4 _ShapePainter + Color.lerp).
                          // На Adreno 610 это и были микрофризы вертикального
                          // скролла: двигать готовый слой дёшево, перекладывать
                          // — нет. Без `const` намеренно: список разделов
                          // читается из RealityCheckService().enabled, а
                          // HomeScreen слушает этот сервис (_onRcChanged), так
                          // что при выключении РП таблетка пересобирается.
                          child: RepaintBoundary(child: SectionPill()),
                          builder: (context, off, pill) {
                            final tEased = (1.0 - off / kSectionPillSlotHeight)
                                .clamp(0.0, 1.0);
                            if (tEased <= 0.01) return const SizedBox.shrink();
                            return ClipRect(
                              child: Align(
                                alignment: Alignment.topCenter,
                                heightFactor: tEased,
                                child: IgnorePointer(
                                  ignoring: tEased < 0.5,
                                  child: pill,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
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
                  final cornerRadius =
                      22.0 + (absOffset / 320.0 * 10.0).clamp(0.0, 10.0);

                  // Тень: появляется и растёт с натяжением.
                  final shadowAlpha = (absOffset / 320.0 * 0.22).clamp(
                    0.0,
                    0.22,
                  );
                  final shadowBlur = (absOffset / 320.0 * 24.0).clamp(
                    0.0,
                    24.0,
                  );
                  final shadowDy = (absOffset / 320.0 * 12.0).clamp(0.0, 12.0);

                  return Transform.translate(
                    // Ограничиваем оттягивание. Капсула остаётся привязанной к
                    // своему месту и не «уезжает» при pull слева/справа.
                    offset: Offset(0, offset.clamp(0.0, 42.0)),
                    child: Transform.scale(
                      scale: 1.0 - (absOffset / 900.0).clamp(0.0, 0.045),
                      alignment: Alignment.topCenter,
                      // Opacity здесь ставить нельзя: внутри блока лежит
                      // BackdropFilter таблетки, а слой прозрачности лишает blur
                      // валидного бэкдропа — при оттягивании экран залило серым.
                      // Лёгкое затемнение при pull и так даёт растущая тень.
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowAlpha * 0.55,
                              ),
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
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(alpha: 0.18),
                                width: 0.8,
                              ),
                            ),
                            child: child,
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
    );
    // Пятна крови темы MUTILATED теперь рисуются ГЛОБАЛЬНО в корневом
    // builder (main.dart) — поверх Navigator, включая drag-прокси при
    // перетаскивании. Здесь Splatter больше не нужен (избегаем двойных пятен).
    return content;
  }
}
