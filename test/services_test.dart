import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keramika/main.dart' show buildBackupPayload;
import 'package:keramika/models/habit.dart';
import 'package:keramika/models/task.dart';
import 'package:keramika/services/ai_guide_service.dart';
import 'package:keramika/services/habit_service.dart';
import 'package:keramika/services/json_file.dart';
import 'package:keramika/services/nutrition_service.dart';
import 'package:keramika/services/new_year_event_service.dart';
import 'package:keramika/services/reality_check_service.dart';
import 'package:keramika/services/prefs.dart';
import 'package:keramika/services/task_service.dart';

/// Песочница для сервисов: реальный File IO во временную папку +
/// мокнутый SharedPreferences. Каждый тест начинает с пустого хранилища.
void main() {
  late Directory tmpDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    tmpDir = await Directory.systemTemp.createTemp('keramika_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
            if (call.method == 'getApplicationDocumentsDirectory') {
              return tmpDir.path;
            }
            return null;
          },
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    try {
      await tmpDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> resetHabits() async {
    await JsonFile.write('habits', jsonEncode(<Object>[]));
    await HabitService().load();
  }

  group('Habit streaks', () {
    test(
      'первая отметка — стрик 1, повторная в тот же день — без изменений',
      () async {
        await resetHabits();
        final svc = HabitService();
        await svc.add(Habit(id: 'h1', name: 'Run'));

        await svc.toggle('h1');
        expect(svc.habits.first.streak, 1);
        expect(svc.habits.first.doneToday, isTrue);

        // Сняли отметку — doneToday сброшен, стрик цел.
        await svc.toggle('h1');
        expect(svc.habits.first.doneToday, isFalse);
        expect(svc.habits.first.streak, 1);

        // Вернули в тот же день — стрик не удвоился.
        await svc.toggle('h1');
        expect(svc.habits.first.doneToday, isTrue);
        expect(svc.habits.first.streak, 1);
      },
    );

    test('снятие отметки не убивает стрик', () async {
      await resetHabits();
      final svc = HabitService();
      await svc.add(Habit(id: 'h2', name: 'Read'));

      await svc.toggle('h2'); // streak 1
      await svc.toggle('h2'); // сняли
      expect(svc.habits.first.doneToday, isFalse);
      expect(svc.habits.first.streak, 1, reason: 'стрик сохраняется');
    });

    test('отметка на следующий день продлевает цепочку (стрик 2)', () async {
      await resetHabits();
      final svc = HabitService();
      final today = HabitService.mskToday();
      final yesterday = today.subtract(const Duration(days: 1));
      await svc.add(
        Habit(id: 'h3', name: 'Meditate', streak: 1, lastDoneDate: yesterday),
      );

      await svc.toggle('h3');
      expect(svc.habits.first.streak, 2, reason: 'соседний день → +1');
      expect(svc.habits.first.doneToday, isTrue);
    });

    test('пропуск дня обрывает цепочку — стрик сбрасывается на 1', () async {
      await resetHabits();
      final svc = HabitService();
      final today = HabitService.mskToday();
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      await svc.add(
        Habit(id: 'h4', name: 'Gym', streak: 5, lastDoneDate: twoDaysAgo),
      );

      await svc.toggle('h4');
      expect(
        svc.habits.first.streak,
        1,
        reason: 'пропуск ≥2 дней → новая цепочка',
      );
    });

    test('сброс стрика (как в UI): следующий день — стрик 1, не 2', () async {
      await resetHabits();
      final svc = HabitService();
      final today = HabitService.mskToday();
      final yesterday = today.subtract(const Duration(days: 1));
      await svc.add(
        Habit(
          id: 'h6',
          name: 'Run',
          streak: 4,
          doneToday: true,
          lastDoneDate: today,
        ),
      );

      // Точная копия UI-сброса (тройной тап): copyWith + прямая
      // мутация lastDoneDate (copyWith не умеет ставить null).
      final h = svc.habits.first;
      final reset = h.copyWith(streak: 0, doneToday: false);
      reset.lastDoneDate = null;
      await svc.update(reset);
      expect(svc.habits.first.streak, 0);
      expect(svc.habits.first.lastDoneDate, isNull);
      expect(svc.habits.first.doneToday, isFalse);

      // Эмулируем «следующий день»: стрик=0, lastDoneDate=null,
      // doneToday=false — как утром следующего дня после сброса.
      final nextDay = svc.habits.first.copyWith(
        doneToday: false,
        lastDoneDate: yesterday, // вчера был сброс, дата не важна
      );
      nextDay.lastDoneDate = null;
      await svc.update(nextDay);

      await svc.toggle('h6');
      expect(
        svc.habits.first.streak,
        1,
        reason: 'после сброса первая отметка = 1 день, а не 2',
      );
      expect(svc.habits.first.doneToday, isTrue);
      expect(svc.habits.first.lastDoneDate, today);
    });

    test(
      'пропуск ≥2 дней самовосстанавливается при загрузке — стрик 0',
      () async {
        final today = HabitService.mskToday();
        final threeDaysAgo = today.subtract(const Duration(days: 3));
        await JsonFile.write(
          'habits',
          jsonEncode([
            Habit(
              id: 'h8',
              name: 'Stale',
              streak: 6,
              doneToday: true,
              lastDoneDate: threeDaysAgo,
            ).toJson(),
          ]),
        );
        await HabitService().load();
        final svc = HabitService();
        expect(
          svc.habits.first.doneToday,
          isFalse,
          reason: 'вчерашняя галочка не должна висеть как сегодняшняя',
        );
        expect(
          svc.habits.first.streak,
          0,
          reason: 'цепочка оборвана 2+ дня назад — мёртвый счётчик не живёт',
        );
        // Следующая отметка — новое начало, а не «продолжение» старого стрика.
        await svc.toggle('h8');
        expect(svc.habits.first.streak, 1);
        expect(svc.habits.first.doneToday, isTrue);
      },
    );

    test('вчерашняя отметка не обрывает цепочку при загрузке', () async {
      final today = HabitService.mskToday();
      final yesterday = today.subtract(const Duration(days: 1));
      await JsonFile.write(
        'habits',
        jsonEncode([
          Habit(
            id: 'h9',
            name: 'Alive',
            streak: 3,
            doneToday: true,
            lastDoneDate: yesterday,
          ).toJson(),
        ]),
      );
      await HabitService().load();
      final svc = HabitService();
      expect(svc.habits.first.doneToday, isFalse);
      expect(
        svc.habits.first.streak,
        3,
        reason: 'пропущен только сегодняшний день — цепочка жива',
      );
      // Отметка сегодня продлевает: 3 → 4.
      await svc.toggle('h9');
      expect(svc.habits.first.streak, 4);
    });

    test(
      'осиротевший стрик (streak>0 без lastDoneDate) обнуляется при загрузке',
      () async {
        await JsonFile.write(
          'habits',
          jsonEncode([
            Habit(
              id: 'h7',
              name: 'Orphan',
              streak: 5,
              doneToday: false,
            ).toJson(),
          ]),
        );
        await HabitService().load();
        final svc = HabitService();
        expect(
          svc.habits.first.streak,
          0,
          reason: 'мёртвый счётчик без даты не должен «оживать»',
        );
        // После ремонта первая отметка = 1 день, а не продолжение старого счёта.
        await svc.toggle('h7');
        expect(svc.habits.first.streak, 1);
        expect(svc.habits.first.lastDoneDate, isNotNull);
      },
    );

    test('сериализация сохраняет стрик, lastDoneDate, pin и тип', () {
      final h = Habit(
        id: 'h5',
        name: 'Water',
        streak: 7,
        doneToday: true,
        pinned: true,
        type: 'bad',
        lastDoneDate: HabitService.mskToday(),
      );
      final restored = habitsFromJson(habitsToJson([h])).first;
      expect(restored.streak, 7);
      expect(restored.doneToday, isTrue);
      expect(restored.pinned, isTrue);
      expect(restored.type, 'bad');
      expect(restored.lastDoneDate, h.lastDoneDate);
    });
  });

  group('Nutrition — 20-дневная история', () {
    Future<void> resetNutrition() async {
      await JsonFile.write('nutrition_meals', jsonEncode(<Object>[]));
      await NutritionService().load();
    }

    test('при загрузке приёмы старше 20 дней вычищаются с диска', () async {
      await resetNutrition();
      final now = DateTime.now();
      final oldMeal = Meal(
        id: 'old',
        name: 'Old meal',
        calories: 500,
        date: now.subtract(const Duration(days: 21)),
      );
      final recentMeal = Meal(
        id: 'recent',
        name: 'Recent meal',
        calories: 300,
        date: now,
      );
      await JsonFile.write(
        'nutrition_meals',
        jsonEncode([oldMeal.toJson(), recentMeal.toJson()]),
      );

      await NutritionService().load();

      final svc = NutritionService();
      expect(svc.meals.map((m) => m.id), contains('recent'));
      expect(svc.meals.map((m) => m.id), isNot(contains('old')));

      // Старый приём удалён и из файла — история реально 20 дней.
      final raw = await JsonFile.read('nutrition_meals');
      final saved = jsonDecode(raw!) as List;
      expect(saved.map((e) => (e as Map)['id']), isNot(contains('old')));
    });

    test('неделю назад приём всё ещё виден — окно стало 20 дней', () async {
      await resetNutrition();
      final now = DateTime.now();
      final week = Meal(
        id: 'week',
        name: 'Неделя назад',
        calories: 400,
        date: now.subtract(const Duration(days: 9)),
      );
      await JsonFile.write('nutrition_meals', jsonEncode([week.toJson()]));
      await NutritionService().load();

      expect(NutritionService().meals.map((m) => m.id), contains('week'));
      expect(NutritionService().totalCalories, 400);
    });

    test('totalCalories считает только видимые 20 дней', () async {
      await resetNutrition();
      final now = DateTime.now();
      await NutritionService().add(
        Meal(id: 'a', name: 'A', calories: 200, date: now),
      );
      // Подсеваем старый приём мимо add(), как если бы он остался от прошлого запуска.
      final old = Meal(
        id: 'old',
        name: 'Old',
        calories: 900,
        date: now.subtract(const Duration(days: 25)),
      );
      await JsonFile.write(
        'nutrition_meals',
        jsonEncode([
          ...NutritionService().meals.map((m) => m.toJson()),
          old.toJson(),
        ]),
      );
      await NutritionService().load();

      expect(
        NutritionService().totalCalories,
        200,
        reason: 'калории старого приёма не должны попадать в счётчик',
      );
    });

    test('приём с названием и без калорий и воды записывается', () async {
      // Так Ада записывает «я съел на обед суп»: блюдо известно,
      // калорийность нет. Раньше такой записи не было, и проверка
      // «нужны калории или вода» ломала именно её.
      await resetNutrition();
      await NutritionService().add(
        Meal(id: 'soup', name: 'суп', calories: 0, date: DateTime.now()),
      );

      expect(NutritionService().meals.map((m) => m.id), contains('soup'));
      expect(NutritionService().todayMacros.carbs, 0);
    });

    test('пустая запись без названия, калорий и воды отклоняется', () async {
      await resetNutrition();
      await expectLater(
        NutritionService().add(
          Meal(id: 'empty', name: '', calories: 0, date: DateTime.now()),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'вода: старая запись без поля воды читается и не считается приёмом',
      () async {
        await JsonFile.write(
          'nutrition_meals',
          jsonEncode([
            {
              'id': 'legacy',
              'name': 'Хлеб',
              'calories': 100,
              'date': DateTime.now().toIso8601String(),
            },
            {
              'id': 'water',
              'name': '',
              'calories': 0,
              'water': 250,
              'date': DateTime.now().toIso8601String(),
            },
          ]),
        );
        await NutritionService().load();

        final legacy = NutritionService().meals.firstWhere(
          (m) => m.id == 'legacy',
        );
        expect(legacy.water, 0);
        final water = NutritionService().meals.firstWhere(
          (m) => m.id == 'water',
        );
        expect(water.isWaterOnly, isTrue);
        expect(NutritionService().todayWater, 250);
        expect(NutritionService().todayCalories, 100);
      },
    );

    test('норма зажимается в границы и переживает перезагрузку', () async {
      SharedPreferences.setMockInitialValues({});
      globalPrefs = await SharedPreferences.getInstance();
      await NutritionService().setNorm(999999);
      expect(NutritionService().norm, kMaxCalorieNorm);

      await NutritionService().setNorm(10);
      expect(NutritionService().norm, kMinCalorieNorm);

      await NutritionService().setNorm(2400);
      await NutritionService().load();
      expect(NutritionService().norm, 2400);
    });

    test('БЖУ: белковое блюдо даёт много белка и мало углеводов', () {
      final meat = MealKind.meat.macrosFor(500);
      expect(meat.protein, greaterThan(meat.carbs));
      expect(meat.fat, greaterThan(0));
      // Доли калорийности в сумме дают саму калорийность (±округление).
      final kcal = meat.protein * 4 + meat.fat * 9 + meat.carbs * 4;
      expect(kcal, closeTo(500, 12));
    });

    test('график тренда — всегда полная ширина окна истории', () async {
      await resetNutrition();
      await NutritionService().add(
        Meal(id: 'a', name: 'Каша', calories: 300, date: DateTime.now()),
      );
      final days = NutritionService().days;
      expect(days.length, kNutritionHistoryDays);
      expect(days.last.calories, 300);
      expect(days.first.meals, 0);
    });
  });

  group('Ивент — собранные шапки не имеют права пропадать', () {
    const eventFile = 'ny_event_2027';

    /// И сервис, и каталог [JsonFile] — синглтоны на весь прогон, поэтому
    /// каждый тест начинается с чистого файла и обнулённого кэша.
    Future<NewYearEventService> freshEvent() async {
      await JsonFile.remove(eventFile);
      final svc = NewYearEventService();
      await svc.reset();
      return svc;
    }

    test('забранная шапка лежит на диске, а не только в памяти', () async {
      final svc = await freshEvent();

      expect(await svc.markToday(), isTrue);

      final raw = await JsonFile.read(eventFile);
      expect(
        raw,
        isNotNull,
        reason: 'после «Забрать» файл обязан существовать',
      );
      final stored = Map<String, bool>.from(jsonDecode(raw!) as Map);
      expect(stored.values.where((v) => v), hasLength(1));
      expect(svc.hats, 1);
    });

    test('перезапуск (новое чтение файла) не теряет шапки', () async {
      final svc = await freshEvent();
      await svc.markToday();

      // Повторное «забери сегодня» — отказ, а не вторая шапка.
      expect(await svc.markToday(), isFalse);
      // Счётчик берётся из файла, а не из памяти виджета.
      expect(await svc.hatCount(), 1);
      expect(svc.currentDay, 2);
    });

    test('номер дня = сколько шапок собрано + 1, но не больше 12', () async {
      final svc = await freshEvent();
      final now = DateTime.now();
      final dates = {
        for (var i = 0; i < NewYearEventService.totalDays + 3; i++)
          '${now.year - 1}-12-${(i + 1).toString().padLeft(2, '0')}': true,
      };
      await JsonFile.write(eventFile, jsonEncode(dates));

      expect(await svc.hatCount(), NewYearEventService.totalDays + 3);
      expect(svc.currentDay, NewYearEventService.totalDays);
    });

    test(
      'подарок по умолчанию не выдан, после выдачи расширяет лимиты',
      () async {
        final svc = await freshEvent();
        expect(svc.prizeGranted, isFalse);
        expect(NutritionService().historyDays, kNutritionHistoryDays);
        expect(TaskService().maxCategories, kMaxCategories);

        await svc.grantPrize();

        expect(svc.prizeGranted, isTrue);
        expect(NutritionService().historyDays, kNutritionPrizeHistoryDays);
        expect(TaskService().maxCategories, kMaxPrizeCategories);
      },
    );

    test(
      'доводка до 12-го дня пишет календарные даты ивента, а не «сегодня»',
      () async {
        final svc = await freshEvent();

        await svc.fillTo(NewYearEventService.totalDays);

        expect(await svc.hatCount(), NewYearEventService.totalDays);
        expect(svc.currentDay, NewYearEventService.totalDays);
        final stored = Map<String, bool>.from(
          jsonDecode((await JsonFile.read(eventFile))!) as Map,
        );
        // Иначе доводка выглядела бы как одна шапка, забранная двадцать раз.
        expect(
          stored.keys,
          containsAll(<String>['2026-12-21', '2027-01-01']),
          reason: '12 шапок = 12 разных дней ивента',
        );
        // 12-й день собран → подарок выдаётся и это видно после перечитывания.
        expect(await svc.grantPrize(), isTrue);
        expect(svc.prizeGranted, isTrue);
      },
    );

    test('сброс убирает и шапки, и подарок', () async {
      final svc = await freshEvent();
      await svc.markToday();
      await svc.grantPrize();

      await svc.reset();

      expect(await svc.hatCount(), 0);
      expect(svc.prizeGranted, isFalse);
      expect(NutritionService().historyDays, kNutritionHistoryDays);
    });
  });

  group('Backup payload', () {
    test('экспорт содержит все разделы данных и настройки', () async {
      await resetHabits();
      await JsonFile.write('nutrition_meals', jsonEncode(<Object>[]));
      await globalPrefs.setString('app_pin', '1234');
      await globalPrefs.setString('setting_theme', 'rose');

      final payload = await buildBackupPayload();

      for (final key in [
        'habits',
        'tasks',
        'task_categories',
        'alarms',
        'app_timers',
        'reality_check_data',
        'nutrition_meals',
      ]) {
        expect(payload.containsKey(key), isTrue, reason: 'нет ключа $key');
      }
      expect(payload['app_pin'], '1234');
      expect(payload['setting_theme'], 'rose');
    });
  });

  group('Ada undo', () {
    test('локальный парсер создаёт привычку, undo удаляет её', () async {
      await resetHabits();
      AiGuideService.lastAction = null;

      final reply = await AiGuideService.send(
        userText: 'создай привычку пить воду',
        history: const [],
        languageCode: 'ru',
      );

      expect(reply, contains('пить воду'));
      expect(
        HabitService().habits.any((h) => h.name.contains('пить воду')),
        isTrue,
      );
      expect(AiGuideService.lastAction, isNotNull);
      expect(AiGuideService.lastAction!.wasCreate, isTrue);

      final undo = await AiGuideService.undoLastAction();
      expect(undo, contains('Отменено'));
      expect(
        HabitService().habits.any((h) => h.name.contains('пить воду')),
        isFalse,
        reason: 'созданная привычка должна удалиться при отмене',
      );
    });

    test('парсер: инфинитивы и естественные фразы создают задачи', () async {
      await JsonFile.write('tasks', jsonEncode(<Object>[]));
      await TaskService().load();
      final r1 = await AiGuideService.send(
        userText: 'добавить задачу вынести мусор',
        history: const [],
        languageCode: 'ru',
      );
      expect(r1, contains('вынести мусор'));
      expect(
        TaskService().tasks.any((t) => t.title.contains('вынести мусор')),
        isTrue,
      );

      final r2 = await AiGuideService.send(
        userText: 'мне нужно добавить задачу позвонить маме',
        history: const [],
        languageCode: 'ru',
      );
      expect(r2, contains('позвонить маме'));
      expect(
        TaskService().tasks.any((t) => t.title.contains('позвонить маме')),
        isTrue,
      );
    });

    test(
      'парсер: проверка реальности без слова «реальности» в названии',
      () async {
        await JsonFile.write('reality_checks', jsonEncode(<Object>[]));
        await RealityCheckService().load();
        final reply = await AiGuideService.send(
          userText: 'создай проверку реальности посчитать пальцы',
          history: const [],
          languageCode: 'ru',
        );
        expect(reply, contains('посчитать пальцы'));
        expect(
          RealityCheckService().checks.any(
            (c) => c.question.contains('посчитать пальцы'),
          ),
          isTrue,
        );
        expect(
          RealityCheckService().checks.any(
            (c) => c.question.startsWith('реальности'),
          ),
          isFalse,
          reason: 'слово «реальности» не должно попадать в название',
        );
      },
    );

    test('парсер: приём пищи «я съел на обед суп» → блюдо «суп»', () async {
      await JsonFile.write('meals', jsonEncode(<Object>[]));
      await NutritionService().load();
      final reply = await AiGuideService.send(
        userText: 'я съел на обед суп',
        history: const [],
        languageCode: 'ru',
      );
      expect(reply, contains('суп'));
    });

    test(
      'парсер: команда без названия отвечает по-русски, без облака',
      () async {
        final reply = await AiGuideService.send(
          userText: 'добавить задачу',
          history: const [],
          languageCode: 'ru',
        );
        expect(reply, contains('Что записать'));
        expect(reply, isNot(contains('курорт')));
      },
    );

    test('удаление через парсер, undo восстанавливает задачу', () async {
      await JsonFile.write('tasks', jsonEncode(<Object>[]));
      await TaskService().load();
      final svc = TaskService();
      await svc.add(Task(id: 't1', title: 'Купить молоко'));
      AiGuideService.lastAction = null;

      final reply = await AiGuideService.send(
        userText: 'удали задачу купить молоко',
        history: const [],
        languageCode: 'ru',
      );

      expect(reply, contains('удален'));
      expect(TaskService().tasks.any((t) => t.id == 't1'), isFalse);
      expect(AiGuideService.lastAction, isNotNull);
      expect(AiGuideService.lastAction!.wasCreate, isFalse);

      final undo = await AiGuideService.undoLastAction();
      expect(undo, contains('Отменено'));
      expect(
        TaskService().tasks.any((t) => t.id == 't1'),
        isTrue,
        reason: 'удалённая задача должна восстановиться при отмене',
      );
    });
  });
}
