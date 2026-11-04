import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../main.dart' show preDecodedLogo;

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

  /// Радиус скругления «стекла» — тот же, что у карточки-сквайркла.
  static const double _kRadius = 30;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    // Блик — окно внутри общего хода: 680→1760 мс. Логотип к этому моменту
    // уже почти проявлен, а до закрытия сплэша остаётся 440 мс, то есть
    // полоса гарантированно проходит ЦЕЛИКОМ и начинается, и заканчивается
    // плавно (яркость на обоих концах хода = 0, скорость тоже).
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
    // Ровно один «вздох» левитации за ВСЁ время сплеша (2200 мс = таймер
    // ухода), бесшовно через sin(2π·p) в пейнтере. Ни замирания в конце,
    // ни рывка: человечек доигрывает цикл именно к моменту, когда экран уходит.
    _float = AnimationController(
      duration: const Duration(milliseconds: 2200),
      vsync: this,
    )..repeat();
    // Человечек доигрывает левитацию и затем мягко растворяется: за
    // последние ~440 мс (t 0.78→0.95, 1560→1900 мс) альфа 1→0. К моменту
    // ухода на контент (1950 мс) он уже полностью погас — поэтому остановка
    // его тикера в этот момент не видна глазу, а кадр перехода не платит
    // за лишнюю перерисовку.
    _badgeExit = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.78, 0.95, curve: Curves.easeIn),
    );
    // Заранее прогреваем кэш логотипа: первый кадр после сплэша
    // не «мигает» и не показывает пустое место.
    //
    // Если логотип уже декодирован в main() (_predecodeSplashLogo), прогрев
    // НЕ повторяем: precacheImage снова декодировал бы ту же 1024×1024 PNG —
    // лишняя работа на старте, ровно на том кадре, где и без неё тесно.
    if (preDecodedLogo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        precacheImage(const AssetImage('assets/keramika.png'), context);
      });
    }
    // Анимация идёт 2 секунды; переходим на главную сразу после её
    // окончания. Раньше стояло 2200 мс — лишние 200 мс «мёртвой паузы»
    // после того, как логотип уже растворился, читались как рывок.
    // 1950 мс: кросс-фейд стартует, пока человечек ещё догасает, поэтому
    // переход читается одним движением, а не «пауза → смена кадра».
    _splashTimer = Timer(const Duration(milliseconds: 1950), () {
      if (!mounted) return;
      // Кросс-фейд на контент уже начался — левитация больше не видна
      // (человечек догас по _badgeExit), но её тикер продолжал бы
      // перерисовывать пейнтер 60 раз в секунду ПОКА строится и проявляется
      // Home (4 экрана). Останавливаем: в кадре перехода мы платим только
      // за проявляющийся контент, а не за два экрана сразу. Мастер-контроллер
      // и блик не трогаем — они к этому моменту уже почти в конце.
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
    _splashTimer?.cancel();
    // CurvedAnimation снимает свой слушатель с мастер-контроллера, поэтому
    // его dispose() идёт ДО dispose родителя. Отдельного таймера старта
    // больше нет — он и ронял smoke-тест на «A Timer is still pending».
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
    // Цвет «глины» для плиты авы. Берём surfaceContainerHighest и заметно
    // подмешиваем primaryContainer: он всегда отличим от фона (в системной
    // теме primary бывает тёмным и плита «чернела»), но остаётся в фирменном
    // оттенке темы. Подмес крупный (0.5+): на малом подмесе плита сливалась с
    // фоном сплэша — тот тоже подмешивает primaryContainer в нижней трети.
    final clayTint = Color.lerp(
      cs.surfaceContainerHighest,
      cs.primaryContainer,
      isDark ? 0.55 : 0.50,
    )!;
    // В светлой теме фон сплэша почти белый, и светлая глина растворялась в
    // нём — подмешиваем primary, чтобы плита читалась отдельным тёплым комком.
    final clay = isDark ? clayTint : Color.lerp(clayTint, cs.primary, 0.16)!;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          // Фон сплэша под темы — как у экрана PIN-кода: градиент от
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
                          // Ава — матовая глиняная плита в цвет ВЫБРАННОЙ темы:
                          // rose → розовая, peach → персиковая, grok → её акцент.
                          // Заранее прогреваем кэш, чтобы логотип не «мигал»
                          // и не появлялся не сразу на слабых телефонах вроде
                          // Redmi Note 12 — первый кадр сразу рисуется с ним.
                          // RepaintBoundary кэширует отрисованную аватарку
                          // текстурой: во время slide/fade-анимации (1800мс)
                          // движется готовый растр, а не перефильтровывается
                          // большая картинка каждый кадр — на слабых
                          // телефонах аватарка не «дёргается».
                          // Блик лежит ОТДЕЛЬНЫМ слоем над всей плитой, а не
                          // внутри картинки: искра должна проходить и по
                          // глиняной кромке, и по самому медальону — только
                          // тогда она читается как отражение на глянце.
                          // Обрезка — своим ClipRRect с тем же радиусом,
                          // поэтому тень карточки (она рисуется ЗА её
                          // габаритом) не подрезается.
                          Stack(
                            children: [
                              // ОБЪЁМНАЯ ГЛИНА: плита не плоская заливка,
                              // а вылепленная масса — светлая грань
                              // сверху-слева и тёмная снизу-справа.
                              //
                              // RepaintBoundary держит готовую текстуру: во
                              // время slide/fade-анимации (1800 мс) движется
                              // растр, а не пересчитываются десятки
                              // градиентов каждый кадр — на слабых телефонах
                              // плита не «дёргается».
                              RepaintBoundary(
                                child: SizedBox(
                                  width: 128,
                                  height: 128,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      // «Скруглый» (squircle) — круглее квадрата,
                                      // но НЕ круг: нижняя подпись на логотипе не
                                      // обрезается кружком и остаётся читаемой.
                                      borderRadius: BorderRadius.circular(
                                        _kRadius,
                                      ),
                                      boxShadow: [
                                        // Мягкая рассеянная тень — плита лежит на
                                        // фоне, а не парит в ореоле.
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: isDark ? 0.45 : 0.16,
                                          ),
                                          blurRadius: 20,
                                          spreadRadius: -4,
                                          offset: const Offset(0, 10),
                                        ),
                                        // Едва заметный цветной ореол вместо
                                        // прежнего яркого свечения.
                                        BoxShadow(
                                          color: accent.withValues(
                                            alpha: isDark ? 0.22 : 0.14,
                                          ),
                                          blurRadius: 24,
                                          spreadRadius: -8,
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(25),
                                      child: DecoratedBox(
                                        // Настоящая ФАСКА вместо «пупырок»: у
                                        // плиты резкая светлая грань сверху-слева
                                        // и тёмная снизу-справа, а середина
                                        // остаётся чистым цветом глины. Переход
                                        // держим близко к кромке (0.0→0.16 и
                                        // 0.84→1.0) — именно резкий перегиб даёт
                                        // «огранку», которую видно в масштабе 1:1;
                                        // плавный градиент читался как грязь.
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color.lerp(
                                                clay,
                                                Colors.white,
                                                isDark ? 0.40 : 0.34,
                                              )!,
                                              clay,
                                              Color.lerp(
                                                clay,
                                                Colors.black,
                                                isDark ? 0.42 : 0.24,
                                              )!,
                                            ],
                                            stops: const [0.0, 0.16, 1.0],
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                // Логотип уже декодирован в main()
                                                // до первого кадра — RawImage
                                                // рисует его мгновенно, без
                                                // «мигания» на слабых телефонах.
                                                if (preDecodedLogo != null)
                                                  RawImage(
                                                    image: preDecodedLogo,
                                                    fit: BoxFit.contain,
                                                    filterQuality:
                                                        FilterQuality.medium,
                                                  )
                                                else
                                                  Image.asset(
                                                    'assets/keramika.png',
                                                    cacheWidth: 512,
                                                    cacheHeight: 512,
                                                    filterQuality:
                                                        FilterQuality.medium,
                                                    isAntiAlias: true,
                                                    fit: BoxFit.contain,
                                                  ),
                                                // ГЛИНЯНАЯ ТОНИРОВКА МЕДАЛЬОНА:
                                                // логотип не остаётся
                                                // «стеклянным» — на него ложится
                                                // тот же глиняный оттенок, что и
                                                // на плиту, поэтому штамп
                                                // читается как вылепленный из той
                                                // же массы.
                                                IgnorePointer(
                                                  child: ColoredBox(
                                                    color: clay.withValues(
                                                      alpha: isDark
                                                          ? 0.18
                                                          : 0.12,
                                                    ),
                                                  ),
                                                ),
                                                // ВДАВЛЕННЫЙ МЕДАЛЬОН: логотип
                                                // не наклеен на плиту, а утоплен в
                                                // неё. Две вещи вместе: КАНАВКА по
                                                // кромке (тонкая тёмная линия по всему
                                                // контуру — она и читается как
                                                // углубление) и НАПРАВЛЕННАЯ фаска
                                                // (тень сверху-слева, свет снизу-
                                                // справа). Раньше здесь были только
                                                // мягкие градиенты поверх яркого
                                                // логотипа — они в нём тонули, и
                                                // вдавленности не было видно.
                                                IgnorePointer(
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                      border: Border.all(
                                                        color: Color.lerp(
                                                          clay,
                                                          Colors.black,
                                                          isDark ? 0.55 : 0.40,
                                                        )!.withValues(
                                                          alpha: isDark
                                                              ? 0.50
                                                              : 0.38,
                                                        ),
                                                        width: 1.6,
                                                      ),
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                        colors: [
                                                          Colors.black.withValues(
                                                            alpha: isDark ? 0.50 : 0.34,
                                                          ),
                                                          Colors.black.withValues(
                                                            alpha: 0.0,
                                                          ),
                                                          Colors.white.withValues(
                                                            alpha: 0.0,
                                                          ),
                                                          Colors.white.withValues(
                                                            alpha: isDark ? 0.20 : 0.30,
                                                          ),
                                                        ],
                                                        stops: const [
                                                          0.0,
                                                          0.12,
                                                          0.88,
                                                          1.0,
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: RepaintBoundary(
                                    child: AnimatedBuilder(
                                      animation: _shine,
                                      builder: (context, _) => ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                          _kRadius,
                                        ),
                                        child: CustomPaint(
                                          painter: _GlassSweepPainter(
                                            t: _shine.value,
                                            // На светлой теме белое ядро по
                                            // белому кольцу не видно ВООБЩЕ —
                                            // поэтому яркость задаётся темой,
                                            // а тёмные кромки полосы делают
                                            // блик читаемым на любом фоне.
                                            strength: isDark ? 0.62 : 0.95,
                                          ),
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
      // Оба текста — готовые child'ы: базовый и под маской. Раньше второй
      // Text создавался В БИЛДЕРЕ, то есть заново на каждом кадре хода
      // (2 с × 60 fps): Flutter каждый раз раскладывал строку заново —
      // это и был заметный «подхруст» подписи. Теперь layout один.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(text, style: style),
          Positioned.fill(
            child: ShaderMask(
              shaderCallback: (rect) => _band(rect, shine.value),
              blendMode: BlendMode.srcIn,
              child: Text(text, style: style),
            ),
          ),
        ],
      ),
      builder: (context, child) {
        // Вне окна хода маска не нужна: полоса прозрачна, а ShaderMask
        // заставляет GPU делать saveLayer каждый кадр. Пока блик не идёт,
        // отдаём только базовую строку — вступительный и финальный отрезки
        // сплэша не платят за saveLayer.
        final t = shine.value;
        if (t <= 0.0 || t >= 1.0) return Text(text, style: style);
        return child!;
      },
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

/// Острый блик-спекуляр, скользящий по глиняной плите авы.
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

  /// Верхняя точка яркости: на тёмной плите белый блик читается сильнее,
  /// поэтому темой задаётся разная глубина.
  final double strength;

  const _GlassSweepPainter({required this.t, required this.strength});

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
          (i == 0 || i == stops.length - 1)
              ? solid.withValues(alpha: 0)
              : solid,
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

    // 1. Тёмный контактный кант — узкий и впереди ядра.
    band(
      cx - diagonal * 0.055,
      diagonal * 0.05,
      (0.14 * env * 255).round(),
      dark: true,
    );
    // 2. Широкое слабое гало — мягкая подсветка вокруг искры.
    band(cx, diagonal * 0.17, (0.11 * env * 255).round());
    // 3. Узкое яркое ядро с крутыми скатами (плато в середине).
    band(
      cx,
      diagonal * 0.055,
      (0.92 * env * 255).round(),
      stops: const [0.0, 0.40, 0.5, 0.60, 1.0],
    );
    // 4. Тонкая почти белая «нить» по центру — остриё блеска.
    band(cx, diagonal * 0.011, 255, color: Colors.white);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassSweepPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.strength != strength;
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
