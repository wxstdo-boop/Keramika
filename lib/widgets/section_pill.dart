import 'dart:math' as math;

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../l10n/translations.dart';
import '../services/haptics.dart';
import '../services/reality_check_service.dart';
import '../widgets/animated_fab_row.dart' show sectionPillVisible;
import '../widgets/icons/agysha_icons.dart';
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

/// Непрерывный знак величины: у нуля проходит через НОЛЬ, а не
/// перескакивает −1→1 кадром.
///
/// `double.sign` разрывен в нуле, поэтому величина, у которой он берётся,
/// «щёлкает» на смене знака. В таблетке разделов это ломало якорь растяжки
/// ровно на порогах раздела (там, где тяга пересекает ноль) — камень
/// дёргался в углах. Здесь переход плавный по smoothstep: нулевая
/// производная на обоих концах, насыщение при |x| ≥ [full].
double smoothSign(double x, {double full = 0.18}) {
  if (x == 0) return 0;
  final t = (x.abs() / full).clamp(0.0, 1.0);
  final s = t * t * (3.0 - 2.0 * t);
  return x.isNegative ? -s : s;
}

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
  (context, {size = 17, color, strokeWidth}) => AgAlarmIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgHabitsIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgTasksIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
  ),
  (context, {size = 17, color, strokeWidth}) => AgRealityCheckIcon(
    size: size,
    color: color,
    strokeWidth: strokeWidth ?? kAgStroke,
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
  /// чистая функция кадра, БЕЗ лага: общий ValueNotifier +
  /// TweenAnimationBuilder догонял цель с лагом 180–230 мс и перестартовывал
  /// на каждом кадре у самого края, отчего камень «мигал и скакал».
  double _edgePull = 0;

  /// Тяга, захваченная в момент отпускания пальца: во время расслабления
  /// камень спадает с неё к нулю.
  double _releasePull = 0;

  /// «Расслабление» после отпускания: один контроллер, 220 мс, easeOut.
  /// Никаких Timer'ов и второго setState.
  late final AnimationController _edgeSettle;

  /// Куда палец увёл камень (дробная страница).
  double _dragPage = 0;
  // Последнее записанное положение камня (для снапшота волны на отпускании).
  double _dragSmooth = 0;
  double _dragGrabOffset = 0;

  /// Последняя «принятая» X-координата пальца (px по дорожке). Дедзона:
  /// микросдвиги меньше [_dragDeadzone] игнорируются, поэтому дрожание руки
  /// при удержании не двигает карусель.
  double _dragFingerX = 0;

  /// Дедзона пальца, px по дорожке таблетки (~304 px). На дорожке камень
  /// занимает 1/4, а на экране — целую страницу (~1080 px), поэтому даже
  /// 1 px дрожания пальца даёт ~4 px хода экрана. 3 px глушат дрожание руки,
  /// но осознанный сдвиг проходят почти без задержки.
  static const double _dragDeadzone = 3.0;

  /// Ближайший раздел на прошлом кадре — по нему звучит хаптик, когда палец
  /// пересекает границу раздела.
  int _dragNearest = -1;

  /// Тяга за край, вынесенная в notifier: у самого края рельса страница уже
  /// упёрлась в предел, [sectionDragPage] перестаёт меняться — и без этого
  /// канала камень НЕ перестраивался бы, хотя [_edgePull] продолжал расти.
  /// Растяжка под пальцем «замирала», а на отпускании камень рывком брал
  /// настоящее значение тяги (та самая жалоба). Пишем сюда на каждом
  /// изменении тяги — ребилд идёт ровно за пальцем.
  final ValueNotifier<double> _edgePullNotifier = ValueNotifier<double>(0.0);

  /// Последняя вычисленная величина transit-растяжки (волна) — живая:
  /// считается прямо из текущей позиции карусели, поэтому при отпускании
  /// пальца не «прыгает» в замороженное значение, а едет дальше вместе с
  /// доводкой раздела.
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
          // Сбрасываем захваченную тягу ТОЛЬКО когда «расслабление» реально
          // отыграно (completed) или отменено (dismissed).
          //
          // `_releasePull = 0` ВНЕ условия срабатывал бы на КАЖДОЙ смене
          // статуса, включая `forward`, а `forward` наступает ровно в кадр
          // отпускания (см. _startEdgeSettle): захваченная тяга обнулилась бы
          // мгновенно, и форма камня в тот же кадр схлопнулась бы с полной
          // растяжки до одной волны — резкий возврат формы при отпускании.
          if (status == AnimationStatus.completed ||
              status == AnimationStatus.dismissed) {
            _releasePull = 0;
            _lastWave = 0;
          }
        });
  }


  @override
  void dispose() {
    _edgeSettle.dispose();
    _edgePullNotifier.dispose();
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
    _edgePullNotifier.value = 0;
    _lastWave = 0;

    _dragPage = sectionRailPage.value
        .clamp(0.0, (count - 1).toDouble())
        .toDouble();
    // Камень стартует ровно с позиции пальца — без рывка на захват.
    _dragSmooth = _dragPage;
    // Камень занимает 1/count дорожки и стоит НЕ по центру слота, а с
    // отступами по краям: его центр при page=0 равен halfStone, при
    // page=last — trackWidth-halfStone. Формула
    // `page/(count-1)*trackWidth` считала бы камень точкой на краю трека,
    // и в момент касания он «прыгал» бы на половину своей ширины. Считаем
    // центр честно и запоминаем смещение пальца относительно него.
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final stoneCenter = span <= 0
        ? _trackWidth / 2
        : (_dragPage / (count - 1)) * span + stoneW / 2;
    _dragGrabOffset = stoneCenter - details.localPosition.dx;
    // Стартовая точка дедзоны — фактический палец (с учётом захвата).
    _dragFingerX = details.localPosition.dx + _dragGrabOffset;
    _dragNearest = _dragPage.round();
    sectionDragPage.value = _dragPage;
  }

  void _dragUpdate(DragUpdateDetails details, int count) {
    if (!_dragging) return;
    if (count < 2) return;
    // ПОЗИЦИОННЫЙ скраббер, как выбор приоритета: палец задаёт ЦЕНТР
    // камня, а не долю «от края до края». Камень едет ровно под пальцем.
    //
    // Почему не «дельта пикселей»: палец делился на ширину слота таблетки
    // (~74 px), а карусель ехала на `доля × ширину СТРАНИЦЫ` (~1080 px) —
    // 74 px движения уносили контент на целый экран, и движение читалось
    // рывком «не в ту сторону». Здесь жест и содержимое живут в одних долях.
    final rawX = details.localPosition.dx + _dragGrabOffset;
    // Дедзона-ПОЛОСА (не «прыжок на весь шаг»): принятая точка идёт за
    // пальцем с постоянным отступом [_dragDeadzone] в сторону движения.
    // Раньше `_dragFingerX = rawX` перезаписывал точку целиком, и цель
    // обновлялась раз в 3 px ДИСКРЕТНЫМИ ступеньками — на медленной тяге
    // камень и экраны шли «лесенкой» (дёргано, неравномерная скорость).
    // Полоса даёт 1:1-следование после первых 3 px, а микродрожание пальца
    // меньше зоны не двигает цель вовсе (удержание не «дёргает» экраны).
    final h = _dragDeadzone;
    var x = _dragFingerX;
    if (rawX > x + h) {
      x = rawX - h;
    } else if (rawX < x - h) {
      x = rawX + h;
    }
    if (x == _dragFingerX) return; // палец внутри мёртвой зоны — не двигаем
    _dragFingerX = x;
    final stoneW = _trackWidth / count;
    final span = _trackWidth - stoneW;
    final frac = span <= 0
        ? 0.0
        : ((x - stoneW / 2) / span).clamp(0.0, 1.0).toDouble();
    // Тяга за КРАЙ рельса считается от ПОКОЙНЫХ центров крайних разделов
    // (stoneW/2 и trackWidth-stoneW/2), а не от 0 и trackWidth: раньше
    // растяжка у углов начиналась лишь при выносе камня ЗА пределы дорожки
    // («растягивается, только если сильно натянуть»). Теперь крайний раздел
    // «упирается в стену» и тянется, как только палец идёт дальше его
    // центра — растяжка видна ПОД пальцем, а не только на отпускании.
    final leftRest = stoneW / 2;
    final rightRest = _trackWidth - stoneW / 2;
    final over = x < leftRest
        ? x - leftRest
        : (x > rightRest ? x - rightRest : 0.0);
    // «Объём до конца»: тяга наливается весь ход пальца за край, поэтому
    // камень дышит на всю длину жеста. Нормированная доля (-0.9..0.9).
    _edgePull = (over / 90.0).clamp(-0.9, 0.9);
    // У края страница уже на пределе — sectionDragPage не меняется, и без
    // этого уведомления камень не перестроился бы (растяжка «замирала»).
    _edgePullNotifier.value = _edgePull;
    // Палец задаёт позицию камня (точная доля по дорожке), она пишется в
    // [sectionDragPage] НАПРЯМУЮ: палец уже прошёл дедзону, сглаживать
    // больше нечего. Каждый лишний слой запаздывания только отставал от
    // пальца и в конце «догонял» скачком. Экран, запертый к этому каналу
    // 1:1, едет РОВНО под пальцем без лага.
    _dragPage = (frac * (count - 1)).clamp(0.0, (count - 1).toDouble());
    _dragSmooth = _dragPage;
    sectionDragPage.value = _dragPage;
    // Направление «резинки» НЕПРЕРЫВНОЕ (см. stretchDir в
    // _buildStoneRow): знак _edgePull — под пальцем, знак _releasePull
    // (затухающий по _edgeSettle) — в полёте. Дискретный гистерезис
    // `_anchorSide` (±0.15) «тикал» у углов и дёргал камень.
    final nearest = _dragPage.round();
    if (nearest != _dragNearest) {
      _dragNearest = nearest;
      Haptics.light();
    }
  }

  void _dragEnd(int count) {
    if (!_dragging) return;
    _dragging = false;
    // Волна НЕ фиксируется: она и так считается из живой позиции карусели,
    // поэтому при отпускании камень продолжает форму плавно, без рывка в
    // растянутое положение. Гасим только захваченную тягу за край.
    _startEdgeSettle();
    final target = _dragSmooth.round().clamp(0, count - 1);
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
    // Отмена (палец ушёл не по сценарию): то же гашение захваченной тяги.
    _startEdgeSettle();
    sectionDragPage.value = null;
    final count = sectionIconsFor(context).length;
    if (count > 1) {
      final target = sectionRailPage.value.round().clamp(0, count - 1);
      sectionCurrentIndex.value = target;
      sectionTabTap.value++;
    }
  }


  /// Форма «резинки-волны» от смещения [transit] (в долях секции, 0..0.5).
  ///
  /// Квадратичная кривая `1-(1-t)^2` — как была: у неё ненулевой наклон в
  /// нуле, поэтому растяжка видна уже с первых пикселей тяги. Плоский
  /// smoothstep у нуля почти не растёт — под пальцем казалось, что камень
  /// «не растягивается вовсе».
  double _waveShape(double transit) {
    final t2 = (transit * 2.0).clamp(0.0, 1.0); // 0 — покой, 1 — порог секции
    return 1.0 - (1.0 - t2) * (1.0 - t2);
  }

  /// «Расслабление» камня после отпускания пальца: захватываем текущую
  /// растяжку и плавно уводим её к нулю (220 мс, easeOut) — камень «сам
  /// отпускает» край, а не соскакивает. До этого было Timer + второй
  /// setState: двойная пересборка в один кадр дёргала камень вбок.
  void _startEdgeSettle() {
    // Гасить нечего: волна теперь живая (её ведёт позиция карусели), а
    // захваченной тяги за край нет — settle не нужен вовсе.
    if (!_dragging && _edgePull == 0) {
      _lastWave = 0;
      return;
    }
    _releasePull = _edgePull;
    _edgeSettle
      ..stop()
      ..value = 0
      ..forward();
    _edgePull = 0;
    _edgePullNotifier.value = 0;
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
                    // внутри _buildStoneRow): ДВА вложенных AnimatedBuilder
                    // (внешний без _edgeSettle, внутренний с _edgeSettle)
                    // пересобирали кадр ДВАЖДЫ на каждый тик любого notifier'а
                    // (внешний билдер прогнал дерево, потом внутренний снова) —
                    // на Adreno это давало микрофризы. _buildStoneRow сам
                    // вешает _edgeSettle через merge внутри, а здесь только
                    // прокидываем rawPage.
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
    // перетягивании.
    final transit = (p - p.roundToDouble()).abs();
    // Живая транзитная волна: по ней считается растяжка камня в середине
    // секции (между разделами). Читается прямо из позиции карусели, поэтому
    // непрерывна и под пальцем, и в доводке после отпускания.
    _lastWave = _waveShape(transit);
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
        _edgePullNotifier,
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
        // ВОЛНА УГЛОВ — всегда живая [_lastWave]: считается из текущей
        // позиции карусели, поэтому под пальцем и после отпускания меняется
        // непрерывно, без рывка «в растянутое положение».
        final wave = _lastWave;
        // Signed-тяга камня: под пальцем — чистая _edgePull, после отпускания
        // — захваченная _releasePull, затухающая по settle.
        final stretch = _dragging ? _edgePull : _releasePull * (1.0 - settle);
        final edgeStretch = stretch.abs();
        final transitOffset = p - p.roundToDouble();
        final transitDir = smoothSign(transitOffset * 2.0);
        final stretchDir = edgeStretch > 0.001 ? smoothSign(stretch) : transitDir;
        // ОБЪЁМНЫЙ СЛОЙ: «резинка» (wave) — наливка/растяжение выбранной
        // вкладки по ходу к СЛЕДУЮЩЕЙ секции. Под пальцем амплитуда ~0.85,
        // в свободном полёте — 1.0 (см. выше). Это и есть то самое
        // РАСТЯЖЕНИЕ выбранной таблетки при перетягивании: без волны scaleX
        // по ходу секции остаётся константой, и камень просто «едет».
        //
        // Единая визуальная растяжка кадра: крайняя тяга (edgeStretch) +
        // волна-резинка (wave). Оба вливаются в один коэффициент, чтобы
        // масштаб/скругление/якорь считались из одного числа — камень дышит
        // ровно за пальцем, без раздельных скачков.
        // РАСТЯЖЕНИЕ В УГЛАХ: у порогов раздела (t2≈1, wave→1) камень
        // заметно вытягивается и округляется в сторону следующего раздела.
        // Коэффициент волны 0.72 (был 0.55 — растяжение «проскальзывало»)
        // держит эффект отчётливым, а `math.min(0.98, …)` не даёт раздуться.
final visualStretch = math.min(0.98, edgeStretch + 0.90 * wave);
        // Радиус угла 10.0: растянутая таблетка округляется заметно.
        final capRadius = 22.0 + 10.0 * visualStretch;

        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            // Позиция камня непрерывна всегда: `indicatorAlignment`
            // (linear по p) идёт одним числом в любой момент — при тяге за
            // край Align не переключается мгновенно на -1/+1 и камень не
            // «мигает в стороны».
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
                // (stretch = 0) садится ровно. Одна и та же формула везде,
                // без ветки по _dragging: «в полёте 0 / под пальцем -3px»
                // дёргало камень вертикально в момент отпускания.
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
                  // Дискретный `_anchorSide` (гистерезис ±0.15) дёргал якорь
                  // вбок у углов.
                  alignment: Alignment(
                    math.max(
                      -1.0,
                      math.min(1.0, -stretchDir * visualStretch * 2.0),
                    ),
                    0,
                  ),
                  // Растяжка читается ИЗ visualStretch: под пальцем камень
                  // вытягивается по ходу секции (wave) и за краем (edgeStretch),
                  // после отпускания — сползает по _edgeSettle. Единый
                  // коэффициент, без дискретных переключений.
                  scaleX: 1.0 + 0.55 * visualStretch,
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
            // DragStartBehavior.start — точка старта берётся в момент
            // РАСПОЗНАВАНИЯ жеста (после touch-slop), а не в момент касания:
            // иначе первый же update приносил позицию «касание + slop», и
            // камень прыгал на ~18 px в первом кадре — тот самый скачок при
            // лёгкой тяге. Дальше камень едет за пальцем 1:1.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.start,
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
                  // Фигура по 12 ступеням, а иконка непрерывно — два слоя
                  // меняли цвет в разном темпе и «проскальзывали» друг
                  // относительно друга: это и было мерцание при перетяжке.
                  // Одна сетка ступеней у обоих: смена цвета дискретная, но
                  // 48 ступеней на секцию глазом не отделяются от
                  // непрерывности (шаг ≈ 2 %), а CustomPaint перерисовывается
                  // лишь на смене ступени — без мерцания и без шейдерного
                  // шторма на каждый кадр.
                  final badgeT = (proximity * 48).round() / 48;
                  // Чернила глифа: фирменный primary на нейтральном бейдже
                  // и onPrimary на выбранном. В тёмной теме onSurfaceVariant
                  // давал светлый глиф на светлом бейдже — контраст падал до
                  // 2.2 и значки читались как «мыло».
                  final iconColor = Color.lerp(
                    cs.primary,
                    cs.onPrimary,
                    badgeT,
                  );
                  return Expanded(
                    // Подсказка: long-press не должен красть протяжку.
                    // Арбитр жестов, ждавший 350 мс, начинал тягу только
                    // после зависания, поэтому жест стартует сразу от касания
                    // (DragStartBehavior.down), а ожидание тултипа длиннее
                    // (500 мс) — на быстром «зажал и повёл» выигрывает
                    // протяжка. Пока палец удерживается без движения, тултип
                    // по-прежнему покажется.
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
    // «Глиняная» лепнина (подмес primaryContainer плюс градиент) заставляла
    // капсулу желтеть/розоветь и спорить с фигурами: значки должны читаться
    // на спокойном фоне, а не на цветной массе.
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
/// Без зеркального блика, бегущей полосы и белых капель внутри: в тёмной
/// теме такой камень вспыхивал при каждом переключении, и глаз ловил блик,
/// а не раздел. Движение камня — само по себе акцент, световые эффекты
/// поверх не нужны.
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

  /// Размер глифа внутри фигуры. Задаётся ОДИН раз: рисование в 17 px с
  /// последующим вписыванием в бокс 15.5 px размывало штрих. У «колючих»
  /// фигур (ромб, звезда) глиф мельче, чтобы не вылезать за острые края.
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

    // ПЛОСКИЙ бейдж: одна заливка и тонкая чёткая кромка. «Глиняная»
    // лепнина (объёмный градиент, смещённый тёмный силуэт, белая дуга и
    // радиальный блик) в масштабе 1:1 на телефоне читалась как грязное
    // пятно, а не фигура: значки сливались и «плыли».
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
