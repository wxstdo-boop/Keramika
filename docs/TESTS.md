# Состояние тестов

## Текущее состояние (проверено в CI)

GitHub Actions, workflow `CI` (`.github/workflows/ci.yml`), Flutter **3.47.5**,
ветка `main`, 2026-11-14:

```
flutter pub get --enforce-lockfile
flutter analyze                 →  No issues found!
flutter test                    →  All tests passed! (410, 6 skipped)
```

Прогон зелёный целиком: **410 тестов в 72 файлах**, падений нет; 6 тестов
помечены `skip` — это ручные прогоны, которым нужны сеть и токен
(`live_forge_test.dart`). В том числе проходит `exit_dialog_localization_test.dart`
(3 теста: ru/en/fr).

Число тестов берётся из итога прогона `flutter test` (410); объявлений
`test(` / `testWidgets(` в `test/*.dart` чуть больше, потому что часть
проверок объявлена внутри общих хелперов. Файлов `test/*.dart` — 72.

Эти же команды CI выполняет на каждый pull request и на каждый push в `main`,
поэтому состояние воспроизводимо на раннере GitHub: локальный SDK для проверки
не нужен.

## Что покрыто

| Область | Файлы |
|---|---|
| Логика привычек и стриков | `habit_streak_test`, `habit_first_streak_test`, `services_test` |
| Слой плавности | `page_transitions_test`, `smooth_typing_test`, `smooth_tooltip_test`, `section_pill_transition_test`, `section_pill_drag_test`, `chips_animation_test`, `volumetric_switch_test`, `rolling_counter_test` |
| Настройки и «убрать анимации» | `preferences_test` (переживают перезапуск, гасят вечные петли), `app_version_test` |
| Будильники и уведомления | `alarm_scheduler_test`, `notification_service_test`, `remind_all_chip_test` |
| ИИ-проводник Ада и «Кузница» | `services_test`, `forge_service_test`, `forge_screen_test`, `live_forge_test` (ручной, `skip`) |
| Данные и миграции | `json_file_test`, `migration_test`, `move_ledger_test` |
| Локализация и тексты | `translations_parity_test`, `exit_dialog_localization_test`, `wide_dash_test` |
| Экраны (смоук) | `smoke_test`, `nutrition_interactions_test`, `stats_stretch_test`, `task_shelves_test`, `developer_corner_screen_test`, `changelog_screen_test` |

## Скриншоты для README

Отдельно от `test/` лежит генератор витрины — `tool/screenshots/render_screenshots.dart`.
Он монтирует реальные экраны в точной теме приложения и рендерит PNG в
`docs/screenshots/`:

```bash
flutter test tool/screenshots/render_screenshots.dart
```

Файл вынесен из `test/`, поэтому обычный `flutter test` его не запускает.

## История разборов (снимки прошлых коммитов)

Всё ниже — разборы падений, сделанные когда-то на коммитах `8925a78` и
`0cfb334`. Это **история, а не текущее состояние**: после этих снимков в
репозиторий вошли исправления, и заново эти разборы не перепроверялись. Числа и
списки падений здесь могут расходиться с текущими (410 тестов, падений нет).

### Снимок на коммите `0cfb334`

```
flutter analyze   →  No issues found!
flutter test      →  +87 / -16   (103 проверки)
```

`flutter analyze` чистый. На том снимке падали 16 тестов — ниже разбор на то, что
падало до этого коммита, а что появилось вместе с новым кодом. (Позже был ещё
один снимок: «All tests passed! (115)» — он тоже не совпадает с текущим набором
из 410 тестов.)

### Как проверялось

Сравнение шло против чистого worktree на коммите `8925a78` (`git worktree add
--detach`). Важная деталь: **сам `8925a78` не компилировался** — в нём были
три ошибки (`home_screen.dart:353` — несуществующий именованный параметр
`pillIndex`, `tasks_screen.dart:37,39,70` — незавершённый код). Поэтому в
baseline `services_test.dart` не загружался вообще, и часть «новых» падений —
это просто тесты, которые впервые удалось запустить.

### Падали и раньше (не регрессии)

| Тест | Причина |
|---|---|
| `exit_dialog_localization_test` ×3 | **Устарело.** Тест уже текстовый (`find.text` для ru/en/fr), golden-картинок и «тофу»-глифов в нём нет. PNG-эталоны `test/goldens/dialog_*.png` осиротели (кодом не использовались) и удалены. Если падает — причина в тексте/вёрстке диалога, не в шрифте. |
| `sliding_picker_test` ×3 | Жестовые сценарии: перетаскивание, быстрый флинг, тап по соседнему чипу. `onChanged` срабатывает несколько раз / не туда. |
| `reorder_list_test` ×1 | «Habits list renders without exception» — исключение при рендере списка. |

### Появились с новым кодом

| Тест | Симптом |
|---|---|
| `services_test` ×4 | Математика стриков (**исправлено**). Два реальных бага: (1) `_normalizeForToday()` не обнулял «мёртвые» серии при загрузке — пропуск ≥2 дней и `streak>0` без даты оставались висеть как живые (тесты ждали 0, получали 6/5); исправлено: мёртвая серия → `streak=0, lastDoneDate=null`. (2) Синглтон `HabitService` между тестами не очищался (`resetHabits` писал пустой файл, но `load()` не перетирал память) — `habits.first` указывал на привычку из прошлого теста; добавлен `debugClear()`. Снятие отметки **уменьшает стрик на 1** (минус один кружок) — это корректная семантика, совпадающая с `habit_streak_test`/`habit_first_streak_test`; ожидания в `services_test` приведены к ней. На момент снимка прогон `services_test.dart` отдельно не выполнялся; сейчас этот файл входит в зелёный прогон CI. |
| `smooth_tooltip_test` ×1 | Пузырь не доигрывает плавное исчезание при уходе с экрана (`Expected > 0.3`, `Actual 0.0`). |
| `section_pill_drag_test` ×1 | Тяга влево не уводит камень на следующий раздел. Тест новый, написан вместе с `section_pill`. |

### Что предлагалось делать (по тому снимку)

1. **Golden-тесты — закрыто.** `exit_dialog_localization_test` уже давно
   проверяет **текст** (`find.text`), а не картинку — ровно то, что советовал
   этот пункт. PNG-эталоны `test/goldens/dialog_*.png` оказались осиротевшими
   (кодом не использовались) и удалены; новых golden-сравнений в репозитории
   нет.
2. **Стрики.** Самая дорогая по смыслу поломка: `habit_service.dart` — это
   данные пользователя. Тесты в `test/habit_streak_test.dart` и
   `test/habit_first_streak_test.dart` при этом проходят, то есть логика
   разошлась в двух местах. Чинить первым.
3. **Жесты.** `sliding_picker` и `section_pill` — это «слой плавности», он
   по определению будет ломаться на границах сценариев. Разбирать вручную
   на устройстве.

## Не проверялось

- Сборка APK и установка на реальный телефон
- Работа будильников после перезагрузки
- Оверлей Ады и его foreground-сервис
- Обновление из GitHub Releases
