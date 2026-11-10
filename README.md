<div align="center">
  <img src="assets/keramika.png" alt="Keramika" width="128" height="128" />

  <h1>Keramika</h1>

  <p><strong>Будильник, который не даёт уснуть обратно.</strong><br />
  Задачи, привычки, питание и ИИ-ассистент Ада — в одном приложении.</p>

  <p>
    <a href="https://github.com/wxstdo-boop/Keramika/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/wxstdo-boop/Keramika/ci.yml?label=CI&color=%232ea44f" /></a>
    <a href="https://github.com/wxstdo-boop/Keramika/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/wxstdo-boop/Keramika?label=%D1%81%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C&color=%23c2185b" /></a>
    <a href="LICENSE"><img alt="MIT" src="https://img.shields.io/badge/license-MIT-2ea44f" /></a>
    <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.47.5-02569a?logo=flutter&logoColor=white" />
    <img alt="Dart" src="https://img.shields.io/badge/Dart-3.12-0175C2?logo=dart&logoColor=white" />
    <img alt="Android" src="https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white" />
  </p>
</div>

---

## 📸 Скриншоты

> [!NOTE]
> Галерея собрана из реальных экранов с демо-данными (без личных записей).
> Снимки воспроизводимы: `flutter test tool/screenshots/render_screenshots.dart`
> кладёт PNG в [`docs/screenshots/`](docs/screenshots/).

<div align="center">
  <table>
    <tr>
      <td width="50%"><img src="docs/screenshots/alarms.png" width="260" alt="Будильники" /></td>
      <td width="50%"><img src="docs/screenshots/habits.png" width="260" alt="Привычки со стриками" /></td>
    </tr>
    <tr>
      <td align="center"><sub>Будильники</sub></td>
      <td align="center"><sub>Привычки со стриками</sub></td>
    </tr>
    <tr>
      <td width="50%"><img src="docs/screenshots/tasks.png" width="260" alt="Задачи" /></td>
      <td width="50%"><img src="docs/screenshots/stats.png" width="260" alt="Статистика" /></td>
    </tr>
    <tr>
      <td align="center"><sub>Задачи с приоритетами</sub></td>
      <td align="center"><sub>Статистика РП</sub></td>
    </tr>
  </table>
</div>

---

## ✨ Что умеет

### ⏰ Будильники
- Точное срабатывание: `SCHEDULE_EXACT_ALARM` + `USE_EXACT_ALARM`, foreground-сервис
  держит процесс живым, `WAKE_LOCK` будит CPU
- **Wake-task** — к каждому будильнику можно привязать задание, которое надо
  выполнить, чтобы выключить звонок
- Переживает перезагрузку телефона (`RECEIVE_BOOT_COMPLETED` + ресивер
  перепланировывает всё заново)
- Полноэкранный интент, чтобы будильник вылез поверх блокировки
- Пять мелодий: classic, default, digital, gentle, nature

### ✅ Задачи и привычки
- Задачи с приоритетом, дедлайном и повторением
- Привычки со стриками, дневными и суммарными нормами
- **Reality checks** — честная проверка «а не врёшь ли ты себе»
- Свайп-по-жесту для удаления, перетаскивание, отложенные анимации

### 🍎 Питание
- Приёмы пищи, нормы по БЖУ, тренды за 30 дней
- Кольцевой прогресс по каждой норме

### 🔒 Приватность
- PIN-защита и экран блокировки приложения
- Экспорт своих данных одним файлом

### 🤖 Ада — ИИ-ассистент
Ада живёт прямо в приложении и понимает обычную речь:

> «поставь будильник на 7 утра на рабочие»
> «завтра в 18:30 напомни купить молоко»
> «посчитай сколько я съел»

- Создаёт, меняет и удаляет будильники, задачи, привычки, проверки и приёмы пищи
- **Умеет отменять**: «Отменить» откатывает последнее действие («Привычка X удалена»)
- Работает в **окошке поверх других приложений** — можно говорить с Адой, не
  открывая приложение
- Несколько провайдеров на выбор (OpenRouter, Kilo, OVHcloud, Agnes и другие),
  ключ хранится только на устройстве
- Аккуратно переживает ошибки сети и 4xx от провайдера

### 🛠 Система
- **Автообновление** прямо из приложения: проверяет GitHub Releases, спрашивает
  подтверждение, сверяет SHA-256 и ставит APK поверх старого — данные (PIN,
  будильники) сохраняются. Установку выполняет ОБЫЧНЫЙ системный установщик
  (`Intent.ACTION_VIEW` через FileProvider): система сама показывает свой экран
  «Установить обновление?» с проверкой Play Protect, а пользователь
  подтверждает. Сессию `PackageInstaller`, объявление себя владельцем обновлений
  (`ENFORCE_UPDATE_OWNERSHIP`) и тихий путь без подтверждения
  (`UPDATE_PACKAGES_WITHOUT_USER_ACTION`) мы сознательно НЕ используем: этот
  набор Play Protect помечает как поведение вредоносного ПО и блокирует
  установку
- **«Что нового»** тянется из живых релизов, а не из зашитого списка: экран
  никогда не отстаёт от установленной версии
- Material You: цвета тянутся из системной темы, есть тёмная тема
- Плавные анимации: пружинные переходы, инерционный ввод, мягкие тултипы
- Тумблеры **вибрации** и **«убрать анимации»**: декоративные петли гаснут,
  система «упростить движение» уважается всегда
- Локализация: **русский / English / Français**

---

## 🚀 Установка

### Готовый APK
1. Открой [Releases](https://github.com/wxstdo-boop/Keramika/releases/latest)
2. Скачай `Keramika-<версия>-<abi>.apk` под свой процессор
   (`arm64-v8a` — почти все современные телефоны, `armeabi-v7a` — старые,
   `x86_64` — эмуляторы)
3. Разреши установку из этого источника, если попросит
4. При обновлении данные не пропадут — APK ставится поверх старого

> Требуется Android 8.0 (API 26) или новее.

> **Play Protect может предупредить об установке.** APK распространяется не
> через Google Play, поэтому система иногда показывает «требуется проверка»
> или «вредоносное приложение». Это не означает, что в приложении есть
> что-то плохое — так Play Protect ведёт себя с любым сайдлоадом. Нажми
> «Всё равно установить», а если система заблокировала установку — открой
> Настройки → Безопасность (Play Protect) и разреши установку для Keramika:
> в приложении есть кнопка, ведущая прямо туда.

### Автообновление через Obtainium

[Obtainium](https://github.com/ImranR98/Obtainium) следит за GitHub Releases и
сам предлагает обновления, сверяя APK по SHA-256. Добавь в приложении ссылку:

```
https://github.com/wxstdo-boop/Keramika
```

Obtainium подхватит нужный ABI и будет ставить новые версии поверх — данные
(PIN, будильники, задачи) сохранятся.

### F-Droid

Приложение готовится к публикации в F-Droid. После приёма его можно будет
установить из любого F-Droid-клиента (Neo Store, Droid-ify и др.). Сборка для
F-Droid собирается из исходников без встроенного автообновления — обновления
приходят через F-Droid.

Готовый рецепт сборки и инструкция по подаче — в
[docs/publishing-fdroid.md](docs/publishing-fdroid.md).

### Из исходников

```bash
git clone https://github.com/wxstdo-boop/Keramika.git
cd Keramika
flutter pub get
flutter run
```

Подробности, требования к SDK и решение проблем — в [docs/BUILD.md](docs/BUILD.md).

---

## 🏗 Архитектура

Проект — обычное Flutter-приложение, Android-first: надёжные будильники
обеспечивает нативный код на Kotlin.

```
lib/
├── main.dart          Точка входа, навигация, startup, автосохранение
├── l10n/              Переводы (ru/en/fr) и провайдер локали
├── models/            Alarm, Habit, Task, RealityCheck, AppTimer, WakeTask
├── screens/           24 экрана: разделы и их компоненты
├── services/          29 сервисов: данные, уведомления, ИИ, обновления
├── overlay/           Оверлей Ады + мост (io / web)
├── theme/             Единый построитель темы (app_theme.dart)
├── utils/             Иконки, анимации, токены дизайна, «убрать анимации»
└── widgets/           56 UI-компонентов

android/app/src/main/kotlin/com/wetidom/keramika/
├── MainActivity.kt             Точка входа Android, каналы плагинов
├── AlarmSchedulerPlugin.kt     Планирование setAlarmClock, догон, манифест
├── AlarmReceiver.kt            Приём срабатывания будильника
├── AlarmForegroundService.kt   Удержание процесса во время звонка
├── BootReceiver.kt             Перепланировка будильников после перезагрузки
├── ScreenReaderService.kt      Доступность: чтение экрана
└── AlarmLog.kt                 Чёрный ящик срабатываний (для диагностики)

third_party/
├── flutter_overlay_window/      Форк: регистрирует плагины в оверлее Ады
└── flutter_keyboard_visibility/ Форк: поднят compileSdk до 36
```

Подробный разбор — в [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

### Токены дизайна
Геометрия, отступы, длительности и начертания живут в одном файле —
`lib/utils/design_tokens.dart`. Тема (`lib/theme/app_theme.dart`) собирается
из этих шкал, поэтому «ещё один магический радиус» не появляется незаметно.

### Хранение данных
Без базы данных и без облака. Каждая сущность лежит отдельным JSON-файлом в
каталоге документов приложения, настройки — в `SharedPreferences`. На вебе тот же
код пишет в `localStorage`. Запись идёт через `flush: true` (fsync), с
проверкой «на диске уже ровно этот текст», чтобы не мучить flash-память
fsync-ом каждые 10 секунд. На web `dart:io` недоступен, поэтому
`lib/utils/` и `lib/services/` умеют работать через `kIsWeb`.

### Стек
| Слой | Что используется |
|---|---|
| UI | Flutter 3.47.5, Material 3, `dynamic_color` для Material You |
| Состояние | `ChangeNotifier` + `ValueNotifier`, без внешних пакетов |
| Хранилище | JSON-файлы + `shared_preferences` |
| Уведомления | `flutter_local_notifications`, `timezone` |
| Оверлей | форк `flutter_overlay_window` |
| ИИ | `http` к выбранному провайдеру, `uuid` для идентификаторов диалогов |
| Локальные форки | `flutter_overlay_window`, `flutter_keyboard_visibility` |

---

## 🧪 Тесты

```bash
flutter test --concurrency=1
```

42 тестовых файла, 245 тестов: стрики привычек, анимации чипов и тултипов,
счётчик, слайдер-пикер, логика ворк-леда, локализация диалогов, смоук-тест.

> По состоянию на 2026-11-08 в CI (Flutter 3.47.5, как в `.github/workflows/ci.yml`)
> `flutter analyze` чистый, `flutter test` — 245 тестов, 3 пропущено (ручные,
> требуют сети), падений нет. Подробности — в разделе
> [Состояние тестов](docs/TESTS.md).

---

## 🚢 Релизы

Релизы собирает GitHub Actions по тегу вида `v1.6.49+45121`
(тот же формат, что в `pubspec.yaml`). Workflow восстанавливает keystore из
секретов, собирает `--split-per-abi`, переименовывает ассеты в
`Keramika-<версия>-<abi>.apk` и публикует в Releases.

```bash
git tag v1.6.49+45121
git push --tags
```

> ⚠️ **`versionCode` должен быть строго выше установленного на телефоне.**
> Flutter прибавляет к номеру из `pubspec.yaml` индекс ABI: `armeabi-v7a` +1000,
> `arm64-v8a` +2000, `x86_64` +3000. Иначе `adb install -r` падает с
> `INSTALL_FAILED_VERSION_DOWNGRADE`.

Разбор процесса — в [docs/RELEASE.md](docs/RELEASE.md).

---

## 🤝 Участие

Приветствуются баги, идеи и PR. Перед правкой прочитайте
[CONTRIBUTING.md](CONTRIBUTING.md) — там договорённости по стилю, локализации и
тому, как не сломать сборку.

---

## 📄 Лицензия

MIT — см. [LICENSE](LICENSE).

Приложение бесплатное и открытое. Свои данные никуда не отправляются, кроме
запросов к ИИ-провайдеру, которого ты сам выбрал в настройках.

---

## 💜 Благодарности

- Flutter и команде Dart
- Всем, кто присылал баги и идеи по Аде