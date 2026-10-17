import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/widgets/category_chip.dart';
import 'package:keramika/widgets/item_reveal.dart';
import 'package:keramika/l10n/locale_provider.dart';
import 'package:keramika/utils/wide_dash_formatter.dart';
import 'package:keramika/widgets/priority_selector.dart';

/// Проверки «плавности» на уровне геометрии: между кадрами элементы не
/// должны прыгать. Это регресс-тесты на жалобы «кнопка расширяется
/// неплавно», «новая категория скачет влево», «таблетка дёргается».

class _ChipsHost extends StatefulWidget {
  const _ChipsHost();

  @override
  State<_ChipsHost> createState() => _ChipsHostState();
}

class _ChipsHostState extends State<_ChipsHost> {
  List<String> items = const ['', 'Работа', 'Спорт', 'Дом'];

  /// Смена состава категорий из теста. `setState` — защищённый член
  /// [State], снаружи его вызывать нельзя: анализатор справедливо ругался
  /// (`invalid_use_of_protected_member`).
  void setItems(List<String> next) => setState(() => items = next);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 760,
            child: ChipsReveal(
              items: items,
              height: 44,
              itemBuilder: (context, value) => CategoryChip(
                label: value.isEmpty ? 'Без категории' : value,
                selected: value == 'Работа',
                onTap: () {},
              ),
              trailing: const SizedBox(
                key: ValueKey<String>('trailing'),
                width: 120,
                height: 36,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ведёт «+ Новая категория» по кадрам и проверяет, что она не прыгает:
/// шаг за кадр ограничен, а движение всё время в одну сторону (никаких
/// откатов назад — именно они читаются как «скачок»).
Future<void> _expectSmoothTrailing(
  WidgetTester tester,
  void Function() mutate,
) async {
  double x() =>
      tester.getTopLeft(find.byKey(const ValueKey<String>('trailing'))).dx;

  final start = x();
  mutate();
  await tester.pump();
  var prev = x();
  final steps = <double>[prev - start];
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    final now = x();
    steps.add(now - prev);
    prev = now;
  }
  final total = prev - start;
  expect(
    total.abs(),
    greaterThan(1.0),
    reason: 'кнопка должна была сдвинуться',
  );
  final dir = total.sign;
  var maxStep = 0.0;
  for (final step in steps) {
    if (step.abs() > maxStep) maxStep = step.abs();
    // Ни один кадр не должен ехать против общего направления больше чем
    // на полпикселя — иначе это рывок туда-обратно.
    expect(step * dir, greaterThan(-0.5), reason: 'откат назад: $steps');
  }
  // Тестовый шрифт вдвое шире настоящего, поэтому порог в пикселях мягкий:
  // важна доля от всего пути, а не абсолют.
  expect(maxStep, lessThan(total.abs() * 0.3 + 2));
}

void main() {
  _dashTests();

  testWidgets('переименование: соседи едут кадр в кадр, без прыжка', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChipsHost());
    await tester.pumpAndSettle();

    final state = tester.state<_ChipsHostState>(find.byType(_ChipsHost));
    await _expectSmoothTrailing(tester, () {
      state.setItems(const ['', 'Работа и учёба', 'Спорт', 'Дом']);
    });
    await tester.pumpAndSettle();
  });

  testWidgets('удаление: «+ Новая категория» уезжает влево плавно', (
    tester,
  ) async {
    await tester.pumpWidget(const _ChipsHost());
    await tester.pumpAndSettle();

    final state = tester.state<_ChipsHostState>(find.byType(_ChipsHost));
    await _expectSmoothTrailing(tester, () {
      state.setItems(const ['', 'Спорт', 'Дом']);
    });
    await tester.pumpAndSettle();
  });

  testWidgets('приоритет: таблетка едет плавно и чуть заезжает за край', (
    tester,
  ) async {
    var value = 0;
    await tester.pumpWidget(
      LocaleProvider(
        locale: const Locale('ru'),
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) => PrioritySelector(
                    value: value,
                    onChanged: (v) => setState(() => value = v),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final track = tester.getRect(find.byType(PrioritySelector));
    final pillFinder = find.byKey(const ValueKey<String>('priority_pill'));

    final gesture = await tester.startGesture(
      Offset(track.left + 40, track.center.dy),
    );
    await tester.pump();

    var prevLeft = tester.getRect(pillFinder).left;
    var maxStep = 0.0;
    // Ведём палец за правый край дорожки — «резинка» должна дать лёгкий
    // заезд, но не улёт.
    for (var i = 1; i <= 30; i++) {
      final x = track.left + 40 + (track.width * 1.2 - 40) * (i / 30);
      await gesture.moveTo(Offset(x, track.center.dy));
      await tester.pump(const Duration(milliseconds: 16));
      final left = tester.getRect(pillFinder).left;
      final step = (left - prevLeft).abs();
      if (step > maxStep) maxStep = step;
      prevLeft = left;
    }

    final overshoot = tester.getRect(pillFinder).right - track.right;
    expect(maxStep, lessThan(14.0), reason: 'таблетка не должна прыгать');
    expect(
      overshoot,
      greaterThan(0.5),
      reason: 'должен быть лёгкий заезд за край',
    );
    expect(overshoot, lessThan(14.0), reason: 'заезд должен быть «чуть»');

    await gesture.up();
    await tester.pumpAndSettle();

    // После отпускания — ровно в своём уровне.
    final settled = tester.getRect(pillFinder);
    expect(settled.right, lessThanOrEqualTo(track.right + 0.5));
  });
}

void _dashTests() {
  testWidgets('любое «узкое» тире в поле ввода становится широким', (
    tester,
  ) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: ctrl,
            inputFormatters: [WideDashFormatter()],
          ),
        ),
      ),
    );
    for (final narrow in [
      '-',
      '\u2010',
      '\u2011',
      '\u2012',
      '\u2013',
      '\u2212',
      '\uFF0D',
    ]) {
      await tester.enterText(find.byType(TextField), 'a${narrow}b');
      await tester.pump();
      expect(
        ctrl.text,
        'a—b',
        reason: 'не заменилось: U+${narrow.codeUnitAt(0).toRadixString(16)}',
      );
    }
    ctrl.dispose();
  });
}
