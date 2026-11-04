import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
import '../widgets/animated_fab_row.dart' show sectionPillVisible;
import '../widgets/icons/keramika_icons.dart';
import '../widgets/press_scale.dart';
import '../widgets/smooth_tooltip.dart';

/// Занимаемая таблеткой высота (отступы 4 + капсула 54 + отступ 6).
/// Таблетка лежит в Stack НАД PageView, поэтому каждый экран-раздел
/// резервирует столько же сверху своего скролла: тогда в покое список
/// начинается под таблеткой, а при прокрутке уходит ПОД стекло.
const double kSectionPillSlotHeight = 64;

/// edgeOffset для RefreshIndicator разделов: кружок (40 px) в покое стоит
/// нижним краем вытягивания под капсулой, а при потягивании ВЫЕЗЖАЕТ ИЗ-ПОД
/// таблетки, а не появляется за ней.
///
/// Позиция круга в Material: низ = edgeOffset + sizeFactor*(displacement+40).
/// При sizeFactor=1 верх круга = edgeOffset + displacement (40) — поэтому
/// edgeOffset = 58 (низ капсулы) - 40 = 18. Увеличили на 6 px, чтобы кружок
/// не налезал на обводку капсулы и не выглядел «слишком高о».
const double kSectionRefreshEdgeOffset = kSectionPillSlotHeight - 6 - 34;

/// Верхний «запретный пояс» для плавающего окошка Ады: статус-бар + шапка +
/// таблетка разделов.
///
/// Окошко Ады — always-on-top поверхность (на Android системный оверлей, на
/// web слой поверх всех экранов), поэтому оно затирает таблетку и её
/// «Полезные/Вредные»: при перетаскивании вверх Ада «залезала» на категории.
/// Пояс считает её НУЛЕВОЙ верхней границей — выше окошко не пускаем ни
/// драгом, ни дрейфом.
double adaTopKeepout(double statusBarHeight) =>
    statusBarHeight + kToolbarHeight + kSectionPillSlotHeight;

// ── Общий стейт таблетки разделов ──────────────────────────────────────
// Таблетка живёт в Home НАД PageView (обычный поток, не поверх контента):
// при переключении разделов она остаётся на месте, а листается только
// содержимое под ней. Её состояние вынесено в общие notifier-ы: Home пишет
// сюда из PageView (текущая страница и её позиция), а тап по разделу Home
// слушает через [sectionTabTap].

/// Текущий выбранный раздел (индекс страницы PageView).
final ValueNotifier<int> sectionCurrentIndex = ValueNotifier<int>(0);

/// Непрерывная позиция страницы — индикатор таблетки следует за ней
/// плавно, без скачков при переходах через 1–2 раздела.
final ValueNotifier<double> sectionRailPage = ValueNotifier<double>(0);

/// Тик тапа по разделу: Home слушает и доезжает до нужной страницы.
final ValueNotifier<int> sectionTabTap = ValueNotifier<int>(0);

/// Тяга по таблетке разделов. Пилюля кладёт сюда ДРОБНУЮ страницу, к которой
/// палец подтянул камень, а Home двигает PageController — разделы едут под
/// пальцем. `null` — тяга закончилась, дальше камень ведёт пружина Home.
///
/// Почему отдельный канал: таблетка не знает ни про PageController, ни про
/// пружину, а Home не должен знать, как устроен жест. Это тот же способ
/// связи, что уже используют [sectionCurrentIndex] и [sectionRailPage].
final ValueNotifier<double?> sectionDragPage = ValueNotifier<double?>(null);

/// Значки разделов: у каждого своя геометрическая фигура.
final List<Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})>
sectionIconBuilders = [
  (context, {size = 17, color, strokeWidth}) => KkAlarmIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kKkStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => KkHabitsIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kKkStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => KkTasksIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kKkStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => KkRealityCheckIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kKkStroke,
  ),
];

/// Названия разделов (для тултипов) — те же, что строит Home: РП-раздел
/// виден только когда проверки реальности включены в настройках.
List<String> sectionLabels(BuildContext context) {
  final rcOn = RealityCheckService().enabled;
  return [
    Translations.alarmsOf(context),
    Translations.habitsOf(context),
    Translations.tasksOf(context),
    if (rcOn) Translations.rcOf(context),
  ];
}

/// Значки разделов с учётом настроек: при выключенных проверках реальности
/// РП-раздел (и его значок) не должен быть виден вообще.
List<Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})>
sectionIconsFor(BuildContext context) {
  final count = sectionLabels(context).length;
  return sectionIconBuilders.sublist(0, count);
}

/// Обёртка таблетки: плавно убирает её вверх при прокрутке вниз и
/// возвращает при долистывании до верха.
///
/// Слушает [sectionPillVisible] (его пишет [FabScrollListener] каждого
/// раздела). Скрытие — мягкий подъём + затухание, а не резкое исчезновение:
/// таблетка «уезжает» вверх вместе с контентом, поэтому прокрутка читается
/// одним движением. Обратно приезжает тем же путём — «закрывается в скролле»
/// и раскрывается симметрично.
///
/// Сдвиг идёт по Transform, а не по высоте слота: layout не пересобирается,
/// скролл-контент разделов не дёргается. Когда таблетка скрыта, она не
/// ловит касания — жест уходит списку.
class SectionPillHost extends StatefulWidget {
  const SectionPillHost({super.key});

  @override
  State<SectionPillHost> createState() => _SectionPillHostState();
}

class _SectionPillHostState extends State<SectionPillHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    sectionPillVisible.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    sectionPillVisible.removeListener(_sync);
    _ctrl.dispose();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    if (sectionPillVisible.value) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_ctrl.value);
        // Таблетка ОСТАЁТСЯ в дереве и держит высоту слота: контент разделов
        // не перекладывается, а список, живущий под ней, не «прыгает» при
        // возврате. При opacity 0 Flutter не рисует ребёнка вовсе
        // (RenderOpacity выходит до paint), так что скрытая таблетка
        // бесплатна по GPU.
        return IgnorePointer(
          ignoring: t < 0.5,
          child: Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, -(1 - t) * kSectionPillSlotHeight),
              child: child,
            ),
          ),
        );
      },
      child: const RepaintBoundary(child: SectionPill()),
    );
  }
}

/// Единая объемная капсула разделов. Названия доступны только в тултипах
/// (показываются НАД таблеткой — иначе прячутся за пальцем), визуально —
/// только иконки в гео-фигурах.
class SectionPill extends StatefulWidget {
  const SectionPill({super.key});

  @override
  State<SectionPill> createState() => _SectionPillState();
}

class _SectionPillState extends State<SectionPill>
    with TickerProviderStateMixin {
  /// Внутренняя ширина капсулы: 304 минус набивка 4 слева и справа. Ровно
  /// столько же занимает жест-дорожка: она лежит в `Stack(StackFit.expand)`.
  /// По этой ширине палец переводится в долю карусели — камень едет ровно
  /// под пальцем.
  static const double _trackWidth = 304 - 4 * 2;

  /// Идёт ли тяга пальцем по таблетке.
  bool _dragging = false;

  /// Signed-тяга пальца за край рельса (-0.72..0.72). Под пальцем —
  /// чистая функция кадра, БЕЗ лага: раньше тяга ходила через общий
  /// ValueNotifier + TweenAnimationBuilder, который догонял цель с лагом
  /// 180–230 мс и перестартовывал на каждом кадре у самого края (duration
  /// zero↔180 мс переключался) — из-за этого камень «мигал и скакал».
  double _edgePull = 0;

  /// Тяга, захваченная в момент отпускания пальца: во время расслабления
  /// камень спадает с неё к нулю.
  double _releasePull = 0;

  /// «Расслабление» после отпускания: один контроллер, 220 мс, easeOut.
  /// Никаких Timer'ов и второго setState.
  late final AnimationController _edgeSettle;

  /// Логарифмический догон камня за пальцем (resistance) ведёт КАЖДЫЙ кадр
  /// отдельным тикером: камень и экраны, запертые 1:1 к нему, едут
  /// МЕДЛЕННЕЕ и ПЛАВНЕЕ пальца — без рывка и без рассинхрона
  /// (то самое «перемещение ultra-быстрое зажатием»).
  late final Ticker _smoothTicker;

  /// Куда палец увёл камень (дробная страница).
  double _dragPage = 0;
  // Сглаженный камень: догоняет цель-палец логарифмически (resistance).
  double _dragSmooth = 0;
  double _dragGrabOffset = 0;

  /// Ближайший раздел на прошлом кадре — по нему звучит хаптик, когда палец
  /// пересекает границу раздела.
  int _dragNearest = -1;

  /// Величина «растяжки-волны» (transit) в момент отпускания пальца. Пока
  /// идёт «расслабление» края ([_edgeSettle]), форма камня затухает от
  /// ЭТОГО зафиксированного значения по той же кривой settle, а не
  /// преследует живую пружину (которая «складывается» в ноль в последний
  /// кадр при лонде в угол — отсюда рывок «резко возвращается в форму»).
  double _releaseWave = 0;

  /// Идёт ли «расслабление после отпускания драга»: в это окно форму камня
  /// ведёт [_releaseWave] (зафиксированный), а не живая пружина. Во время
  /// свободного полёта по тапу (не-драг) растяжение остаётся живым.
  bool _releasing = false;

  /// Последняя вычисленная величина transit-растяжки (волна) — снапшот,
  /// чтобы в момент отпускания понимать, с какой растяжки затухать.
  double _lastWave = 0;

  @override
  void initState() {
    super.initState();
    _edgeSettle =
        AnimationController(
          vsync: this,
          // 480 мс: возврат растяжки на краях читается как «отпустило и
          // медленно вернулось», а не «щёлкнуло обратно». Кривая ниже —
          // симметричная, с нулевой скоростью на обоих концах.
          duration: const Duration(milliseconds: 480),
        )..addStatusListener((status) {
          // Расслабление завершено (или отменено) — сбрасываем захваченную
          // тягу, чтобы она не влияла на следующий жест.
          _releasePull = 0;
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            // «Расслабление» отыграно — растяжение снова ведётся живой
            // формулой (по тапу/следующему драгу).
            _releasing = false;
            _releaseWave = 0;
            _lastWave = 0;
          }
        });
    // Логарифмический догон камня за пальцем идёт КАЖДЫЙ КАДР отдельным
    // тикером (resistance). Камень и экран, запертый 1:1 к нему, из-за
    // этого едут МЕДЛЕННЕЕ и ПЛАВНЕЕ пальца — «тяжёлое» движение без
    // рывка и без рассинхрона.
    _smoothTicker = createTicker(_onSmoothTick);
  }

  /// Кадровый тик резистанса: камень догоняет цель-палец логарифмически и
  /// пишет своё сглаженное значение в общий канал.
  void _onSmoothTick(Duration _) {
    if (!_dragging) {
      _smoothTicker.stop();
      return;
    }
    // Коэффициент 0.30 на кадр (~60 fps): камень мягко отстаёт от пальца,
    // но уже не «плывёт» с заметной задержкой (0.18 читалось как тормоз).
    _dragSmooth += (_dragPage - _dragSmooth) * 0.30;
    if ((_dragPage - _dragSmooth).abs() < 0.001) _dragSmooth = _dragPage;
    sectionDragPage.value = _dragSmooth;
  }

  @override
  void dispose() {
    _smoothTicker.stop();
    _smoothTicker.dispose();
    _edgeSettle.dispose();
    // Экран мог закрыться прямо во время тяги — не оставляем Home с
    // висящей ненулевой страницей.
    if (_dragging) sectionDragPage.value = null;
    super.dispose();
  }

  void _dragStart(DragStartDetails details, int count) {
    if (count < 2) return;
    _dragging = true;
    // Новый жест отменяет «расслабление» предыдущего: камень, ещё
    // растянутый старой тягой, не должен прыгать в ноль по-своему.
    _edgeSettle.stop();
    _edgeSettle.value = 0;
    _releasePull = 0;
    _edgePull = 0;
    // Снимаем «зафиксированную волну» с прошлого отпускания: под новым
    // пальцем растяжение снова ведётся живой формулой.
    _releasing = false;
    _releaseWave = 0;
    _lastWave = 0;

    _dragPage = sectionRailPage.value
        .clamp(0.0, (count - 1).toDouble())
        .toDouble();
    // Камень стартует ровно с позиции пальца — без рывка на захват.
    _dragSmooth = _dragPage;
    // Камень занимает 1/count дорожки и стоит НЕ по центру слота, а с
    // отступами по краям: его центр при page=0 равен halfStone, при
    // page=last — trackWidth-halfStone. Раньше здесь брали
    // `page/(count-1)*trackWidth`, то есть считали, что камень — точка на
    // краю трека. Из-за этого в момент касания камень «прыгал» на
    // половину своей ширины и дальше ехал не под пальцем. Считаем центр
    // честно и запоминаем смещение пальца относительно него.
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final stoneCenter = span <= 0
        ? _trackWidth / 2
        : (_dragPage / (count - 1)) * span + stoneW / 2;
    _dragGrabOffset = stoneCenter - details.localPosition.dx;
    _dragNearest = _dragPage.round();
    sectionDragPage.value = _dragPage;
    // Кадровый резистанс стартует: камень начинает догонять палец
    // логарифмически на каждом кадре.
    _smoothTicker.start();
  }

  void _dragUpdate(DragUpdateDetails details, int count) {
    if (!_dragging) return;
    if (count < 2) return;
    // ПОЗИЦИОННЫЙ скраббер, как выбор приоритета: палец задаёт ЦЕНТР
    // камня, а не долю «от края до края». Камень едет ровно под пальцем.
    //
    // Почему не «дельта пикселей»: раньше палец делился на ширину слота
    // таблетки (~74 px), а карусель ехала на `доля × ширину СТРАНИЦЫ`
    // (~1080 px) — 74 px пальцем уносили контент на целый экран, и движение
    // читалось рывком «не в ту сторону». Здесь жест и содержимое живут в
    // одних долях.
    final x = details.localPosition.dx + _dragGrabOffset;
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final frac = span <= 0
        ? 0.0
        : ((x - stoneW / 2) / span).clamp(0.0, 1.0).toDouble();
    final over = x < 0 ? x : (x > _trackWidth ? x - _trackWidth : 0.0);
    // «Объём до конца»: тяга наливается весь ход пальца за край (до ±72 px),
    // так что камень дышит на всю длину жеста, а не досыпает первую треть.
    // Храним НОРМИРОВАННУЮ долю (-0.72..0.72), как в старой реализации:
    // все формулы ниже (scaleX, capRadius, якорь) рассчитаны на долю.
    // Пропущенный здесь /110 превращал px в 19-кратное раздутие камня.
    _edgePull = (over / 110.0).clamp(-0.72, 0.72);
    // Палец задаёт ЦЕЛЬ камня (точная позиция по дорожке). Сам сдвиг
    // ведёт кадровый тикер [_onSmoothTick]: камень догоняет цель
    // логарифмически (resistance) и пишет сглаженное значение в
    // [sectionDragPage] на каждом кадре. Экраны, запертые 1:1 к нему,
    // из-за этого едут МЕДЛЕННЕЕ и ПЛАВНЕЕ пальца — без рывка и без
    // рассинхрона (то самое «ультрабыстрый перелёт зажатием»).
    _dragPage = (frac * (count - 1)).clamp(0.0, (count - 1).toDouble());
    // Направление «резинки» теперь НЕПРЕРЫВНОЕ (см. stretchDir в
    // _buildStoneRow): знак _edgePull — под пальцем, знак _releasePull
    // (затухающий по _edgeSettle) — в полёте. Дискретный гистерезис
    // `_anchorSide` (±0.15) убран — он «тикал» у углов и дёргал камень.
    final nearest = _dragPage.round();
    if (nearest != _dragNearest) {
      _dragNearest = nearest;
      Haptics.light();
    }
    // sectionDragPage ведёт тикер — здесь не пишем, чтобы не было скачка.
  }

  void _dragEnd(int count) {
    if (!_dragging) return;
    _dragging = false;
    _smoothTicker.stop();
    // Захватываем величину transit-растяжки в точке, где отпустили:
    // по этой величины камень будет ПЛАВНО затухать (см. _releasing в
    // билдере), а не резким броском «складываться» в форму, когда живая
    // пружина долетает до угла.
    _releasing = true;
    _releaseWave = _waveAt(_dragPage, count);
    _lastWave = _releaseWave;
    _startEdgeSettle();
    final target = _dragPage.round().clamp(0, count - 1);
    // Снимаем ручное ведение ДО заказа перелёта: дальше камень ведёт
    // пружина Home, которая стартует с текущей страницы PageView.
    sectionDragPage.value = null;
    // Хаптик на отпускании не дублируем: его даёт _onTabTap в Home, а
    // границы разделов уже «щёлкнули» в _dragUpdate.
    sectionCurrentIndex.value = target;
    // Тап-канал: Home доведёт карусель пружиной от текущего положения, а не
    // «с нуля», поэтому отпускание после тяги не даёт рывка.
    sectionTabTap.value++;
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    _smoothTicker.stop();
    // Отмена (палец ушёл не по сценарию): то же плавное затухание
    // transit-растяжки от зафиксированной величины.
    _releasing = true;
    _releaseWave = _waveAt(_dragPage, sectionIconsFor(context).length);
    _lastWave = _releaseWave;
    _startEdgeSettle();
    sectionDragPage.value = null;
    final count = sectionIconsFor(context).length;
    if (count > 1) {
      final target = sectionRailPage.value.round().clamp(0, count - 1);
      sectionCurrentIndex.value = target;
      sectionTabTap.value++;
    }
  }

  /// Величина transit-растяжки (wave) для дробной страницы [page] из
  /// [count] разделов: пик у порогов раздела, ноль в центре секции.
  /// Одна формула и в билдере (живая), и в момент отпускания (снапшот),
  /// чтобы «зафиксированная волна» точно совпадала с той, что палец
  /// «отпустил» — иначе в первый кадр отпускания форма бы просела.
  double _waveAt(double page, int count) {
    final p = page.clamp(0.0, (count - 1).toDouble());
    final transit = (p - p.roundToDouble()).abs();
    final t2 = transit * 2.0; // 0..1 (0 — покой в центре секции)
    // Та же формула, что в билдере: амплитуда 1.0, квадратичная кривая.
    return 1.0 * (1.0 - (1.0 - t2) * (1.0 - t2));
  }

  /// «Расслабление» камня после отпускания пальца: захватываем текущую
  /// растяжку и плавно уводим её к нулю (220 мс, easeOut) — камень «сам
  /// отпускает» край, а не соскакивает. До этого было Timer + второй
  /// setState: двойная пересборка в один кадр дёргала камень вбок.
  void _startEdgeSettle() {
    if (!_dragging && _edgePull == 0) return;
    _releasePull = _edgePull;
    _edgeSettle
      ..stop()
      ..value = 0
      ..forward();
    _edgePull = 0;
  }

  @override
  Widget build(BuildContext context) {
    final labels = sectionLabels(context);
    final iconBuilders = sectionIconsFor(context);
    final count = iconBuilders.length;
    if (count == 0) return const SizedBox.shrink();

    // КАПСУЛА (заливка, обводка, тень) не зависит от положения индикатора,
    // поэтому лежит отдельным НЕПОДВИЖНЫМ слоем под движущимся: пока камень
    // едет, капсула не перестраивается вообще. Экземпляр капсулы — const:
    // элемент дерева не пересобирается даже при перестройке родителя.
    return Padding(
      // Таблетка в Home чуть выше (под AppBar), компактный отступ.
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Center(
        child: SizedBox(
          width: 304,
          height: 54,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const _GlassCapsule(child: SizedBox.expand()),
              Padding(
                padding: const EdgeInsets.all(4),
                child: ClipRRect(
                  clipBehavior: Clip.none,
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedBuilder(
                    // ЕДИНЫЙ слушатель на все 4 канала (вместе с _edgeSettle
                    // внутри _buildStoneRow): раньше здесь были ДВА вложенных
                    // AnimatedBuilder (внешний без _edgeSettle, внутренний с
                    // _edgeSettle) — на каждый тик любого notifier'а кадр
                    // пересобирался ДВАЖДЫ (внешний билдер прогнал дерево,
                    // потом внутренний снова). На Adreno это дало микрофризы.
                    // Теперь _buildStoneRow сам вешает _edgeSettle через
                    // merge внутри, и здесь только прокидываем rawPage.
                    animation: Listenable.merge([
                      sectionCurrentIndex,
                      sectionDragPage,
                      sectionRailPage,
                    ]),
                    builder: (context, _) {
                      final current = sectionCurrentIndex.value;
                      final dragPage = sectionDragPage.value;
                      final page = sectionRailPage.value;
                      final cs = Theme.of(context).colorScheme;
                      final dark =
                          Theme.of(context).brightness == Brightness.dark;
                      final rawPage = _dragging && dragPage != null
                          ? dragPage.clamp(0.0, (count - 1).toDouble())
                          : page.isFinite
                          ? page
                          : current.toDouble();
                      return _buildStoneRow(
                        context: context,
                        cs: cs,
                        dark: dark,
                        current: current,
                        rawPage: rawPage,
                        count: count,
                        icons: iconBuilders,
                        labels: labels,
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStoneRow({
    required BuildContext context,
    required ColorScheme cs,
    required bool dark,
    required int current,
    required double rawPage,
    required int count,
    required List<
      Widget Function(BuildContext context, {double size, Color? color, double? strokeWidth})
    >
    icons,
    required List<String> labels,
  }) {
    final p = rawPage.clamp(0.0, (count - 1).toDouble());
    final selectedIndex = p.round().clamp(0, count - 1);
    final indicatorAlignment = count == 1
        ? 0.0
        : -1.0 + (2.0 * p / (count - 1));

    // Лёгкая «резинка»: в полёте камень чуть
    // вытягивается и мягко закругляется. Никаких
    // бликов и переливов — движение читается само,
    // без световых наклеек поверх таблетки.
    //
    // «Резинка» выбранной вкладки: чем дальше палец от центра текущей
    // секции, тем сильнее камень «наливается» и вытягивается в сторону
    // следующей. Именно это и есть РАСТЯЖЕНИЕ выбранной таблетки при
    // перетягивании. Раньше wave замораживали на 0 под пальцем — и
    // растяжение пропало совсем; оставили лишь 50 % амплитуды, чтобы
    // было видно, но без «дёргания» (плавная кривая t2 не скачет).
    final transit = (p - p.roundToDouble()).abs();
    final t2 = transit * 2.0; // 0..1 (0 — покой в центре секции)
    // Под пальцем резинка почти полная (0.85): выбранная вкладка
    // наглядно «наливается» по ходу к следующей секции — именно это
    // и есть РАСТЯЖЕНИЕ выбранной таблетки при перетягивании. В свободном
    // полёте (пружина) амплитуда максимальная (1.0).
    // АМПИТУДА ВИНЬЕТКИ: волна пиков у ПОРОГОВ раздела (t2≈1, t.е. у
    // «углов», где раздел граничит со следующим) и почти ноль в центре.
    // Чуть сильнее в полёте (1.0), под пальцем (0.9) — чтобы растяжение
    // выбранного угла читалось отчётливо, но не «раздувалось» рывком.
    // Снапшот живой транзитной волны (stretch в середине секции): держим в
    // [_lastWave], чтобы в момент отпускания понимать, с какой величины
    // затухать. Сама смена «живая → затухающая» происходит ВНУТРИ
    // внутреннего AnimatedBuilder (см. ниже), где она ведётся по _edgeSettle.
    _lastWave = 1.0 * (1.0 - (1.0 - t2) * (1.0 - t2));
    // «Расслабление» камня после отпускания: он сползает с _releasePull к
    // нулю по _edgeSettle (220 мс, easeOut). Под пальцем — 1:1 (_edgePull),
    // БЕЗ лага. TweenAnimationBuilder убран: он догонял цель с лагом
    // 180–230 мс и перезапускался у самого края (duration zero↔180
    // переключался на каждом кадре) — это и была «мигалка/скачок».
    //
    // Важно: слушаем не только _edgeSettle, а и три канала тяги
    // (current/drag/rail). Во время перетягивания _edgeSettle стоит на
    // паузе, и если бы билдер слушал только его, камень НЕ растягивался бы
    // и не следовал за пальцем («растягивания выбранной нет вообще»).
    // Мerged-listenable пересобирает камень на каждый тик любого из них.
    return AnimatedBuilder(
      animation: Listenable.merge([
        _edgeSettle,
        sectionCurrentIndex,
        sectionDragPage,
        sectionRailPage,
      ]),
      builder: (context, _) {
        // СИММЕТРИЧНАЯ кривая: easeOutCubic в первом кадре сбрасывал ~15 %
        // растяжки — на крайних разделах это читалось как «соскочило и
        // дёргано возвращается». easeInOutCubic стартует и финиширует с
        // нулевой скоростью — камень плавно «отпускает» край.
        final settle = Curves.easeInOutCubic.transform(_edgeSettle.value);
        // ВОЛНА УГЛОВ: в обычном полёте (тап/пружина) — живая [_lastWave];
        // в окне «расслабления после отпускания драга» — ЗАФИКСИРОВАННАЯ
        // [_releaseWave], плавно затухающая по той же кривой easeInOutCubic.
        // Раньше в этом окне шёл _lastWave (живая пружина), который в
        // последнем кадре лонда резко падал в 0 — «резко возвращается
        // в форму». Теперь отпускание формы идёт синхронно с краем.
        final wave = _releasing
            ? _releaseWave * (1.0 - settle)
            : _lastWave;
        final stretch = _dragging ? _edgePull : _releasePull * (1.0 - settle);
        final edgeStretch = stretch.abs();
        // НЕПРЕРЫВНОЕ направление растяжки (заменяет дискретный
        // _anchorSide): под пальцем — знак _edgePull, в полёте — знак
        // _releasePull, затухающий по settle. Полностью гладкое, без
        // рывков 1→0→-1 у углов (сам источник «дёргает в углу»).
        final stretchDir = _dragging
            ? _edgePull.sign.toDouble().clamp(-1.0, 1.0)
            : _releasePull.sign.toDouble().clamp(-1.0, 1.0) * (1.0 - settle);
        // ОБЪЁМНЫЙ СЛОЙ: «резинка» (wave) — наливка/растяжение выбранной
        // вкладки по ходу к СЛЕДУЮЩЕЙ секции. Под пальцем амплитуда ~0.85,
        // в свободном полёте — 1.0 (см. выше). Это и есть то самое
        // РАСТЯЖЕНИЕ выбранной таблетки при перетягивании, которого не
        // хватало: раньше scaleX по ходу секции был константой 1.0 и камень
        // просто «ехал», не набухая.
        //
        // Единая визуальная растяжка кадра: крайняя тяга (edgeStretch) +
        // волна-резинка (wave). Оба вливаются в один коэффициент, чтобы
        // масштаб/скругление/якорь считались из одного числа — камень дышит
        // ровно за пальцем, без раздельных скачков.
        // Растяжение ВЫБРАННОГО УГЛА: у порогов раздела (в полёте, t2≈1)
        // волна пиков, и в этот момент выбранная «камень» заметно
        // вытягивается и округляется в сторону следующего раздела —
        // это и есть «растяжение в углах», которого раньше не было
        // вообще. Amplitude 0.55 + capRadius 7.0 держат эффект
        // видимым, `math.min(0.85, ...)` не даёт камню раздуться.
        // АМПИТУДА РАСТЯЖЕНИЯ В УГЛАХ: раньше коэффициент волны в
        // visualStretch был 0.55 и capRadius +7 — в полёте между
        // разделами растяжение «проскальзывало» и читалось как «его
        // нет вообще». Усилили до 0.72 / +9: у порогов раздела (t2≈1,
        // wave→1) камень заметно вытягивается и округляется в сторону
        // следующего раздела — «растяжение в углах» снова отчётливое.
        final visualStretch = math.min(0.98, edgeStretch + 0.90 * wave);
        // Радиус угла 10.0: растянутая таблетка округляется заметно.
        final capRadius = 22.0 + 10.0 * visualStretch;

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            // Позиция камня непрерывна всегда: `indicatorAlignment`
            // (linear по p) — раньше при тяге за край Align переключался
            // мгновенно на -1/+1 (скачок «мигал в стороны»). Теперь
            // X-координата камня идёт одним числом в любой момент.
            Align(
              alignment: Alignment(indicatorAlignment, 0),
              // Эффект ГЛУБИНЫ: в полёте камень слегка «отоходит» назад и
              // плавно возвращается — ощущение, что таблетка «опускается» в экран.
              // Под пальцем (dragging) эффект выключен: только чистая растяжка.
              child: Transform.translate(
                // Эффект ГЛУБИНЫ при приземлении на угол: чем сильнее камень
                // растянут (visualStretch — непрерывная величина: под
                // пальцем = _edgePull + wave, после отпускания сползает по
                // _edgeSettle), тем чуть «выше» он парит; в центре секции
                // (stretch = 0) садится ровно. ВЕЗДЕ — одна и та же формула
                // (без ветки по _dragging): раньше «в полёте 0 / под
                // пальцем -3px» дёргало камень вертикально на моменте
                // отпускания — тот самый «дереж/лаг в углах».
                offset: Offset(0, -2.6 * visualStretch),
                child: Transform.scale(
                  // Масштаб считается прямо из stretch — БЕЗ tween'а:
                  // под пальцем 1:1 за движением (zero latency), после
                  // отпускания stretch спадает по _edgeSettle (easeOut).
                  // TweenAnimationBuilder здесь давал лаг 180–230 мс и
                  // «мигал» у края (перезапуск при переключении duration).
                  //
                  // Якорь растяжки — непрерывный lerp по signed-тяге:
                  // stretchDir (-1..0..1, всегда непрерывный) × edgeStretch,
                  // без дискретных переключений Alignment.center/Left/Right.
                  // Раньше здесь был _anchorSide (гистерезис ±0.15) — дискретный
                  // переключатель дёргал якорь вбок у углов («дереж»).
                  alignment: Alignment(
                    math.max(
                      -1.0,
                      math.min(1.0, -stretchDir * visualStretch * 2.0),
                    ),
                    0,
                  ),
                  // Растяжка читается ИЗ visualStretch: под пальцем камень
                  // вытягивается по ходу секции (wave) и за крайом (edgeStretch),
                  // после отпускания — сползает по _edgeSettle. Единый
                  // коэффициент, без дискретных переключений.
                  scaleX: 1.0 + 0.42 * visualStretch,
                  // Layout-ширина — КОНСТАНТА (слот/карантин, не зависит от
                  // breath). Дышащий масштаб идёт через Transform — иначе
                  // каждый кадр пересобирался layout, камень «дёргался».
                  child: FractionallySizedBox(
                    widthFactor: 1.0 / count,
                    heightFactor: 1,
                    child: RepaintBoundary(
                      child: _GlassStone(
                        capRadius: capRadius,
                        primary: cs.primary,
                        dark: dark,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Тяга пальцем: как в выборе приоритета — камень
            // едет за пальцем, а отпускание доводит его до
            // ближайшего раздела пружиной Home. Тап по иконке
            // при этом остаётся тапом: арбитр жестов отдаёт
            // победу перетаскиванию при сдвиге, а при
            // отпускании без движения — тапу.
            //
            // DragStartBehavior.down — драг стартует СРАЗУ от
            // касания, без порога в 18 px. С ним «зажал и
            // повёл» отзывается сразу, как приоритет. Со
            // штатным .start жест не начинался, пока палец не
            // уезжал за slop, и на практике читалось как «не
            // работает вовсе».
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onHorizontalDragStart: (d) => _dragStart(d, count),
              onHorizontalDragUpdate: (d) => _dragUpdate(d, count),
              onHorizontalDragEnd: (_) => _dragEnd(count),
              onHorizontalDragCancel: _dragCancel,
              child: Row(
                children: List.generate(count, (i) {
                  final label = i < labels.length ? labels[i] : '';
                  final proximity = (1.0 - (p - i).abs()).clamp(0.0, 1.0);
                  final isSelected = selectedIndex == i;
                  // Фигура и иконка квантуются ОДНИМ числом (48 ступеней).
                  // Раньше фигура шла по 12 ступеням, а иконка — непрерывно
                  // по каждому кадру: два слоя меняли цвет в разном темпе и
                  // «проскальзывали» друг относительно друга — это и было
                  // мерцание при перетяжке. Теперь одна сетка ступеней у
                  // обоих: смена цвета дискретная, но 48 ступеней на секцию
                  // глазом не отделяются от непрерывности (шаг ≈ 2 %), а
                  // CustomPaint перерисовывается лишь на смене ступени —
                  // без мерцания и без шейдерного шторма на каждый кадр.
                  final badgeT = (proximity * 48).round() / 48;
                  // Чернила глифа: фирменный primary на нейтральном бейдже
                  // и onPrimary на выбранном. Раньше в тёмной теме был
                  // onSurfaceVariant — светлый глиф на светлом бейдже, контраст
                  // падал до 2.2 и значки читались как «мыло».
                  final iconColor = Color.lerp(
                    cs.primary,
                    cs.onPrimary,
                    badgeT,
                  );
                  return Expanded(
                    // Подсказка возвращена. Её long-press раньше
                    // крал протяжку: арбитр жестов ждал 350 мс,
                    // и тяга начиналась только после зависания
                    // («через жопу»). Теперь жест стартует сразу
                    // от касания (DragStartBehavior.down), а
                    // ожидание тултипа длиннее (500 мс) — на
                    // быстром «зажал и повёл» успевает выиграть
                    // протagonистка. Пока палец УДЕРЖИВАЕТСЬ без
                    // движения, тултип по-прежнему покажется.
                    child: SmoothTooltip(
                      message: label,
                      waitDuration: const Duration(milliseconds: 500),
                      preferredAbove: true,
                      child: Semantics(
                        button: true,
                        selected: isSelected,
                        label: label,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(21.5),
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            // Переключение — ТОЛЬКО при ОТПУСКАНИИ пальца (onTap).
                            // Касание/свайп по таблетке не меняет активный раздел «на лету».
                            onTap: () {
                              if (!mounted) return;
                              Haptics.select();
                              sectionCurrentIndex.value = i;
                              sectionTabTap.value++;
                            },
                            child: Center(
                              child: PressScale(
                                // Во время драга камня инвертируем плавное
                                // зажатие: палец и так ведёт жёст, и
                                // дополнительная отдача в этот момент
                                // «сбивает» рисунок иконки под пальцем.
                                enabled: !_dragging,
                                pressedScale: 0.88,
                                duration: const Duration(milliseconds: 160),
                                releaseDuration: const Duration(
                                  milliseconds: 260,
                                ),
                                child: _GeoBadge(
                                  index: i,
                                  size: 31,
                                  dark: dark,
                                  // Невыбранная — заметный
                                  // фирменный оттенок (чтобы
                                  // фигуры читались), выбранная —
                                  // сочный градиентный «камень».
                                  // Невыбранная — нейтральная приподнятая
                                  // площадка (без «глины» и цветной каши),
                                  // выбранная — сплошной primary. Обе дают
                                  // чёткий контраст с глифом.
                                  color: Color.lerp(
                                    dark
                                        ? cs.surfaceContainerHighest
                                        : cs.surfaceContainerLowest,
                                    cs.primary,
                                    badgeT,
                                  )!,
                                  child: icons[i](
                                    context,
                                    size: _GeoBadge.iconSizeFor(i),
                                    strokeWidth: 2.4,
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
            ),
          ],
        );
      },
    );
  }
}

/// Капсула разделов — плотная матовая «глина»: один градиент, тонкая
/// фирменная обводка и мягкая тень под ней.
///
/// Никакого стекла, витражных пятен и бликов: они читались как грязь
/// по центру таблетки, а в тёмной теме ещё и спорили с выбранным разделом —
/// глаз цеплялся за пятна вместо иконок. Плоская заливка рисуется одним
/// слоем и не перестраивается в полёте камня.
class _GlassCapsule extends StatelessWidget {
  final Widget child;

  const _GlassCapsule({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // ПЛОСКИЙ нейтральный фон: одна непрозрачная поверхность и мягкая тень.
    // Раньше здесь была «глиняная» лепнина — подмес primaryContainer плюс
    // градиент, — из-за чего капсула желтела/розовела и спорила с фигурами.
    // Значки должны читаться на спокойном фоне, а не на цветной массе.
    final base = dark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest;
    return DecoratedBox(
      // Тень снаружи клипа: внутри скругления она обрезается и капсула
      // выглядит наклеенной.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.22 : 0.10),
            blurRadius: 12,
            spreadRadius: -3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: base,
            border: Border.all(
              // Тонкая обводка только для контура, без неоновой рамки.
              color: cs.outlineVariant.withValues(alpha: dark ? 0.55 : 0.70),
              width: 1.0,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Выбранный раздел — «камень»: сплошная заливка цветом темы с мягким
/// затемнением к низу и тенью под ним.
///
/// Раньше это было стекло с зеркальным бликом, бегущей полосой и белыми
/// каплями внутри. В тёмной теме такой камень вспыхивал при каждом
/// переключении: глаз ловил блик, а не раздел. Теперь движение камня — само
/// по себе акцент, без световых эффектов поверх.
class _GlassStone extends StatelessWidget {
  final double capRadius;
  final Color primary;
  final bool dark;

  const _GlassStone({
    required this.capRadius,
    required this.primary,
    required this.dark,
  });

  @override
  Widget build(BuildContext context) {
    // Камень — ОДИН тон: в светлой теме берём primary чуть приглушённый,
    // в тёмной — primary приглушён к чёрному (иначе «горит»). Вместо
    // двуступенчатого градиента (который на слабом железе читается как
    // «грязное пятно» при каждом перемещении) — монохромная заливка с
    // едва различимым затемнением к низу (0.06), чтобы объём остался.
    final fill = dark
        ? Color.lerp(primary, Colors.black, 0.14)!
        : Color.lerp(primary, Colors.white, 0.06)!;
    final shade = dark
        ? Color.lerp(fill, Colors.black, 0.18)!
        : Color.lerp(fill, Colors.black, 0.06)!;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(capRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.34 : 0.16),
            blurRadius: 6,
            spreadRadius: -2,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(capRadius),
        child: DecoratedBox(
          // Мягкое градиентное «дно» — не резкий переход двух цветов,
          // а едва заметное углубление к низу (одна палитра).
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(capRadius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [fill, shade],
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(capRadius),
              border: Border.all(
                // Едва заметная кромка — только чтобы контур читался.
                color: Colors.white.withValues(alpha: dark ? 0.10 : 0.16),
                width: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Значок раздела: иконка сидит внутри своей «драгоценной» фигуры
/// (круг, скруглённый квадрат, ромб, звезда). У каждого раздела свой контур.
/// Фигура вылеплена из глины: свет сверху-слева, тень снизу-справа,
/// мягкий рельеф по кромке — не глянец, а объём.
class _GeoBadge extends StatelessWidget {
  final int index;
  final double size;
  final Color color;
  final bool dark;
  final Widget child;

  const _GeoBadge({
    required this.index,
    required this.size,
    required this.color,
    required this.dark,
    required this.child,
  });

  /// Размер глифа внутри фигуры. Раньше глиф рисовался в 17 px и затем
  /// вписывался в бокс 15.5 px — двойное масштабирование размывало штрих.
  /// Теперь размер задаётся один раз: у «колючих» фигур (ромб, звезда)
  /// глиф мельче, чтобы не вылезать за острые края.
  static double iconSizeFor(int index) => switch (index) {
    2 => 18,
    3 => 16,
    _ => 20,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShapePainter(index, color, dark),
        child: Center(child: child),
      ),
    );
  }
}

/// Фигуры значков — «глиняные»: у каждой своя форма, свет лепит объём
/// сверху-слева, снизу-справа ложится мягкая тень. Вместо глянцевого
/// блика — матовый рельеф: тёмная кромка по контуру и светлая грань по
/// верхней дуге.
class _ShapePainter extends CustomPainter {
  final int index;
  final Color color;
  final bool dark;

  const _ShapePainter(this.index, this.color, this.dark);

  /// Контуры значков зависят только от фигуры и размера — при перелистывании
  /// разделов цвет меняется каждый кадр, а геометрия нет. Звезда и
  /// скруглённый многоугольник считаются тригонометрией, поэтому держим их
  /// в маленьком кэше (размеров у таблетки ровно несколько).
  static final Map<String, Path> _shapes = {};

  static Path _shapeFor(int index, Size size) {
    final key = '$index:${size.width}x${size.height}';
    final cached = _shapes[key];
    if (cached != null) return cached;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.0;
    final Path shape;
    if (index == 0) {
      shape = Path()..addOval(Rect.fromCircle(center: center, radius: r));
    } else if (index == 1) {
      // Привычки — «подушка»: скруглённый квадрат с мягкими углами, как
      // оттиск ладони в глине (скругление крупнее, чем у обычного квадрата).
      shape = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: center, radius: r),
            Radius.circular(r * 0.44),
          ),
        );
    } else if (index == 2) {
      // 💠 Ромб — широкий (0.96r), чтобы значок свободно помещался;
      // острые верх/низ по-прежнему читаются как гранёный камень.
      final pts = [
        Offset(center.dx, center.dy - r),
        Offset(center.dx + r * 0.96, center.dy),
        Offset(center.dx, center.dy + r),
        Offset(center.dx - r * 0.96, center.dy),
      ];
      shape = _roundedPolygon(pts, r * 0.08);
    } else {
      // Пятиконечная звезда: острые лучи, без скруглений.
      shape = _star(center, r);
    }
    if (_shapes.length > 24) _shapes.clear();
    _shapes[key] = shape;
    return shape;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Фигура: 🔵 круг, ⬜ скруглённый квадрат, 💠 ромб, ✦ звезда.
    final shape = _shapeFor(index, size);

    // ПЛОСКИЙ бейдж: одна заливка и тонкая чёткая кромка. Раньше здесь была
    // «глиняная» лепнина — объёмный градиент, смещённый тёмный силуэт, белая
    // дуга и радиальный блик. В масштабе 1:1 на телефоне это читалось как
    // грязное пятно, а не фигура: значки сливались и «плыли».
    canvas.drawPath(shape, Paint()..color = color);

    // Кромка: чуть темнее заливки — держит контур, не превращаясь в рамку.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Color.lerp(color, Colors.black, dark ? 0.22 : 0.14)!
            .withValues(alpha: 0.35),
    );
  }

  /// Пятиконечная звезда с центром [center] и внешним радиусом [r].
  static Path _star(Offset center, double r) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final ang = -math.pi / 2 + i * math.pi / 5;
      final rad = i.isEven ? r : r * 0.46;
      final pt = Offset(
        center.dx + rad * math.cos(ang),
        center.dy + rad * math.sin(ang),
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  /// Скруглённый многоугольник по точкам (radius — радиус скругления углов).
  static Path _roundedPolygon(List<Offset> points, double radius) {
    final path = Path();
    final n = points.length;
    for (var i = 0; i < n; i++) {
      final p = points[i];
      final prev = points[(i - 1 + n) % n];
      final next = points[(i + 1) % n];
      final u1 = (p - prev);
      final u2 = (next - p);
      final rad = radius.clamp(0.0, math.min(u1.distance, u2.distance) / 2);
      final a = p - u1 / u1.distance * rad;
      final b = p + u2 / u2.distance * rad;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(p.dx, p.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) =>
      oldDelegate.index != index ||
      oldDelegate.color != color ||
      oldDelegate.dark != dark;
}
