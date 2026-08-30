import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import '../services/haptics.dart';
import '../widgets/section_pill.dart';
import '../widgets/animated_fab_row.dart' show sectionScrollOffset;
import '../widgets/press_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
  // Таблетка разделов теперь живёт ВНУТРИ скролл-контента каждого экрана
  // (листается вместе с ним) и читает общие notifier-ы из section_pill.dart.
  // Здесь — те же notifier-ы: Home пишет в них позицию PageView, а тап по
  // разделу слушает через sectionTabTap. ValueNotifier вместо setState:
  // смена страницы обновляет только таблетку, а не весь home.
  late final ValueNotifier<int> _currentIndex = sectionCurrentIndex;
  late final ValueNotifier<double> _railPage = sectionRailPage;
  late final PageController _pageController;
  late final AnimationController _animCtrl;
  // Раздел, на котором PageView УСТАНОВИЛСЯ (после анимации/свайпа).
  // Сброс таблетки в видимое состояние делается только при смене этого
  // значения — не при каждом пересечении границы (иначе «скачки»).
  int _lastSettledPage = 0;
  // Ленивый прогрев вкладок: первый кадр Home строит только текущую и
  // соседнюю вкладки, остальные достраиваются через полсекунды в фоне.
  // Раньше все 4 раздела (со списками и их каскадными анимациями)
  // строились в ОДНОМ кадре — на слабых телефонах вход в приложение
  // «подтормаживал» именно в момент перехода сплэш → главная.
  bool _cacheWarmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Запускаемся в том разделе, где пользователь был в прошлый раз.
    final savedTab = (globalPrefs.getInt('last_home_tab') ?? 0).clamp(0, 3);
    _lastSettledPage = savedTab;
    sectionCurrentIndex.value = savedTab;
    sectionRailPage.value = savedTab.toDouble();
    // Тап по разделу таблетки (таблетка живёт в скролл-контенте экранов)
    // приходит сюда тиком — доезжаем до выбранной страницы.
    sectionTabTap.addListener(_onSectionTabTap);
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

  /// Тап по разделу в таблетке (она внутри скролл-контента экранов).
  void _onSectionTabTap() {
    _onTabTap(sectionCurrentIndex.value);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RealityCheckService().removeListener(_onRcChanged);
    sectionTabTap.removeListener(_onSectionTabTap);
    _pageController.removeListener(_onPageScroll);
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
    if (state == AppLifecycleState.inactive) {
      // Останавливаем незавершённый переход между вкладками и встаём
      // ровно на текущую страницу (ту, что уже выбрана чипами).
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
    if (page != null &&
        page.isFinite &&
        (_railPage.value - page).abs() > 0.001) {
      _railPage.value = page;
    }
  }

  void _onPageChanged(int index) {
    _currentIndex.value = index;
    // Сброс скролл-офсета (таблетка видна на свежем разделе) НЕ делаем
    // здесь: onPageChanged срабатывает при пересечении КАЖДОЙ границы во
    // время дальнего перелёта (0→3 проходит через 1 и 2) и при быстрых
    // тапах телепортировал таблетку вверх-вниз — отсюда «скачки». Сброс
    // происходит в момент тапа (_onTabTap) и когда раздел УСТАНОВИЛСЯ
    // (ScrollEndNotification).
    globalPrefs.setInt('last_home_tab', index);
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
          sectionScrollOffset.value = 0;
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
    // Таблетка сразу видна на новом разделе (сброс здесь, а не в
    // onPageChanged — тот дёргал её при каждом пересечении границы).
    sectionScrollOffset.value = 0;
    // Плавный, чуть более медленный перелёт (420 мс, мягкий вход-выход):
    // резкий 320 мс + jumpTo перед анимацией давали «рывок» таблетки при
    // быстрых тапах туда-сюда. animateToPage сам заменяет текущую анимацию
    // новой — очередь не копится, а скачка-снапа нет.
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
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
          // Плавная отдача при зажатии у всех значков шапки (обновить,
          // статистика, питание, настройки) — мягко вдавливаются.
          leading: PressScale(
            pressedScale: 0.90,
            duration: const Duration(milliseconds: 200),
            child: IconButton(
              icon: const Icon(Icons.refresh_outlined),
              tooltip: Translations.refreshOf(context),
              onPressed: () => KeramikaApp.of(context).refreshApp(),
            ),
          ),
          title: const AnimatedBlurTitle(),
          centerTitle: false,
          actions: [
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                icon: const Icon(Icons.bar_chart_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RealityCheckStatsScreen(),
                  ),
                ),
              ),
            ),
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                icon: const Icon(Icons.restaurant_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NutritionScreen()),
                ),
              ),
            ),
            PressScale(
              pressedScale: 0.90,
              duration: const Duration(milliseconds: 200),
              child: IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(
                  context,
                ).push(slideSideRoute(const SettingsScreen())),
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
              child: Column(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: sectionScrollOffset,
                    // Таблетка «уезжает» вместе с прокруткой ВМЕСТЕ со своим
                    // фоном: высота слота пропорциональна скроллу, контент
                    // заполняет освободившееся место (как было в 1.6.19 —
                    // это и есть «пиздато»). Align меняет только высоту слота,
                    // сама таблетка (RepaintBoundary) не пере-раскладывается.
                    builder: (context, off, _) {
                      final t = (1.0 - off / 72.0).clamp(0.0, 1.0);
                      final tEased = Curves.easeOutCubic.transform(t);
                      return ClipRect(
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: tEased,
                          child: Opacity(
                            opacity: tEased,
                            child: IgnorePointer(
                              ignoring: tEased < 0.5,
                              // child без const: при переключении РП в
                              // настройках таблетка получает свежий список
                              // разделов.
                              child: RepaintBoundary(child: SectionPill()),
                            ),
                          ),
                        ),
                      );
                    },
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
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: _onPageScrollEnd,
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
                final cornerRadius =
                    22.0 + (absOffset / 320.0 * 10.0).clamp(0.0, 10.0);

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
