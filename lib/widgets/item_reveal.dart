import 'package:flutter/material.dart';

/// Мягкое появление и исчезновение элемента ряда (чипа категории, таблетки
/// карусели).
///
/// Появление: элемент «разворачивается» из нулевой ширины — соседи плавно
/// разъезжаются, а не прыгают на освободившееся место. Исчезновение —
/// зеркально ([removing] = true): элемент схлопывается в ноль, после чего
/// вызывает [onDone], и родитель может убрать его из дерева.
///
/// Обычная перестройка без смены состава ничего не запускает
/// ([animate] = false): элемент сразу стоит на месте, без мигания.
class ItemReveal extends StatefulWidget {
  const ItemReveal({
    super.key,
    required this.child,
    this.animate = true,
    this.removing = false,
    this.duration = const Duration(milliseconds: 340),
    this.height,
    this.onDone,
    this.clipRadius = const BorderRadius.all(Radius.circular(999)),
  });

  final Widget child;

  /// Проявлять ли элемент при первом построении. Для элементов, которые уже
  /// стоят на экране, — false (появляются сразу).
  final bool animate;

  /// Элемент исчезает: схлопывается в ноль, затем зовёт [onDone].
  final bool removing;

  final Duration duration;

  /// Явная высота элемента. Задаём её там, где анимация ширины иначе поменяла
  /// бы размер элемента (например, чипы в горизонтальном списке, которые
  /// растянуты на всю высоту строки).
  final double? height;

  /// Анимация (появления или исчезновения) доехала до конца.
  final VoidCallback? onDone;

  /// Скругление «окна», в котором схлопывается элемент. Элементы ряда —
  /// пилюли, поэтому по умолчанию радиус = «стадион»: уезжающая таблетка
  /// сжимается со СВОИМИ скруглёнными концами, а не режется прямоугольником
  /// (острые углы посреди пилюли выглядели как баг).
  final BorderRadius clipRadius;

  @override
  State<ItemReveal> createState() => _ItemRevealState();
}

class _ItemRevealState extends State<ItemReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: (widget.animate && !widget.removing) ? 0.0 : 1.0,
  );

  @override
  void initState() {
    super.initState();
    if (widget.removing) {
      _startRemove();
    } else if (_c.value < 1.0) {
      _c.forward().whenComplete(() {
        if (!mounted) return;
        // Один пересбор после финиша: в дереве рендера не остаётся лишнего
        // ClipRect/Opacity/Transform.
        setState(() {});
        widget.onDone?.call();
      });
    }
  }

  @override
  void didUpdateWidget(covariant ItemReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removing && !oldWidget.removing) _startRemove();
  }

  void _startRemove() {
    _c.duration = widget.duration;
    _c.reverse().whenComplete(() {
      if (mounted) widget.onDone?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _sized(Widget child) => widget.height == null
      ? child
      : SizedBox(height: widget.height, child: child);

  @override
  Widget build(BuildContext context) {
    // Готовый элемент: никаких лишних слоёв.
    //
    // ВАЖНО: «готов» — это не только value == 1, но и ОСТАНОВЛЕННЫЙ контроллер.
    // У «призрака» удалённого чипа анимация стартует прямо в initState, когда
    // значение ещё ровно 1.0: если на первом кадре уйти в быстрый путь, в
    // дереве не остаётся ни одного слушателя контроллера — тикер тикает в
    // пустоту, призрак навсегда застывает на полной ширине, а соседи
    // («+ Новая категория») так и не съезжают — это и читалось как «скачет
    // влево».
    if (_c.value >= 1.0 && !_c.isAnimating) return _sized(widget.child);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = _c.value;
        final t = Curves.easeInOutCubic.transform(v);
        return ClipRRect(
          // Скруглённый клип: таблетка «уезжает», оставаясь пилюлей.
          borderRadius: widget.clipRadius,
          // widthFactor = t: элемент «разворачивается» от левого края, ширина
          // едет вместе с прозрачностью — соседи переезжают плавно.
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: t,
            heightFactor: 1.0,
            child: IgnorePointer(
              ignoring: widget.removing,
              child: Opacity(
                // При появлении чуть прозрачнее на старте, при исчезновении
                // успевает погаснуть раньше, чем ширина дойдёт до нуля, —
                // «обрезков» не видно.
                opacity: widget.removing ? t : (0.25 + 0.75 * t),
                child: _sized(
                  Transform.scale(
                    scale: 0.94 + 0.06 * t,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ряд элементов с плавным появлением/исчезновением.
///
/// Следит за составом [items]: новые элементы «разворачиваются» на своих
/// местах, а удалённые остаются «призраками» на прежней позиции и тают,
/// пока соседи мягко съезжаются.
class ChipsReveal extends StatefulWidget {
  const ChipsReveal({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.trailing,
    this.height,
    this.duration = const Duration(milliseconds: 340),
  });

  final List<String> items;

  /// Строит элемент по имени. Вызывается и для «призраков» удалённых
  /// элементов — поэтому он должен уметь построить чип по одному имени.
  final Widget Function(BuildContext context, String item) itemBuilder;

  /// Элемент, который стоит после ряда (например, «+ Новая категория»).
  final Widget? trailing;

  /// Высота строки: держит элементы той же высоты, что и до анимации ширины.
  final double? height;

  final Duration duration;

  @override
  State<ChipsReveal> createState() => _ChipsRevealState();
}

class _Ghost {
  _Ghost(this.name, this.index, this.child);
  final String name;
  final int index;
  /// Как элемент выглядел В МОМЕНТ удаления (в том числе выбранным). Призрак
  /// рисуется именно таким — иначе ширина «прыгала» из-за другой набивки и
  /// обводки выбранного, и соседи (кнопка «+ Новая категория») дёргались.
  final Widget child;
}

class _ChipsRevealState extends State<ChipsReveal> {
  late List<String> _items;
  final List<_Ghost> _ghosts = [];
  final Set<String> _appearing = {};

  /// Последний построенный вид каждого элемента — призраку берём его.
  final Map<String, Widget> _lastBuilt = {};

  /// Псевдонимы имён: при ПЕРЕИМЕНОВАНИИ на той же позиции имя сохраняет
  /// прежний «токен», поэтому чип не пересоздаётся, а плавно меняет подпись.
  /// Ключ элемента — 'chip_' + (alias[name] ?? name).
  final Map<String, String> _alias = {};

  @override
  void initState() {
    super.initState();
    _items = List<String>.from(widget.items);
  }

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant ChipsReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.items;
    if (_same(next, _items)) return;
    final prev = _items;
    final prevSet = prev.toSet();
    final nextSet = next.toSet();

    // ПЕРЕИМЕНОВАНИЕ: прежнее имя исчезло и РОВНО НА ЕГО ПОЗИЦИИ появилось
    // новое. Это не «удалить + создать», а подмена подписи: переносим «токен»,
    // чтобы чип остался тем же элементом (подпись сменится кросс-фейдом,
    // а ширина доедет AnimatedSize — без рывка и без скачка соседей).
    final renamedFrom = <String>{};
    final renamedTo = <String>{};
    for (var i = 0; i < next.length && i < prev.length; i++) {
      final o = prev[i];
      final n = next[i];
      if (o == n || nextSet.contains(o) || prevSet.contains(n)) continue;
      if (renamedFrom.contains(o) || renamedTo.contains(n)) continue;
      renamedFrom.add(o);
      renamedTo.add(n);
      _alias[n] = _alias.remove(o) ?? o;
    }

    // Исчезло (и не переименовано) — остаётся «призраком» на прежнем месте
    // и плавно тает.
    for (var i = 0; i < prev.length; i++) {
      final name = prev[i];
      if (nextSet.contains(name)) continue;
      if (renamedFrom.contains(name)) {
        _alias.remove(name);
        continue;
      }
      _alias.remove(name);
      _ghosts.add(
        _Ghost(
          name,
          i,
          _lastBuilt[name] ?? widget.itemBuilder(context, name),
        ),
      );
    }

    // Появилось — проявится на своём месте.
    for (final name in next) {
      if (prevSet.contains(name) || renamedTo.contains(name)) continue;
      _alias.remove(name);
      _appearing.add(name);
      // Имя вернулось — его «призрак» больше не нужен.
      _ghosts.removeWhere((g) => g.name == name);
    }
    _items = List<String>.from(next);
  }

  /// Один слот ряда: разворачивание/схлопывание при смене состава.
  ///
  /// Смена ШИРИНЫ чипа (переименование, смена набивки у выбранного) едет
  /// внутри самого чипа — там ширина анимируется вместе со скруглением
  /// пилюли. Раньше ширина анимировалась здесь общим [AnimatedSize], и он
  /// резал таблетку прямоугольником: пилюля на глазах теряла скруглённые
  /// концы (острые углы).
  Widget _slot({
    required String slotKey,
    required Widget child,
    required bool removing,
    required bool animate,
    required VoidCallback onDone,
  }) {
    return ItemReveal(
      key: ValueKey(slotKey),
      animate: animate,
      removing: removing,
      duration: widget.duration,
      height: widget.height,
      onDone: onDone,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = <Widget>[];
    for (var i = 0; i <= _items.length; i++) {
      for (final g in _ghosts.where((g) => g.index == i)) {
        slots.add(
          _slot(
            slotKey: 'ghost_${g.name}',
            child: g.child,
            removing: true,
            animate: false,
            onDone: () {
              if (!mounted) return;
              setState(() => _ghosts.remove(g));
            },
          ),
        );
      }
      if (i < _items.length) {
        final name = _items[i];
        final child = widget.itemBuilder(context, name);
        _lastBuilt[name] = child;
        slots.add(
          _slot(
            slotKey: 'chip_${_alias[name] ?? name}',
            child: child,
            removing: false,
            animate: _appearing.contains(name),
            onDone: () {
              if (!mounted || !_appearing.contains(name)) return;
              setState(() => _appearing.remove(name));
            },
          ),
        );
      }
    }
    if (widget.trailing != null) {
      slots.add(
        KeyedSubtree(
          key: const ValueKey('chips_trailing'),
          child: widget.trailing!,
        ),
      );
    }
    final list = ListView(
      scrollDirection: Axis.horizontal,
      children: slots,
    );
    return widget.height == null
        ? list
        : SizedBox(height: widget.height, child: list);
  }
}
