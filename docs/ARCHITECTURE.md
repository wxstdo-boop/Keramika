# Архитектура

Keramika — Flutter-приложение с нативным Android-слоем. Логика предметной
области и весь UI на Dart; Kotlin отвечает только за то, что Dart не умеет
надёжно: точные будильники, foreground-сервис и приём broadcast'ов.

## Общая схема

```
┌─────────────────────────────────────────────┐
│  Presentation (lib/screens, lib/widgets)    │
│  17 экранов · 47 компонентов                │
└───────────────┬─────────────────────────────┘
                │  вызовы сервисов
┌───────────────▼─────────────────────────────┐
│  Services (lib/services) — 22 штуки         │
│  данные · уведомления · ИИ · обновления     │
└───────┬───────────────────────────┬─────────┘
        │                           │
┌───────▼──────────┐      ┌─────────▼──────────┐
│ Хранилище        │      │ Внешние сервисы    │
│ JSON-файлы +     │      │ ИИ-провайдер,      │
│ SharedPreferences│      │ GitHub Releases    │
└──────────────────┘      └────────────────────┘

  Android: AlarmReceiver · AlarmForegroundService · OverlayService
```

## Слои

### 1. Модели — `lib/models/`

Простые иммутабельные классы с `toJson` / `fromJson`:

| Модель | Что описывает |
|---|---|
| `alarm.dart` | Будильник: время, дни, звук, повтор, включённость |
| `wake_task.dart` | Задание, которое нужно выполнить, чтобы выключить будильник |
| `habit.dart` | Привычка: норма в день/неделю, стрик, история |
| `task.dart` | Задача: приоритет, дедлайн, повторение |
| `reality_check.dart` | Проверка честности перед собой |
| `app_timer.dart` | Таймер фокуса |

### 2. Сервисы — `lib/services/`

Слой данных и системных интеграций. Экраны не пишут в файлы сами — только
через сервисы.

| Сервис | Ответственность |
|---|---|
| `ai_guide_service.dart` | Ада: диалог с ИИ, разбор естественного языка, undo-действия |
| `notification_service.dart` | Локальные уведомления, каналы, точные триггеры |
| `alarm_scheduler.dart` | Планирование и перепланирование срабатываний |
| `alarm_service.dart` | CRUD будильников |
| `update_service.dart` | Проверка GitHub Releases, скачивание APK, SHA-256 |
| `installer.dart` | Установка скачанного APK |
| `habit_service.dart` | CRUD привычек, стрики |
| `task_service.dart` | CRUD задач |
| `nutrition_service.dart` | Приёмы пищи, нормы, тренды |
| `reality_check_service.dart` | CRUD проверок |
| `completion_log_service.dart` | Журнал выполненного |
| `pin_service.dart` | PIN-хранение и проверка |
| `settings_service.dart` | Пользовательские настройки |
| `prefs.dart` | Единая точка инициализации `SharedPreferences` |
| `json_file.dart` | Чтение/запись JSON с fsync и защитой от лишней записи |
| `safe_save.dart` | Обёртка с откатом при неудачной записи |
| `migration.dart` | Обновление формата данных между версиями |
| `alarm_black_box.dart` | Отладочный журнал срабатываний |
| `timer_service.dart`, `screen_reader_service.dart`, `haptics.dart`, `new_year_event_service.dart` | Таймер, озвучка для скринридера, тактильный отклик, seasonal-баннер |

### 3. Экраны — `lib/screens/`

Крупнейшие: `settings_screen.dart` (171 КБ) и `lock_screen.dart` (92 КБ) —
там много состояний и анимаций. Остальные — по одной предметной области.

### 4. Виджеты — `lib/widgets/`

47 компонентов. Отдельный интерес представляет «слой плавности»:
`page_spring.dart`, `press_splat.dart`, `smooth_typing.dart`,
`rolling_counter.dart`, `smooth_tooltip.dart`, `section_pill.dart`,
`stained_glass.dart`. Это то, чем приложение отличается от обычного
Material-приложения.

### 5. Оверлей — `lib/overlay/`

`ada_overlay.dart` — окно поверх других приложений. `overlay_bridge.dart`
определяет интерфейс, `overlay_bridge_io.dart` реализует его для Android,
`overlay_bridge_web.dart` — заглушка для браузера (там оверлея нет).

## Хранение данных

Своего хранилища нет — сознательное решение: данные должны читаться глазами и
переживать переезд между устройствами.

**На Android/iOS/Desktop** — JSON-файл на каждую сущность в каталоге
документов приложения:

```
<AppDocuments>/alarms.json
<AppDocuments>/habits.json
<AppDocuments>/tasks.json
<AppDocuments>/nutrition.json
...
```

**Настройки** — в `SharedPreferences` через глобальный `globalPrefs`.

**На web** — тот же код пишет в `localStorage` через `SharedPreferences`
(ветка `kIsWeb` в `json_file.dart`), потому что `dart:io` на web недоступен.

### Особенности записи

`JsonFile.write` устроен с оглядкой на flash-память:

- автосохранение в `main()` пишет все файлы раз в 10 секунд;
- `writeAsString(flush: true)` — это fsync, на бюджетном Android это
  миллисекунды блокировки IO на каждый файл;
- перед записью сравнивается текст на диске, а не только в памяти — потому
  что isolate плавающего окошка Ады пишет часть тех же ключей из своего
  процесса, и проверка «по памяти» привела бы к потере данных;
- при ошибке запись идёт через `.tmp` с заменой поверх.

## Нативный слой — `android/app/src/main/kotlin/com/wetidom/keramika/`

| Файл | Роль |
|---|---|
| `MainActivity.kt` | Точка входа, инициализация плагинов, каналов уведомлений |
| `AlarmReceiver.kt` | `BroadcastReceiver` на срабатывание будильника и на `BOOT_COMPLETED` |
| `AlarmForegroundService.kt` | Удержание процесса, пока звонок играет |

Третий сервис — `OverlayService` из форка `flutter_overlay_window`,
объявлен с `foregroundServiceType="specialUse"`.

### Разрешения Android

Приложение просит много — и это осознанно:

```
INTERNET                              запросы к ИИ-провайдеру
SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM  будильник ровно в срок
USE_FULL_SCREEN_INTENT                будильник поверх блокировки
WAKE_LOCK                             разбудить CPU
RECEIVE_BOOT_COMPLETED                пережить перезагрузку
POST_NOTIFICATIONS                    уведомления (Android 13+)
SYSTEM_ALERT_WINDOW                    оверлей Ады
FOREGROUND_SERVICE (+ specialUse)     процесс во время звонка
REQUEST_IGNORE_BATTERY_OPTIMIZATIONS  не усыплять будильники
REQUEST_INSTALL_PACKAGES               автообновление
VIBRATE                               тактильный отклик
READ_EXTERNAL_STORAGE (maxSdk 32)     выбор файлов для экспорта
```

## Локализация

`lib/l10n/translations.dart` — один файл со словарями `en`, `ru`, `fr`
(148 КБ). Ключи лежат в одном месте, поэтому перевод нельзя рассыпать по
экранам. Рядом `locale_provider.dart` переключает язык в рантайме.

Системные диалоги (например, отказ в разрешении) переводятся отдельно —
`lib/utils/android_settings.dart`.

## Локальные форки

`third_party/` — два плагина, намеренно форкнутых. Причины описаны в
[BUILD.md](BUILD.md). Правки в форках нужно повторять при обновлении пакета.