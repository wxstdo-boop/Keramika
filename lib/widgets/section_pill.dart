import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
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
const List<IconData> sectionIcons = [
  Icons.alarm_outlined,
  Icons.auto_awesome_outlined,
  Icons.checklist_outlined,
  Icons.psychology_outlined,
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
List<IconData> sectionIconsFor(BuildContext context) {
  final count = sectionLabels(context).length;
  return sectionIcons.sublist(0, count);
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
    with SingleTickerProviderStateMixin {
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

  /// От какого края камень растянут (-1 левый / +1 правый). Держится
  /// через весь отпуск: раньше `_edgeSide` сбрасывался в 0 в `_dragEnd`,
  /// и якорь растяжки вбок-скакал на первом кадре «расслабления».
  int _anchorSide = 0;

  /// Тяга, захваченная в момент отпускания пальца: во время расслабления
  /// камень спадает с неё к нулю.
  double _releasePull = 0;

  /// «Расслабление» после отпускания: один контроллер, 220 мс, easeOut.
  /// Никаких Timer'ов и второго setState.
  late final AnimationController _edgeSettle;

  /// Куда палец увёл камень (дробная страница).
  double _dragPage = 0;
  double _dragGrabOffset = 0;

  /// Ближайший раздел на прошлом кадре — по нему звучит хаптик, когда палец
  /// пересекает границу раздела.
  int _dragNearest = -1;

  @override
  void initState() {
    super.initState();
    _edgeSettle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addStatusListener((status) {
        // Расслабление завершено (или отменено) — сбрасываем захваченные
        // значения, чтобы они не влияли на следующий жест.
        _anchorSide = 0;
        _releasePull = 0;
      });
  }

  @override
  void dispose() {
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
    _anchorSide = 0;
    _dragPage = sectionRailPage.value
        .clamp(0.0, (count - 1).toDouble())
        .toDouble();
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
    _edgePull = over;
    // Гистерезис: сторона, у которой камень «сидит» за краем, выбирается
    // один раз (порог ±6 px) и держится на протяжении ВСЕГО отпускания —
    // якорь растяжки не должен перещёлкиваться вбок посреди
    // расслабления (это был вбок-скачок на первом кадре после тапа).
    if (over != 0) {
      if (_anchorSide != -1 && over < -6) _anchorSide = -1;
      if (_anchorSide != 1 && over > 6) _anchorSide = 1;
      if (_anchorSide == 0) _anchorSide = over < 0 ? -1 : 1;
    }
    _dragPage = (frac * (count - 1)).clamp(0.0, (count - 1).toDouble());
    final nearest = _dragPage.round();
    if (nearest != _dragNearest) {
      _dragNearest = nearest;
      Haptics.light();
    }
    sectionDragPage.value = _dragPage;
  }

  void _dragEnd(int count) {
    if (!_dragging) return;
    _dragging = false;
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
    _startEdgeSettle();
    sectionDragPage.value = null;
    final count = sectionIconsFor(context).length;
    if (count > 1) {
      final target = sectionRailPage.value.round().clamp(0, count - 1);
      sectionCurrentIndex.value = target;
      sectionTabTap.value++;
    }
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
    final icons = sectionIconsFor(context);
    final count = icons.length;
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
                    // ОДИН слушатель на три состояния вместо трёх вложенных
                    // ValueListenableBuilder: за кадр тяги и dragPage, и
                    // railPage меняются одновременно, и вложенные билдеры
                    // пересобирали камень дважды. Здесь — один rebuild на
                    // кадр, без лишней работы на слабом железе.
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
                        icons: icons,
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
    required List<IconData> icons,
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
    // ИСПРАВЛЕНИЕ ДЁРГАНЬЯ: во время тяги пальцем wave
    // замораживается на нуле. Раньше ширина камня
    // дышала (до +4%) на КАЖДОМ пересечении границы
    // раздела, и камень визуально «подёргивался» под
    // пальцем. Теперь дышит только камень в свободном
    // полёте (пружина); ведёмый пальцем — монолитен.
    final transit = (p - p.roundToDouble()).abs();
    final t2 = transit * 2.0; // 0..1 (0 — покой)
    final wave = _dragging ? 0.0 : 1.0 - (1.0 - t2) * (1.0 - t2);
    // «Расслабление» камня после отпускания: он сползает с _releasePull к
    // нулю по _edgeSettle (220 мс, easeOut). Под пальцем — 1:1 (_edgePull),
    // БЕЗ лага. TweenAnimationBuilder убран: он догонял цель с лагом
    // 180–230 мс и перезапускался у самого края (duration zero↔180
    // переключался на каждом кадре) — это и была «мигалка/скачок».
    return AnimatedBuilder(
      animation: _edgeSettle,
      builder: (context, _) {
        final settle = _edgeSettle.value;
        final stretch =
            _dragging ? _edgePull : _releasePull * (1.0 - settle);
        final edgeStretch = stretch.abs();
        // «Объём до конца»: в спокойном полёте камень
        // дышит волной; а под пальцем — наливается
        // вместе с тягой за край: чем сильней тянешь,
        // тем он крупнее и мягче. Раньше объём был
        // константным и потому «замедлялся» на глазах.
        final capRadius = _dragging
            ? 22.0 + 5.0 * edgeStretch
            : 22.0 + 2.0 * wave;

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
              child: Transform.scale(
                // Масштаб считается прямо из stretch — БЕЗ tween'а:
                // под пальцем 1:1 за движением (zero latency), после
                // отпускания stretch спадает по _edgeSettle (easeOut).
                // TweenAnimationBuilder здесь давал лаг 180–230 мс и
                // «мигал» у края (перезапуск при переключении duration).
                //
                // Якорь растяжки — непрерывный lerp по signed-тяге:
                // _anchorSide (-1/+1, гистерезис) × edgeStretch, без
                // дискретных переключений Alignment.center/Left/Right.
                alignment: Alignment(
                  math.max(
                    -1.0,
                    math.min(
                      1.0,
                      -(_anchorSide) * edgeStretch * 2.0,
                    ),
                  ),
                  0,
                ),
                scaleX: (1 + 0.30 * edgeStretch) *
                    (_dragging ? 1.0 : (1.0 + 0.04 * wave)),
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
                  final iconColor = Color.lerp(
                    cs.onSurfaceVariant,
                    cs.onPrimary,
                    proximity,
                  );
                  final isSelected = selectedIndex == i;
                  // Цвет фигуры квантуем по 12 ступеням:
                  // CustomPainter с градиентом и ободком
                  // иначе перерисовывался бы на каждый
                  // кадр тяги. Глаз разницы не видит, а
                  // шейдеры не создаются 60 раз в секунду.
                  final badgeT = (proximity * 12).round() / 12;
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
                                  // Невыбранная — заметный
                                  // фирменный оттенок (чтобы
                                  // фигуры читались), выбранная —
                                  // сочный градиентный «камень».
                                  color: Color.lerp(
                                    cs.primary.withValues(alpha: 0.3),
                                    cs.primary,
                                    badgeT,
                                  )!,
                                  child: Icon(
                                    icons[i],
                                    size: 17,
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
    final base = dark ? cs.surfaceContainerHigh : cs.surfaceContainerHighest;
    // Лёгкий фирменный оттенок — таблетка «своя», но не цветная плитка.
    final tint = Color.lerp(base, cs.primary, dark ? 0.10 : 0.08)!;
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
            // Объём — только мягким градиентом сверху вниз, без бликов.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                tint.withValues(alpha: 0.94),
                tint.withValues(alpha: 0.90),
              ],
            ),
            border: Border.all(
              // Тонкая обводка: раньше 3 px яркого primary давали неоновую
              // рамку, которая перетягивала внимание с иконок.
              color: cs.primary.withValues(alpha: dark ? 0.24 : 0.30),
              width: 1.2,
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
/// (круг, скруглённый квадрат, ромб, гексагон). У каждого раздела свой
/// контур; градиент + блик + гранёный ободок — фигура читается объёмной.
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

  /// Коэффициент иконки внутри фигуры: у «колючих» фигур (ромб, звезда)
  /// иконка меньше, чтобы не вылезать за острые края.
  double get _iconScale => switch (index) {
    2 => 0.5,
    3 => 0.44,
    _ => 0.56,
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ShapePainter(index, color),
        child: Center(
          child: SizedBox(
            width: size * _iconScale,
            height: size * _iconScale,
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
      shape = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            Rect.fromCircle(center: center, radius: r),
            Radius.circular(r * 0.38),
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
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 1.0;
    // «Драгоценный» градиент: свет сверху-слева, глубина снизу-справа.
    final light = Color.lerp(color, Colors.white, 0.42)!;
    final deep = Color.lerp(color, Colors.black, 0.18)!;
    final shader = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, color, deep],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Offset.zero & size);

    // Фигура: 🔵 круг, ⬜ скруглённый квадрат, 💠 вытянутый ромб,
    // ✦ пятиконечная звезда («искра» проверок реальности).
    final shape = _shapeFor(index, size);

    canvas.drawPath(shape, Paint()..shader = shader);

    // Гранёный ободок: тонкая светлая кромка по контуру фигуры.
    canvas.drawPath(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = Colors.white.withValues(alpha: 0.38),
    );

    // Глянцевый блик: мягкое светлое пятно в верхней части фигуры.
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawCircle(
      Offset(center.dx - r * 0.30, center.dy - r * 0.34),
      r * 0.34,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(center.dx - r * 0.30, center.dy - r * 0.34),
                radius: r * 0.7,
              ),
            ),
    );
    canvas.restore();
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
      oldDelegate.index != index || oldDelegate.color != color;
}
