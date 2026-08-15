# -*- coding: utf-8 -*-
import io

p = 'lib/services/ai_guide_service.dart'
s = io.open(p, encoding='utf-8').read()

MEDAL = '\U0001F396\U0000FE0F'
HEART = '\U00002764\U0000FE0F'
TROPHY = '\U0001F3C6'
HUG = '\U0001F49B'

anchor = "  // ---- Инструменты Ады: создание привычек/задач/будильников/РП ----"
add = '''  /// Награды Ады: одноразовые поздравления за достижения.
  /// - Стрики привычек на вехах 3/7/14/30/60/100/150/200/300/365 дней
  ///   (награждается КАЖДАЯ веха, ключ = habit.id + streak — повторно
  ///   не выдаётся, пока серия не дорастёт до следующей вехи).
  /// - «Все задачи выполнены» — раз в день.
  /// Возвращает тексты наград и помечает их выданными (globalPrefs).
  static Future<List<String>> collectRewards(String languageCode) async {
    final ru = languageCode == 'ru';
    final fr = languageCode == 'fr';
    final rewards = <String>[];
    try {
      await Future.wait([HabitService().load(), TaskService().load()]);
    } catch (_) {}
    final done = (globalPrefs.getStringList('ai_rewards_done') ?? <String>[]).toSet();
    var changed = false;
    String text(String ruT, String frT, String enT) =>
        ru ? ruT : (fr ? frT : enT);
    // Вехи стриков.
    const milestones = [3, 7, 14, 30, 60, 100, 150, 200, 300, 365];
    for (final h in HabitService().habits) {
      if (h.streak > 0 && milestones.contains(h.streak)) {
        final key = 'streak_${h.id}_${h.streak}';
        if (!done.contains(key)) {
          done.add(key);
          changed = true;
          rewards.add(text(
            'MEDAL ${h.title}: серия ${_streakUnit(h.streak, ru)} — ${h.streak}! Ты настоящий герой, я горжусь тобой HEART',
            'MEDAL ${h.title} : série de ${h.streak} jours ! Tu es un vrai héros, je suis fière de toi HEART',
            'MEDAL ${h.title}: ${h.streak}-day streak! You are a true hero, I am so proud of you HEART',
          ));
        }
      }
    }
    // Все задачи выполнены — раз в день.
    final tasks = TaskService().tasks;
    if (tasks.isNotEmpty && tasks.every((t) => t.done)) {
      final key = 'all_done_${_todayKey()}';
      if (!done.contains(key)) {
        done.add(key);
        changed = true;
        rewards.add(text(
          'TROPHY Все задачи выполнены! День закрыт на отлично. Обнимаю тебя HUG',
          'TROPHY Toutes les tâches sont terminées ! Journée parfaite. Gros câlin HUG',
          'TROPHY All tasks done! Day closed perfectly. Big hug HUG',
        ));
      }
    }
    if (changed) {
      await globalPrefs.setStringList('ai_rewards_done', done.toList());
    }
    return rewards;
  }

  static String _streakUnit(int n, bool ru) {
    if (!ru) return 'days';
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'день';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня';
    return 'дней';
  }

'''
add = add.replace('MEDAL', MEDAL).replace('HEART', HEART).replace('TROPHY', TROPHY).replace('HUG', HUG)

assert anchor in s
s = s.replace(anchor, add + anchor, 1)
io.open(p, 'w', encoding='utf-8', newline='').write(s)
print('service OK')
