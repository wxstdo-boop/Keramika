import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../widgets/item_reveal.dart';
import '../widgets/page_spring.dart';
import '../widgets/press_scale.dart';

/// Скользящий выбор «по пунктам»: горизонтальная карусель с центральной
/// привязкой. Свайп влево/вправо плавно переключает пункты; текущий пункт
/// выделен и слегка увеличен, соседние чуть приглушены.
///
/// Применение пункта:
/// - тап по пункту — применяется СРАЗУ (явное намерение), карусель плавно
///   подъезжает к нему;
/// - свайп — применяется, когда карусель ДЕЙСТВИТЕЛЬНО встала. После
///   отпускания ждём баллистику; любой новый скролл-тик отменяет применение
///   и ждёт финальной остановки.
///   Так быстрый флип через несколько пунктов применяет только финальный,
///   а «доезжающая» карусель не применяет промежуточные.
class SlidingPicker<T> extends StatefulWidget {
  final List<T> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final Widget Function(BuildContext context, T item, bool selected)
  itemBuilder;
  final double viewportFraction;
  final double height;

  const SlidingPicker({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.itemBuilder,
    this.viewportFraction = 0.6,
    this.height = 68,
  });

  @override
  State<SlidingPicker<T>> createState() => _SlidingPickerState<T>();
}

class _SlidingPickerState<T> extends State<SlidingPicker<T>>
    with SingleTickerProviderStateMixin {
  late final PageController _ctrl = PageController(
    viewportFraction: widget.viewportFraction,
  );
  // Пружина вместо animateToPage: при быстрых тапах по двум пунктам движение
  // не «перезапускается» с нуля, а доворачивает с текущей скоростью.
  late final PageSpring _spring = PageSpring(
    vsync: this,
    controller: _ctrl,
    // Карусель категорий — собраннее: короткий доворот без «хвоста».
    stiffness: 230,
    dampingRatio: 0.95,
  );
  // Свайп пользователя уже движет карусель — не дёргаем контроллер в ответ.
  bool _settling = false;
  // Палец сейчас ведёт карусель (dragDetails != null): в этом случае
  // didUpdateWidget не «дёргает» контроллер к выбранному пункту — иначе
  // живое применение во время драга конфликтовало бы с пальцем.
  bool _userDragging = false;
  Timer? _applyTimer;
  // Пункт, на который ТОЛЬКО ЧТО тапнули (но карусель ещё едет к нему):
  // подсветка прилипает к нему МГНОВЕННО, не дожидаясь, пока карусель
  // доедет и встанет по центру. Так тап не ощущается «с задержкой».

  int get _selectedIndex {
    final i = widget.items.indexOf(widget.selected);
    return i < 0 ? 0 : i;
  }

  int? _pendingSelect;
  int? _lastAppliedIndex;

  // Когда список пунктов изменился в последний раз (категорию создали или
  // удалили). В этом окне таблетки карусели проявляются заново — смягчая
  // сдвиг строки, поэтому появление/исчезновение не выглядит рывком.
  DateTime _itemsChangedAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _revealWindow = Duration(milliseconds: 700);

  /// Список пунктов отличается от предыдущего (состав или порядок)?
  bool _sameItems(List<T> a, List<T> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Карусель доехала до намеченного тапом пункта — подсветку можно
  /// передать живой логике (она и так держит этот пункт).
  void _maybeClearPending() {
    final p = _pendingSelect;
    if (p == null || !_ctrl.hasClients) return;
    final page = _ctrl.page;
    if (page != null && (page - p).abs() < 0.02) {
      setState(() => _pendingSelect = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _lastAppliedIndex = _selectedIndex;
    _ctrl.addListener(_maybeClearPending);
    // При открытии экрана карусель стартует на ВЫБРАННОМ пункте, а не на
    // первом — иначе обводка выбранного звука «сбрасывается» при перезаходе.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_ctrl.hasClients) return;
      final target = _selectedIndex;
      if (target > 0) {
        _settling = true;
        _ctrl.jumpToPage(target);
        _settling = false;
      }
    });
  }

  /// Тап по пункту: применяем сразу (пользователь явно выбрал), карусель
  /// плавно подъезжает к нему.
  void _selectPage(int i) {
    _applyTimer?.cancel();
    _applyTimer = null;
    final item = widget.items[i];
    if (item == widget.selected) {
      // Уже выбран — просто доводим карусель на место (мягко, а не рывком).
      if (_ctrl.hasClients) _animateTo(i);
      return;
    }
    // МГНОВЕННОЕ применение: список задач переключается сразу, без
    // задержки и без «анимации исчезновения» (AnimatedSwitcher убран).
    // Карусель плавно подъезжает к выбранному пункту уже ПОСЛЕ —
    // на отклик это не влияет.
    setState(() => _pendingSelect = i);
    _lastAppliedIndex = i;
    widget.onChanged(item);
    if (_ctrl.hasClients) _animateTo(i);
  }

  /// Мягко доводит карусель до пункта [i]. Скорость ведёт пружина: повторный
  /// тап (или тап по другой таблетке) лишь меняет цель, поэтому быстрое
  /// «тапание туда-сюда» не выглядит медленным перекатыванием и не заедает.
  void _animateTo(int i) {
    _spring.to(i.toDouble(), maxPage: (widget.items.length - 1).toDouble());
  }

  /// Карусель закончила движение (отпускание пальца или конец баллистики).
  void _onScrollEnd({required bool ballisticEnd}) {
    _applyTimer?.cancel();
    // После отпускания можно ещё начаться баллистика. Даём ей стартовать,
    // а каждый ScrollUpdate отменит это применение. На конце баллистики
    // выбираем конечную страницу сразу.
    _applyTimer = Timer(
      ballisticEnd ? Duration.zero : const Duration(milliseconds: 150),
      _applySettledPage,
    );
  }

  /// Карусель снова движется — отменяем отложенное применение: промежуточные
  /// позиции при флипе не должны применяться.
  void _cancelPendingApply() {
    _applyTimer?.cancel();
    _applyTimer = null;
  }

  /// Применяет пункт, на котором карусель стоит СЕЙЧАС (с дедупом).
  void _applySettledPage() {
    _applyTimer = null;
    if (!mounted || !_ctrl.hasClients) return;
    final page = _ctrl.page;
    if (page == null) return;
    final j = page.round().clamp(0, widget.items.length - 1);
    if (_lastAppliedIndex == j) return;
    final item = widget.items[j];
    if (item == widget.selected) return;
    _lastAppliedIndex = j;
    widget.onChanged(item);
  }

  @override
  void didUpdateWidget(covariant SlidingPicker<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameItems(oldWidget.items, widget.items)) {
      // Состав пунктов поменялся: запоминаем момент, чтобы таблетки
      // проявились мягко, а не «выскочили» на новых местах.
      _itemsChangedAt = DateTime.now();
    }
    final target = _selectedIndex;
    if (oldWidget.selected != widget.selected) _lastAppliedIndex = target;
    final page = _ctrl.hasClients ? _ctrl.page : null;
    // Пока палец ведёт карусель — не дёргаем контроллер: применённый
    // (живой) пункт совпадёт с позицией карусели, когда палец отпустят.
    // И не перезапускаем анимацию, если карусель уже едет к пункту,
    // выбранному ТАПОМ: раньше два animateToPage (тап + этот) боролись друг
    // с другом, и при частых тапах карусель «заедала» на полпути.
    if (!_settling &&
        !_userDragging &&
        _pendingSelect == null &&
        page != null &&
        (page - target).abs() > 0.01) {
      _spring.to(
        target.toDouble(),
        maxPage: (widget.items.length - 1).toDouble(),
      );
    }
  }

  @override
  void dispose() {
    _applyTimer?.cancel();
    _spring.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: widget.height,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollStartNotification) {
            _userDragging = notification.dragDetails != null;
            _cancelPendingApply();
            // Палец повёл карусель — пружина уступает место жесту.
            if (_userDragging) _spring.stop();
            // Пользователь сам ведёт карусель — отменяем «намеченную тапом»
            // подсветку, её место занимает живая подсветка под пальцем.
            if (_pendingSelect != null) setState(() => _pendingSelect = null);
          } else if (notification is ScrollUpdateNotification) {
            if (notification.dragDetails != null) {
              // Во время тяги позиция не является конечным выбором.
              _userDragging = true;
            } else {
              // Баллистика ещё проходит промежуточные страницы. Ждём
              // ScrollEnd, чтобы флип применил только конечный пункт.
              _cancelPendingApply();
            }
          } else if (notification is ScrollEndNotification) {
            _userDragging = false;
            // Пружина ведёт карусель: её покадровые «концы скролла» — не повод
            // применять ПРОМЕЖУТОЧНЫЙ пункт (иначе список мигал бы назад на
            // старте движения). Финальный пункт применяется сам: живое
            // применение у границы + onChanged из тапа.
            if (_spring.isRunning) return false;
            // dragDetails != null — ScrollEnd от отпускания пальца (дальше
            // может поехать баллистика); null — баллистика встала на место.
            _onScrollEnd(ballisticEnd: notification.dragDetails == null);
          }
          return false;
        },
        child: PageView.builder(
          controller: _ctrl,
          itemCount: widget.items.length,
          // Карусель подхватывает палец СРАЗУ при касании (а не после
          // порога в 20 px): «зажал и повёл» работает как ожидается —
          // можно протащить категории через все пункты, не отпуская.
          dragStartBehavior: DragStartBehavior.down,
          itemBuilder: (context, i) {
            final item = widget.items[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _selectPage(i),
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (context, _) {
                  // Масштаб/прозрачность по мере приближения к центру.
                  final pos = _ctrl.hasClients ? (_ctrl.page ?? 0) : 0.0;
                  final delta = (i - pos).abs().clamp(0.0, 1.0);
                  final scale = 1.0 - 0.12 * delta;
                  final opacity = 1.0 - 0.35 * delta;
                  // Подсветка РОВНО ОДНА. Если карусель едет к намеченному
                  // тапом пункту — подсвечен только он (сразу, не дожидаясь,
                  // пока доедет). Раньше «центральный» вид одновременно
                  // получали и намеченный пункт, и тот, что стоял в центре, —
                  // при быстрых тапах туда-сюда подсветка дёргалась между
                  // двумя таблетками. Без намеченного — живая подсветка
                  // пункта, к которому карусель привязана сейчас (при
                  // перетаскивании пальцем).
                  final liveSelected = _pendingSelect != null
                      ? i == _pendingSelect
                      : (i - pos).abs() < 0.5;
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(
                      scale: scale,
                      child: PressScale(
                        pressedScale: 0.96,
                        duration: const Duration(milliseconds: 400),
                        child: ItemReveal(
                          key: ValueKey<Object>('picker_cell_$item'),
                          // Проявляем заново только сразу после смены состава
                          // пунктов: таблетки, приехавшие во время обычного
                          // свайпа, появляются мгновенно, без лишнего мигания.
                          animate:
                              DateTime.now().difference(_itemsChangedAt) <
                              _revealWindow,
                          child: widget.itemBuilder(
                            context,
                            item,
                            liveSelected,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
