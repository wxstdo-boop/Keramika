import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/widgets/move_ledger.dart';

/// Проверка «ведомости переезда»: список со стабильными ключами
/// (ReorderableListView) переставляет элементы мгновенно, и [MoveLedger]
/// обязан превратить это в плавное движение БЕЗ мигания на новом месте.
void main() {
  testWidgets('перестановка: в первом же кадре элементы ещё на старых местах', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());

    expect(_y(tester, 'A'), 0);
    expect(_y(tester, 'B'), 100);

    tester.state<_HarnessState>(find.byType(_Harness)).swap();
    await tester.pump();

    // Новая раскладка уже в дереве (B сверху), но нарисованы СТАРЫЕ позиции:
    // карточка не телепортируется и не мигает на новом месте.
    expect(_y(tester, 'B'), 100);
    expect(_y(tester, 'A'), 0);
  });

  testWidgets('переезд промежуточный и финальный: доехали точно на места', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.swap();
    await tester.pump();
    // Первый тик тикер только привязывает часы (значения не меняет) — как на
    // реальном устройстве, где кадры идут каждые 16 мс.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Середина анимации: обе карточки в пути между стартом и целью.
    expect(_y(tester, 'A'), greaterThan(0));
    expect(_y(tester, 'A'), lessThan(150));
    expect(_y(tester, 'B'), lessThan(100));
    expect(_y(tester, 'B'), greaterThan(0));

    await tester.pump(const Duration(milliseconds: 500));
    expect(_y(tester, 'A'), 150);
    expect(_y(tester, 'B'), 0);
  });

  testWidgets('skip (после drag-перетаскивания) — никакой анимации', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    tester.state<_HarnessState>(find.byType(_Harness)).swap(skip: true);
    await tester.pump();

    expect(_y(tester, 'B'), 0);
    expect(_y(tester, 'A'), 150);
  });

  testWidgets('перестроение без смены порядка не двигает карточки', (
    tester,
  ) async {
    await tester.pumpWidget(const _Harness());
    final state = tester.state<_HarnessState>(find.byType(_Harness));

    state.rebuildSame();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(_y(tester, 'A'), 0);
    expect(_y(tester, 'B'), 100);
  });
}

/// Фактическая (с учётом анимации) верхняя координата карточки. Ищем именно
/// Container внутри MoveItem: у Transform его собственный бокс смещением не
/// двигается, сдвиг применяется к потомку.
double _y(WidgetTester tester, String id) => tester
    .getTopLeft(
      find.descendant(
        of: find.byKey(ValueKey(id)),
        matching: find.byType(Container),
      ),
    )
    .dy;

class _Harness extends StatefulWidget {
  const _Harness();

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  late final MoveLedger ledger = MoveLedger(
    duration: const Duration(milliseconds: 400),
    // vsync — сам State: в виджет-тестах тикеры живут на fake-часках binding.
    vsync: this,
  );

  List<String> _order = const ['A', 'B'];
  final Map<String, double> _sizes = const {'A': 100, 'B': 150};

  void swap({bool skip = false}) {
    if (skip) ledger.skipNext();
    setState(() => _order = const ['B', 'A']);
  }

  void rebuildSame() => setState(() {});

  @override
  void dispose() {
    ledger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ledger.plan(_order);
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            for (final id in _order)
              MoveItem(
                key: ValueKey(id),
                id: id,
                ledger: ledger,
                child: Container(
                  height: _sizes[id],
                  color: id == 'A' ? Colors.red : Colors.blue,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
