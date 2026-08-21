import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/services/habit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime day(int back) =>
      HabitService.mskToday().subtract(Duration(days: back));

  Future<HabitService> makeSvc(List<Habit> habits) async {
    final svc = HabitService();
    svc.debugClear();
    await svc.load();
    for (final h in habits) {
      await svc.add(Habit(
        id: h.id,
        name: h.name,
        streak: h.streak,
        lastDoneDate: h.lastDoneDate,
        doneToday: h.doneToday,
        type: h.type,
      ));
    }
    return svc;
  }

  test('first habit streak grows like others', () async {
    final svc = await makeSvc([
      Habit(id: 'h1', name: 'First', type: 'good'),
      Habit(id: 'h2', name: 'Second', type: 'good'),
      Habit(id: 'h3', name: 'Third', type: 'good'),
    ]);

    // Вчера все три были отмечены (chain 1 день).
    await svc.update(Habit(
      id: 'h1',
      name: 'First',
      type: 'good',
      streak: 1,
      lastDoneDate: day(1),
    ));
    await svc.update(Habit(
      id: 'h2',
      name: 'Second',
      type: 'good',
      streak: 1,
      lastDoneDate: day(1),
    ));
    await svc.update(Habit(
      id: 'h3',
      name: 'Third',
      type: 'good',
      streak: 1,
      lastDoneDate: day(1),
    ));

    // Отмечаем ПЕРВУЮ (h1).
    await svc.toggle('h1');
    expect(svc.habits.firstWhere((h) => h.id == 'h1').streak, 2,
        reason: 'h1 (first) streak after check today');

    // Отмечаем остальных.
    await svc.toggle('h2');
    await svc.toggle('h3');
    expect(svc.habits.firstWhere((h) => h.id == 'h2').streak, 2);
    expect(svc.habits.firstWhere((h) => h.id == 'h3').streak, 2);

    // Снимаем первую и ставим обратно.
    await svc.toggle('h1');
    expect(svc.habits.firstWhere((h) => h.id == 'h1').streak, 1);
    await svc.toggle('h1');
    expect(svc.habits.firstWhere((h) => h.id == 'h1').streak, 2);
  });

  test('orphaned state streak0+dateToday heals on check (real phone data)',
      () async {
    // Точное состояние первой привычки на телефоне: streak 0, дата =
    // сегодня, галочка снята. Осталось от старого бага, когда снятие
    // галочки не очищало lastDoneDate. Отметка должна дать стрик 1,
    // а не застрять на 0 в ветке re-mark.
    final svc = await makeSvc([
      Habit(
        id: 'h1',
        name: 'First',
        type: 'good',
        streak: 0,
        lastDoneDate: HabitService.mskToday(),
        doneToday: false,
      ),
    ]);

    await svc.toggle('h1');
    final h = svc.habits.first;
    expect(h.streak, 1, reason: 'check on orphaned state gives streak 1');
    expect(h.doneToday, true);
  });

  test('normalizeIfDayChanged heals orphaned state (streak0+dateToday)',
      () async {
    final svc = await makeSvc([
      Habit(
        id: 'h1',
        name: 'First',
        type: 'good',
        streak: 0,
        lastDoneDate: HabitService.mskToday(),
        doneToday: false,
      ),
    ]);
    // Вызываем нормализацию — «осиротевший» след должен стереться:
    // дата сегодня при нулевом стрике и снятой галочке — бессмыслица.
    svc.normalizeIfDayChanged();
    final h = svc.habits.first;
    expect(h.lastDoneDate, isNull,
        reason: 'orphaned today-date cleared by normalize');
    expect(h.streak, 0);

    // После очистки отметка идёт по ветке «первая в жизни» — стрик 1.
    await svc.toggle('h1');
    expect(svc.habits.first.streak, 1);
  });
}
