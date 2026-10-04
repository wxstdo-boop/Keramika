import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;

/// Ведомость плавного переезда элементов списка со стабильными ключами.
///
/// [ReorderableListView] с `ValueKey` переставляет карточки МГНОВЕННО: скрытой
/// анимации позиции у него нет, поэтому закрепление/открепление привычки
/// выглядело как телепорт.
///
/// Экран вызывает [MoveLedger.plan] на каждой сборке списка с НОВЫМ порядком
/// ключей. Ведомость сравнивает порядок с предыдущим и по высотам элементов
/// (их бесшимо сообщает [MoveItem] через [_HeightReport]) считает, на сколько
/// пикселей уехал каждый элемент. Сдвиг применяется в ТОМ ЖЕ кадре, что и
/// новая раскладка, поэтому карточка не мигает на новом месте, а выезжает из
/// старого.
class MoveLedger {
  MoveLedger({
    required TickerProvider vsync,
    this.duration = const Duration(milliseconds: 420),
  }) : _vsync = vsync;

  /// Кривая переезда: быстрый старт и мягкая посадка.
  static const Curve curve = Curves.easeOutCubic;

  final TickerProvider _vsync;
  final Duration duration;

  final Map<String, double> _heights = <String, double>{};
  final Map<String, double> _dy = <String, double>{};
  List<String> _order = const <String>[];
  AnimationController? _ctrl;
  bool _skip = false;

  /// Фаза переезда: 0 — элемент ещё на старом месте, 1 — доехал.
  Animation<double>? get animation => _ctrl;

  /// На сколько пикселей элемент уехал с прошлого кадра (null — не едет).
  double? dyOf(String id) => _dy[id];

  /// Пропустить ОДИН ближайший пересчёт порядка: именно так ведёт себя
  /// перетаскивание — [ReorderableListView] показывает новую раскладку ещё во
  /// время драга, и «переезд» из старого порядка был бы отдачей назад.
  void skipNext() => _skip = true;

  void _report(String id, double height) {
    if (height > 0 && _heights[id] != height) _heights[id] = height;
  }

  /// Новый порядок ключей списка. Возвращает true, если сейчас что-то едет.
  bool plan(List<String> order) {
    final previous = _order;
    _order = order;
    if (_skip) {
      _skip = false;
      _dy.clear();
      return false;
    }
    if (_isSameOrder(previous, order)) {
      // Порядок не менялся: начатый переезд досматриваем, новый не начинаем.
      return _dy.isNotEmpty;
    }
    _dy.clear();
    if (previous.isEmpty) return false;

    final before = _positions(previous);
    final after = _positions(order);
    final at = <String, int>{
      for (var i = 0; i < previous.length; i++) previous[i]: i,
    };
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      final j = at[id];
      if (j == null) continue; // элемент появился — ехать неоткуда
      final d = before[j] - after[i];
      if (d.abs() > 0.5) _dy[id] = d;
    }
    if (_dy.isEmpty) return false;

    // Новый контроллер, а не reset(): у свежего значение уже 0 и слушателей
    // нет, поэтому первый же кадр новой раскладки рисует элементы на СТАРЫХ
    // местах (никакого мигания), а старт откладывается на post-frame.
    final old = _ctrl;
    if (old != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    _ctrl = AnimationController(vsync: _vsync, duration: duration, value: 0);
    final started = _ctrl!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(started, _ctrl)) started.forward();
    });
    return true;
  }

  /// Координаты верхних краёв элементов: префиксные суммы высот. Скролл на
  /// них не влияет (высоты берутся из раскладки), поэтому дельта честная в
  /// любой момент прокрутки.
  List<double> _positions(List<String> order) {
    final fallback = _averageHeight;
    final out = List<double>.filled(order.length, 0);
    var y = 0.0;
    for (var i = 0; i < order.length; i++) {
      out[i] = y;
      y += _heights[order[i]] ?? fallback;
    }
    return out;
  }

  double get _averageHeight {
    if (_heights.isEmpty) return 0;
    var sum = 0.0;
    for (final h in _heights.values) {
      sum += h;
    }
    return sum / _heights.length;
  }

  bool _isSameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    _ctrl?.dispose();
    _ctrl = null;
  }
}

/// Оборачивает элемент списка: несёт его ключ, сообщает высоту и, если
/// раскладка перестроилась, плавно доезжает до нового места.
class MoveItem extends StatelessWidget {
  const MoveItem({
    required super.key,
    required this.id,
    required this.ledger,
    required this.child,
  });

  final String id;
  final MoveLedger ledger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final measured = _HeightReport(id: id, ledger: ledger, child: child);
    final dy = ledger.dyOf(id);
    final anim = ledger.animation;
    if (dy == null || dy == 0 || anim == null) return measured;
    return AnimatedBuilder(
      animation: anim,
      child: measured,
      builder: (BuildContext context, Widget? child) => Transform.translate(
        offset: Offset(0, dy * (1 - MoveLedger.curve.transform(anim.value))),
        child: child,
      ),
    );
  }
}

/// Пассивный замер высоты элемента (нужен для расчёта дельты переезда).
class _HeightReport extends SingleChildRenderObjectWidget {
  const _HeightReport({required this.id, required this.ledger, super.child});

  final String id;
  final MoveLedger ledger;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReport(id: id, ledger: ledger);
}

class _RenderHeightReport extends RenderProxyBox {
  _RenderHeightReport({required this.id, required this.ledger});

  final String id;
  final MoveLedger ledger;

  @override
  void performLayout() {
    super.performLayout();
    ledger._report(id, size.height);
  }
}
