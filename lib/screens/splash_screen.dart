import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart' show preDecodedLogo;
import '../utils/motion_prefs.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onDone;

  const SplashScreen({super.key, this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  /// Ход блика по стеклу. ВЕДЁТСЯ ОТ ТОГО ЖЕ мастер-контроллера, что и
  /// появление логотипа, а не из отдельного таймера: собственный контроллер
  /// со стартом на 1100 мс и периодом 1900 мс физически не успевал пройти
  /// цикл до закрытия сплэша на 2200 мс — пользователь видел только то, как
  /// полоса входит с левого края (ход обрывался на t≈0.58), а пик яркости
  /// приходился ровно на смену экрана.
  late final CurvedAnimation _shine;

  /// Левитирующий человечек — независимый бесшовный цикл.
  late final AnimationController _float;

  /// Финальное растворение человечка: в последние 20 % хода мастер-контроллера
  /// (0.80→1.0) его альфа идёт 1→0 — иконка исчезает ровно в момент, когда
  /// сплеш уходит на контент, а не в начале.
  late final CurvedAnimation _badgeExit;

  Timer? _splashTimer;

  /// Селекторы _float и _splashTimer: отложенный запуск левитации + её
  /// остановка на выходе.
  Timer? _startFloatTimer;

  /// Радиус скругления «стекла» — тот же, что у карточки-сквайркла.
  static const double _kRadius = 30;

  /// Сколько сплэш виден до ухода на главную. Единый источник правды:
  /// от него считаются все окна анимаций, поэтому ничего не «обрезается»
  /// на выходе (раньше мастер-контроллер шёл 2000 мс, а уход случался на
  /// 1950-й — последние 2.5 % фаз просто не доигрывались).
  static const int _kVisibleMs = 1950;

  /// Пауза перед стартом левитации: сплэш въезжает (340 мс, scale+fade всей
  /// страницы), и только потом включается бесконечный пейнтер человечка.
  static const int _kFloatStartMs = 340;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: _kVisibleMs),
      vsync: this,
    );
    // Блик — окно внутри общего хода (0.34..0.88 = 663→1716 мс). Логотип
    // к этому моменту уже почти проявлен, а до закрытия сплэша остаётся
    // запас, то есть полоса гарантированно проходит ЦЕЛИКОМ и начинается,
    // и заканчивается плавно (яркость на обоих концах хода = 0, скорость
    // тоже).
    _shine = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.34, 0.88),
    );
    // Быстрое и чистое проявление: ТОЛЬКО fade, без масштаба. Масштаб
    // (0.94→1.0) на большой карточке с тенью заставлял GPU каждый кадр
    // перефильтровывать слой — на бюджетнике это и читалось как
    // «иконка появляется подтормаживая». Fade готового растра дешёвый.
    // Окно 0→0.60 (1.2 с): логотип появляется решительно, а не «выползает»
    // полторы секунды.
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.60, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    // Левитация — бесконечный цикл (repeat()): пейнтер рисует
    // sin(2π·p), поэтому на стыке p=1→0 значение И скорость совпадают —
    // ни замирания в конце, ни рывка при развороте нет.
    // Один «вздох» левитации за ВИДИМОЕ время сплеша: старт на 340 мс
    // (когда страница встала после въезда) и уход на 1950 мс. Длительность
    // цикла равна этому окну, поэтому человечек доигрывает фазу ИМЕННО к
    // моменту ухода: раньше цикл был 2200 мс и на 1950-й loop обрывался в
    // воздухе (фаза ~0.89) — заметное «зависание» на последних кадрах.
    // Теперь фаза на выходе ровно 1.0 (== 0), без рывка.
    _float = AnimationController(
      duration: const Duration(milliseconds: _kVisibleMs - _kFloatStartMs),
      vsync: this,
    );
    // ЛЕВИТАЦИЯ НЕ ПУСКАЕТСЯ СРАЗУ: сплеш въезжает через lockRoute
    // (340 мс, scale + fade всей страницы), и в это же время крутился бы
    // бесконечный CustomPaint-пейнтер — GPU одновременно перефильтровал бы
    // масштабируемую страницу И перечитывал пейнтер каждый кадр: отсюда
    // «подлагивание на входе». В первые 340 мс человечек всё равно невидим
    // (alpha = _fade * (1 - _badgeExit) ≈ 0), поэтому старт левитации на
    // 340-м мс не виден глазом, а тяжёлый loop крутится уже когда
    // страница встала на место.
    _startFloatTimer = Timer(const Duration(milliseconds: _kFloatStartMs), () {
      if (!mounted) return;
      // Левитация — чисто декоративная петля: при «убрать анимации»
      // человечек просто стоит на месте (в позе покоя), а не парит.
      if (MotionPrefs.shouldReduceMotion) return;
      _float.repeat();
    });
    // Человечек доигрывает левитацию и затем мягко растворяется: за
    // последние ~400 мс (t 0.80→1.0) альфа 1→0. Таким образом он живёт
    // весь сплэш и исчезает в КОНЦЕ, когда экран уже уходит.
    _badgeExit = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.80, 1.0, curve: Curves.easeIn),
    );
    // Заранее прогреваем кэш логотипа: первый кадр после сплэша
    // не «мигает» и не показывает пустое место. PrcacheImage сам
    // отработает, когда у него будет MediaQuery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/keramika.png'), context);
    });
    // Анимация идёт 2 секунды; переходим на главную сразу после её
    // окончания. Раньше стояло 2200 мс — лишние 200 мс «мёртвой паузы»
    // после того, как логотип уже растворился, читались как рывок.
    // 1950 мс: кросс-фейд стартует, пока человечек ещё догасает, поэтому
    // переход читается одним движением, а не «пауза → смена кадра».
    _splashTimer = Timer(const Duration(milliseconds: _kVisibleMs), () {
      if (!mounted) return;
      // ВЫХОД: в момент onHome стартует homeEntryRoute (280 мс, наезд
      // дома: 4 keepAlive-экрана + таблетка). Если в это же время сплеш
      // крутит бесконечную левитацию, оба экрана перечитывают кады
      // одновременно — GPU проседает, и переход читается как
      // «подлагивание на выходе». Останавливаем loop: левитация (лёгкое
      // покачивание на ±2.8 px) замирает почти незаметно, растворение
      // человечка (_badgeExit) продолжается — его ведёт ещё живой
      // _controller, а блик к этому моменту уже отработал.
      _float.stop();
      widget.onDone?.call();
    });
    // Разрешения больше не запрашиваем автоматически.
    // Пользователь сам включает их в настройках приложения.
    // Это предотвращает:
    //  — вылет в системные настройки точных будильников при первом запуске
    //  — "двойной запуск" при возврате из системных настроек
    //  — включённые уведомления без ведома пользователя
  }

  @override
  void dispose() {
    _startFloatTimer?.cancel();
    _splashTimer?.cancel();
    // Левитацию останавливаем ПЕРЕД dispose: контроллер, размонтированный
    // со стартовавшим бесконечным циклом, роняет assertion («ticker
    // active at dispose»).
    _float.stop();
    // CurvedAnimation снимает свой слушатель с мастер-контроллера, поэтому
    // его dispose() идёт ДО dispose родителя.
    _shine.dispose();
    _badgeExit.dispose();
    _float.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Цвет обводки логотипа — primary выбранной темы (rose/peach/grok/...).
    final accent = theme.colorScheme.primary;
    final cs = theme.colorScheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          // Фон сплеша под темы — как у экрана PIN-кода: градиент от
          // поверхности к лёгкому фирменному оттенку primaryContainer,
          // а не жёсткий серый/чёрный. Светлый/тёмный по текущей теме.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    cs.surface,
                    cs.surfaceContainerLow,
                    Color.lerp(cs.surface, cs.primaryContainer, 0.28)!,
                  ]
                : [
                    cs.surfaceContainerLowest,
                    cs.surface,
                    Color.lerp(cs.surface, cs.primaryContainer, 0.35)!,
                  ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Логотип крупным планом, без «коробки» и без обрезки
                        // (contain) — текст внутри картинки читается чётко.
                        // Вокруг — красивая полупрозрачная обводка в цвет
                        // ВЫБРАННОЙ темы (primary из ColorScheme): rose → розовая,
                        // peach → персиковая, grok → её акцент и т.д. Смотрится
                        // дорого и на светлом, и на тёмном фоне.
                        // Заранее прогреваем кэш, чтобы логотип не «мигал»
                        // и не появлялся не сразу на слабых телефонах вроде
                        // Redmi Note 12 — первый кадр сразу рисуется с ним.
                        // Логотип крупным планом, с прогретым кэшем
                        // из initState сразу выезжает на первый кадр.
                        // RepaintBoundary кэширует отрисованную аватарку
                        // текстурой: во время slide/fade-анимации (1800мс)
                        // движется готовый растр, а не перефильтровывается
                        // большая картинка каждый кадр — на слабых
                        // телефонах аватарка не «дёргается».
                        // Блик лежит ОТДЕЛЬНЫМ слоем над всей карточкой, а
                        // не внутри картинки: полоса должна проходить и по
                        // цветному кольцу-обводке, и по самому логотипу —
                        // только тогда она читается как отражение на стекле.
                        // Обрезка — своим ClipRRect с тем же радиусом,
                        // поэтому тень карточки (она рисуется ЗА её
                        // габаритом) не подрезается.
                        Stack(
                          children: [
                            RepaintBoundary(
                              child: Container(
                                width: 104,
                                height: 104,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  // «Скруглый» (squircle) — круглее квадрата, но
                                  // НЕ круг: нижняя подпись на логотипе не
                                  // обрезается кружком и остаётся читаемой.
                                  borderRadius: BorderRadius.circular(_kRadius),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(
                                        alpha: isDark ? 0.10 : 0.92,
                                      ),
                                      accent.withValues(
                                        alpha: isDark ? 0.20 : 0.12,
                                      ),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.62),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withValues(alpha: 0.28),
                                      blurRadius: 30,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.28 : 0.08,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 9),
                                    ),
                                  ],
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(25),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.55,
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(23),
                                    // Логотип уже декодирован в main() до
                                    // первого кадра — RawImage рисует его
                                    // мгновенно, без «мигания» на слабых
                                    // телефонах.
                                    child: preDecodedLogo != null
                                        ? RawImage(
                                            image: preDecodedLogo,
                                            width: 94,
                                            height: 94,
                                            fit: BoxFit.contain,
                                            filterQuality: FilterQuality.high,
                                          )
                                        : Image.asset(
                                            'assets/keramika.png',
                                            width: 94,
                                            height: 94,
                                            cacheWidth: 512,
                                            cacheHeight: 512,
                                            filterQuality: FilterQuality.high,
                                            isAntiAlias: true,
                                            fit: BoxFit.contain,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            // РАЗБИТОЕ СТЕКЛО: радиальные трещины из точки
                            // удара, концентрические разломы и светлые пятна
                            // напряжения. Лежит над плитой, но ПОД бегущим
                            // бликом — искра проходит и по трещинам, поэтому
                            // ава читается настоящим сколом, а не наклейкой.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(_kRadius),
                                  child: RepaintBoundary(
                                    child: CustomPaint(
                                      painter: _ShatteredGlassPainter(
                                        isDark: isDark,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                // Блик лежит ОДНИМ слоем под RepaintBoundary
                                // и клипается ВНУТРИ пейнтера
                                // (canvas.clipRRect). Раньше здесь стоял
                                // виджет ClipRRect: он делает saveLayer на
                                // каждый кадр блика, а блик перерисовывается
                                // каждый кадр — на слабом GPU это лишний
                                // полноэкранный слой. Клип на канвасе
                                // saveLayer не создаёт.
                                child: RepaintBoundary(
                                  child: AnimatedBuilder(
                                    animation: _shine,
                                    builder: (context, _) => CustomPaint(
                                      painter: _GlassSweepPainter(
                                        t: _shine.value,
                                        radius: _kRadius,
                                        // На светлой теме кровавое ядро по
                                        // белому кольцу читается слабо —
                                        // поэтому яркость задаётся темой,
                                        // а тёмная кромка полосы делает блик
                                        // читаемым на любом фоне.
                                        strength: isDark ? 0.78 : 1.10,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      // Подпись остаётся строго по центру кадра: «POWERED BY
                      // LARAF» — мелко и чётко (10px, широкий треинг,
                      // полужирный для резкости кромки). Подписывает
                      // проявляется с логотипом и растворяется в самом конце
                      // сплеша вместе с человечком — тем же окном _badgeExit.
                      AnimatedBuilder(
                        animation: _badgeExit,
                        builder: (context, _) => Opacity(
                          opacity: 1.0 - _badgeExit.value,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: _ShineText(
                              'POWERED BY LARAF',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? Colors.grey[300]
                                    : Colors.grey[500],
                                letterSpacing: 3.2,
                              ),
                              shine: _shine,
                            ),
                          ),
                        ),
                      ),
                      // Человечек наложен ВНЕ потока СЛЕВА от «W» — он
                      // не сдвигает центрированный текст. Живёт весь сплэш
                      // и плавно растворяется в последние 400 мс (_badgeExit),
                      // то есть исчезает в КОНЦЕ, когда сплеш уходит на
                      // контент.
                      Positioned(
                        left: -34,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: AnimatedBuilder(
                            animation: Listenable.merge([
                              _badgeExit,
                              _fadeAnimation,
                            ]),
                            builder: (context, _) => Opacity(
                              // В начале — невидим, проявляется вместе с текстом
                              // Wetcorp. (_fadeAnimation); в конце плавно
                              // растворяется (_badgeExit). Ничего не «доезжает».
                              opacity:
                                  _fadeAnimation.value *
                                  (1.0 - _badgeExit.value),
                              child: _LevitationBadge(
                                t: _float,
                                color: accent,
                                isDark: isDark,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подпись, по которой катится та же полоса, что по «стеклу» авы, но
/// полупрозрачным кроваво-красным.
///
/// Два слоя: базовая строка плюс ОНА ЖЕ строка, залитая «кровью» и обрезанная
/// по бегущему градиенту (`ShaderMask` + `srcIn`, где маска работает по
/// альфе глифов). Одной маской нельзя — вне полосы подпись стала бы дырой.
/// Огибающая яркости и кривая хода взяты один-в-один из [_GlassSweepPainter],
/// поэтому два блеска едут синхронно и оба начинаются/кончаются нулём.
class _ShineText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// Ход полосы, тот же `CurvedAnimation`, что у авы (окно 680→1760 мс).
  final Animation<double> shine;

  const _ShineText(this.text, {required this.style, required this.shine});

  /// Цвет блеска — фиксированная «кровь», не primary: фирменная подпись
  /// должна одинаково читаться во всех темах, включая grok и rose.
  static const Color _blood = Color(0xFFB3121F);

  /// Половина ширины полосы в координатах Alignment (по горизонтали).
  static const double _half = 0.55;

  /// Сердцевина полосы — чуть высветлённая «кровь». Не белый: белое ядро
  /// вместе и так невысокой альфой делало полосу почти невидимой на светлом
  /// фоне, а полосы пользователь не видел вовсе.
  static Color _hot(double a) =>
      Color.lerp(_blood, Colors.white, 0.30)!.withValues(alpha: a);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shine,
      child: Text(text, style: style),
      builder: (context, base) => Stack(
        alignment: Alignment.center,
        children: [
          base!,
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (rect) => _band(rect, shine.value),
              blendMode: BlendMode.srcIn,
              // Тот же стиль без изменений: srcIn берёт отсюда только альфу
              // глифов, а метрики обязаны совпасть с базовой строкой.
              child: Text(text, style: style),
            ),
          ),
        ],
      ),
    );
  }

  /// Полоса: кровавые кромки → светлое ядро → кровавые кромки. Оба конца
  /// обязаны быть нулевой яркости и нулевой скорости, иначе блик «включается»
  /// и «выключается» кадром: яркость — огибающая sin(π·t), положение —
  /// easeInOutSine (там же скорость 0). Потолок альфы держит подпись
  /// полупрозрачной.
  Shader _band(Rect rect, double t) {
    // Огибающая без степени: sin(π·t) в середине хода даёт ровно 1, то есть
    // в центре полосы глифы залиты цветом ПОЛНОСТЬЮ. Прежнее sin^1.35 с
    // альфой 0.62–0.95 оставляло базовый цвет проступать на треть — на
    // светлом фоне это выглядело как «ничего не блеснуло».
    final a = math.sin(math.pi * t).clamp(0.0, 1.0);
    final cx =
        -1.0 - _half + (2.0 + 2.0 * _half) * Curves.easeInOutSine.transform(t);
    return LinearGradient(
      begin: Alignment(cx - _half, 0),
      end: Alignment(cx + _half, 0),
      colors: [
        _blood.withValues(alpha: 0),
        _blood.withValues(alpha: 0.92 * a),
        _hot(0.98 * a),
        _blood.withValues(alpha: 0.92 * a),
        _blood.withValues(alpha: 0),
      ],
      stops: const [0.0, 0.26, 0.5, 0.74, 1.0],
    ).createShader(rect);
  }
}

/// Полоса блика, катящаяся по «стеклу» карточки логотипа.
///
/// [t] — ход 0 → 1 одного прохода. Оба конца обязаны быть нулевой яркости и
/// нулевой скоростью, иначе блик «включается» и «выключается» кадром:
/// яркость — огибающая sin(π·t) (на старте и финише ровно 0), положение —
/// easeInOutSine (там же скорость 0).
///
/// Блик СОБРАН ИЗ ЧЕТЫРЁХ СЛОЁВ, а не одной размазанной полосы: тонкая почти
/// белая «нить» в центре (даёт остриё), вокруг неё узкое яркое ядро с крутыми
/// скатами, под ними слабое широкое гало, а впереди — тёмный контактный кант.
/// Одна широкая полоса читалась как «помазанная кистью» дымка; нить и крутые
/// скаты дают резкий отсвет, как от глянца на керамике.
///
/// Тёмный кант идёт ПЕРЕД ядром: без него белый блик физически невидим на
/// светлой теме (белым по белому ярче не стать) — он и делает полосу
/// читаемой на любой заливке.
class _GlassSweepPainter extends CustomPainter {
  final double t;

  /// Радиус скругления плиты: блик клипается по нему ПРЯМО на канвасе
  /// (`canvas.clipRRect`), чтобы не платить за виджетный `ClipRRect`
  /// (он создаёт saveLayer на каждый кадр).
  final double radius;

  /// Верхняя точка яркости: на тёмном стекле блик читается сильнее,
  /// поэтому темой задаётся разная глубина.
  final double strength;

  /// Цвет блика — фирменная «кровь», та же, что у подписи POWERED BY LARAF
  /// (см. [_ShineText]). Белый блик по белой плите в светлой теме почти не
  /// читался; кровавая полоса видна и на белом, и на тёмном, и перекликается
  /// с подписью — ава и текст блестят ОДНИМ материалом.
  static const Color _blood = Color(0xFFB3121F);

  const _GlassSweepPainter({
    required this.t,
    required this.strength,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    // Степень 1.6 вместо 1.35: вспышка набирает и отдаёт яркость резче, из-за
    // чего проход читается как короткая искра, а не как долгий разлив.
    final env = math.pow(math.sin(math.pi * t), 1.6).toDouble() * strength;
    if (env <= 0.004) return;

    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    // Чуть круче прежних 36°: острый скол света на скруглённом углу плиты.
    const angle = -math.pi / 4.2;
    final cx =
        -diagonal * 1.05 + Curves.easeInOutSine.transform(t) * diagonal * 2.1;

    canvas.save();
    // Клип по скруглению плиты на канвасе, а не виджетом: saveLayer не нужен.
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ),
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);

    // Полоса с настраиваемым профилем: stops задают «скат» (чем ближе крайние
    // stops к 0.5, тем острее пик), peak — альфу вершины. Края всегда
    // прозрачны, иначе полоса включается и выключается видимой кромкой.
    void band(
      double center,
      double width,
      int peak, {
      bool dark = false,
      List<double> stops = const [0.0, 0.5, 1.0],
      Color? color,
    }) {
      if (peak <= 1) return;
      // strength > 1 (светлая тема) разгоняет вершину выше 255 — withValues
      // такое значение не принимает, поэтому подрезаем к пределу альфы.
      peak = peak > 255 ? 255 : peak;
      final r = Rect.fromLTWH(
        center - width / 2,
        -diagonal,
        width,
        diagonal * 2,
      );
      final hot =
          color ?? (dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
      final solid = hot.withValues(alpha: peak / 255);
      final colors = [
        for (var i = 0; i < stops.length; i++)
          (i == 0 || i == stops.length - 1) ? solid.withValues(alpha: 0) : solid,
      ];
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: colors,
            stops: stops,
          ).createShader(r),
      );
    }

    // 1. Тёмный контактный кант — узкий и впереди ядра. Единственная
    //    НЕкрасная полоса: без него кровавое ядро на белой плите сливалось
    //    бы с фоном и блик «не показывался».
    band(
      cx - diagonal * 0.11,
      diagonal * 0.12,
      (0.14 * env * 255).round(),
      dark: true,
    );
    // 2. Широкое слабое гало — мягкая кровавая подсветка вокруг искры.
    band(cx, diagonal * 0.30, (0.20 * env * 255).round(), color: _blood);
    // 3. Узкое ядро с крутыми скатами — плотная кровь (плато в середине).
    band(
      cx,
      diagonal * 0.11,
      (0.88 * env * 255).round(),
      color: _blood,
      stops: const [0.0, 0.42, 0.5, 0.58, 1.0],
    );
    // 4. Тонкая «нить» по центру — остриё блеска. Чуть высветленная кровь
    //    (не белая): держит остриё читаемым, оставаясь красной.
    band(
      cx,
      diagonal * 0.022,
      (0.95 * env * 255).round(),
      color: Color.lerp(_blood, Colors.white, 0.28)!,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassSweepPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.strength != strength ||
      oldDelegate.radius != radius;
}

/// Разбитое стекло поверх плиты авы: скол расходится из точки удара.
///
/// Геометрия детерминирована (фиксированный seed): при перерисовке кадра
/// трещины стоят на месте, а не «кипят». Слой кэшируется RepaintBoundary,
/// поэтому растр лежит готовым и не грузит бюджетные телефоны.
///
/// Точка удара смещена от центра (0.30, 0.32) — если бить по центру, скол
/// приходится ровно на логотип и читается хуже.
class _ShatteredGlassPainter extends CustomPainter {
  final bool isDark;

  const _ShatteredGlassPainter({required this.isDark});

  // Точка удара в долях стороны плиты.
  static const Offset _impact = Offset(0.30, 0.32);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final impact = Offset(_impact.dx * w, _impact.dy * h);

    // Фиксированный seed: скол детерминирован и не мерцает между кадрами.
    final rng = math.Random(4711);

    final crackLight = Colors.white.withValues(alpha: isDark ? 0.58 : 0.88);
    final crackDark = Colors.black.withValues(alpha: isDark ? 0.58 : 0.34);
    final spot = Colors.white.withValues(alpha: isDark ? 0.17 : 0.30);

    // Пятна напряжения вокруг удара — светлые разводы на «стекле».
    for (var i = 0; i < 5; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final d = rng.nextDouble() * 0.32;
      final c = Offset(
        impact.dx + math.cos(a) * d * w,
        impact.dy + math.sin(a) * d * h,
      );
      final rr = w * (0.06 + rng.nextDouble() * 0.09);
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..shader = RadialGradient(
            colors: [spot, spot.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: rr)),
      );
    }

    // Радиальные трещины: ломаная линия с изломом на каждом шаге, поэтому
    // скол читается как настоящий, а не как ровный «луч».
    const spokes = 11;
    final span = math.sqrt(w * w + h * h) * 0.5;
    for (var i = 0; i < spokes; i++) {
      final a = (i / spokes) * math.pi * 2 + rng.nextDouble() * 0.28;
      final reach = 0.62 + rng.nextDouble() * 0.62;
      final steps = 3 + rng.nextInt(3);
      final stepLen = span * reach / steps;
      final path = Path()..moveTo(impact.dx, impact.dy);
      var x = impact.dx;
      var y = impact.dy;
      var ang = a;
      for (var j = 0; j < steps; j++) {
        ang += (rng.nextDouble() - 0.5) * 0.5;
        x += math.cos(ang) * stepLen;
        y += math.sin(ang) * stepLen;
        path.lineTo(x, y);
      }
      // Тёмная подложка + светлая линия = скол с бликом на грани.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..color = crackDark,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round
          ..color = crackLight,
      );
    }

    // Концентрические разломы-«паутинка», затухающие к краю.
    const rings = 4;
    for (var r = 1; r <= rings; r++) {
      final rr = (r / rings) * w * 0.72;
      final arcPath = Path();
      var started = false;
      for (var i = 0; i <= 9; i++) {
        final a = (i / 9) * math.pi * 2;
        final wob = 0.82 + rng.nextDouble() * 0.36;
        final x = impact.dx + math.cos(a) * rr * wob;
        final y = impact.dy + math.sin(a) * rr * wob;
        if (!started) {
          arcPath.moveTo(x, y);
          started = true;
        } else {
          arcPath.lineTo(x, y);
        }
      }
      arcPath.close();
      final fade = 1 - r / (rings + 1);
      canvas.drawPath(
        arcPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = crackDark.withValues(
            alpha: (isDark ? 0.30 : 0.18) * fade,
          ),
      );
      canvas.drawPath(
        arcPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = crackLight.withValues(
            alpha: (isDark ? 0.55 : 0.85) * fade,
          ),
      );
    }

    // Яркая точка удара — центр скола.
    canvas.drawCircle(
      impact,
      w * 0.035,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: isDark ? 0.85 : 0.95),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(
          Rect.fromCircle(center: impact, radius: w * 0.06),
        ),
    );
  }

  @override
  bool shouldRepaint(_ShatteredGlassPainter oldDelegate) =>
      oldDelegate.isDark != isDark;
}

/// Левитирующий стикман рядом с подписью «Wetcorp.»
///
/// Всё движение считается из одного хода 0→1 по синусоиде, поэтому цикл
/// бесшовный: человек плавно взлетает и опускается, слегка заваливаясь на
/// боку, кольцо под ногами сжимается и бледнеет ровно тогда, когда он
/// поднимается выше, а искры идут по пологой орбите.
class _LevitationBadge extends StatelessWidget {
  final Animation<double> t;
  final Color color;
  final bool isDark;

  const _LevitationBadge({
    required this.t,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) => RepaintBoundary(
        // Пейнтер рассчитан на абсолютные координаты в 30×36, поэтому
        // уменьшаем целую фигуру через Transform.scale, а не size — иначе
        // картинка просто обрезалась и человечек не становился меньше.
        child: Transform.scale(
          scale: 0.68,
          child: CustomPaint(
            size: const Size(30, 36),
            painter: _LevitationPainter(
              phase: t.value,
              color: color,
              glow: isDark ? 0.30 : 0.20,
            ),
          ),
        ),
      ),
    );
  }
}

class _LevitationPainter extends CustomPainter {
  final double phase;
  final Color color;

  /// Насколько ярким рисовать ореол — на тёмном фоне свечение читается
  /// сильнее, поэтому там оно тише.
  final double glow;

  _LevitationPainter({
    required this.phase,
    required this.color,
    required this.glow,
  });

  static const double _tau = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final p = phase % 1.0;
    final bob = math.sin(_tau * p); // -1 (внизу) .. 1 (наверху)
    final rise = (bob + 1) / 2; // 0 .. 1
    final cx = size.width / 2;
    final cy = size.height * 0.52 - bob * 2.8;
    final tilt = 0.055 * math.sin(_tau * p + math.pi / 2);

    // ── Ореол за спиной ─────────────────────────────────
    canvas.drawCircle(
      Offset(cx, cy - 2),
      13.0,
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: glow * (0.35 + 0.45 * rise)),
            color.withValues(alpha: 0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy - 2), radius: 13)),
    );

    // ── Кольцо-тень под ногами: сжимается, когда он выше ─
    final ringY = size.height * 0.88;
    final rx = 9.0 - 3.4 * rise;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, ringY),
        width: rx * 2,
        height: rx * 0.66,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.34 - 0.20 * rise),
    );

    // ── Искры: пологой орбитой, пульсируют ──────────────
    for (var i = 0; i < 3; i++) {
      // Полный оборот (2π) за цикл, а не половина: при полуобороте на склейке
      // витков искра телепортировалась на противоположную сторону орбиты —
      // тот самый рывок раз в цикл. Теперь угол в p=0 и p=1 совпадает.
      final a = _tau * p + i * (_tau / 3);
      final spark = Offset(cx + math.cos(a) * 12.0, cy - 3 + math.sin(a) * 6.0);
      final pulse = 0.30 + 0.55 * (0.5 + 0.5 * math.sin(_tau * p * 2 + i));
      canvas.drawCircle(
        spark,
        1.0 + 0.5 * pulse,
        Paint()..color = color.withValues(alpha: pulse.clamp(0.0, 1.0)),
      );
    }

    // ── Фигура ──────────────────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(tilt);

    final body = Path()
      ..moveTo(0, -9.4) // шея
      ..lineTo(0, -2.0) // позвоночник
      // Руки подняты вверх-в стороны — классическая поза парения.
      ..moveTo(0, -7.8)
      ..quadraticBezierTo(-4.2, -9.4, -6.6, -13.2)
      ..moveTo(0, -7.8)
      ..quadraticBezierTo(4.2, -9.4, 6.6, -13.2)
      // Ноги свисают вниз и чуть в стороны с мягким прогибом — поза
      // парящего, а не сидящего. Раньше были «скрещены в лотосе» двумя
      // квадратичными дугами из одного бедра: они самопересекались в
      // 30-пиксельном бейдже и вместо ног получалось кольцо на палочке.
      ..moveTo(0, -2.0)
      ..quadraticBezierTo(-3.8, 1.8, -2.9, 6.4)
      ..moveTo(0, -2.0)
      ..quadraticBezierTo(3.8, 1.8, 2.9, 6.4);

    // Сначала широким мягким мазком — свечение, затем чёткий контур.
    for (final (width, alpha) in [(5.0, glow * 0.55), (2.0, 1.0)]) {
      canvas.drawPath(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: alpha),
      );
      canvas.drawCircle(
        const Offset(0, -12.4),
        width == 5.0 ? 3.4 : 3.0,
        Paint()..color = color.withValues(alpha: alpha),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LevitationPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
