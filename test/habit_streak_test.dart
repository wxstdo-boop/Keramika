import 'package:flutter_test/flutter_test.dart';
import 'package:keramika/models/habit.dart';
import 'package:keramika/services/habit_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Habit makeHabit({int streak = 0, DateTime? lastDone, bool doneToday = false}) {
    return Habit(
      id: 'h1',
      name: 'test',
      streak: streak,
      lastDoneDate: lastDone,
      doneToday: doneToday,
      type: 'good',
    );
  }

  /// Прямо подменяем состояние привычки в сервисе (через load с json),
  /// чтобы симулировать «прошедшие дни» — toggle использует реальный
  /// mskToday(), поэтому прошлые дни задаём датами lastDoneDate.
  Future<void> seed(HabitService svc, Habit h) async {
    await svc.load();
    // добавляем через add() с пустым reminderTime — без уведомлений
    final fresh = Habit(
      id: h.id,
      name: h.name,
      streak: h.streak,
      lastDoneDate: h.lastDoneDate,
      doneToday: h.doneToday,
      type: h.type,
    );
    if (svc.habits.isEmpty) {
      await svc.add(fresh);
    } else {
      await svc.update(fresh);
    }
  }

  Habit one(HabitService svc) => svc.habits.first;

  DateTime day(int back) =>
      HabitService.mskToday().subtract(Duration(days: back));

  test('check → uncheck → check: streak preserved', () async {
    final svc = HabitService();
    // Симулируем: вчера было отмечено (streak 3 через день назад… на самом
    // деле chain: 3 дня подряд, последний — вчера).
    await seed(svc, makeHabit(streak: 3, lastDone: day(1)));

    await svc.toggle('h1'); // сегодня: streak 4
    expect(one(svc).streak, 4);
    expect(one(svc).doneToday, true);

    await svc.toggle('h1'); // снять
    expect(one(svc).streak, 3);
    expect(one(svc).doneToday, false);
    expect(one(svc).lastDoneDate, day(1));

    await svc.toggle('h1'); // снова поставить
    expect(one(svc).streak, 4);
    expect(one(svc).doneToday, true);
  });

  test('check → uncheck → check → uncheck → check (второй раз снять)', () async {
    final svc = HabitService();
    await seed(svc, makeHabit(streak: 3, lastDone: day(1)));

    await svc.toggle('h1'); // check
    await svc.toggle('h1'); // uncheck #1
    await svc.toggle('h1'); // check
    await svc.toggle('h1'); // uncheck #2
    expect(one(svc).streak, 3);
    expect(one(svc).doneToday, false);
    expect(one(svc).lastDoneDate, day(1));

    await svc.toggle('h1'); // check снова
    expect(one(svc).streak, 4);
    expect(one(svc).doneToday, true);
    expect(one(svc).lastDoneDate, HabitService.mskToday());
  });

  test('fresh habit: check → uncheck ×2 → check: streak = 1', () async {
    final svc = HabitService();
    await seed(svc, makeHabit());

    for (var i = 0; i < 4; i++) {
      await svc.toggle('h1');
    }
    // check, uncheck, check, uncheck
    expect(one(svc).streak, 0);
    expect(one(svc).doneToday, false);
    expect(one(svc).lastDoneDate, null);

    await svc.toggle('h1');
    expect(one(svc).streak, 1);
    expect(one(svc).doneToday, true);
  });

  test('uncheck после «пропуска дня» (normalize сбросил стрик)', () async {
    final svc = HabitService();
    // lastDone 3 дня назад, стрик мёртвый, но записан как 5
    await seed(svc, makeHabit(streak: 5, lastDone: day(3)));

    await svc.toggle('h1'); // normalize: streak=0, потом check → streak=1
    expect(one(svc).streak, 1);
    expect(one(svc).doneToday, true);

    await svc.toggle('h1'); // uncheck
    expect(one(svc).streak, 0);
    expect(one(svc).lastDoneDate, null);

    await svc.toggle('h1'); // check
    expect(one(svc).streak, 1);
    expect(one(svc).doneToday, true);
  });

  test('два дня подряд после uncheck: стрик растёт как надо', () async {
    final svc = HabitService();
    // Вчера было: streak 1, lastDone вчера
    await seed(svc, makeHabit(streak: 1, lastDone: day(1)));

    await svc.toggle('h1'); // сегодня check → 2
    expect(one(svc).streak, 2);

    await svc.toggle('h1'); // uncheck → 1, lastDone вчера
    expect(one(svc).streak, 1);

    await svc.toggle('h1'); // check → 2
    expect(one(svc).streak, 2);

    await svc.toggle('h1'); // uncheck → 1
    expect(one(svc).streak, 1);
    expect(one(svc).lastDoneDate, day(1));

    await svc.toggle('h1'); // check → 2
    expect(one(svc).streak, 2);
    expect(one(svc).doneToday, true);
    expect(one(svc).lastDoneDate, HabitService.mskToday());
  });
}
