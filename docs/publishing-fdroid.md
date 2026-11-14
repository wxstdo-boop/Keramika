# Публикация Agysha в каталогах приложений

Документ описывает, что уже готово в репозитории, куда подавать приложение и в
каком порядке. Цель — попасть в F-Droid (и через него в Neo Store и другие
клиенты), а затем расширять охват.

## Что уже готово в репозитории

| Артефакт | Зачем |
|---|---|
| `fdroid/metadata/com.wetcorp.agysha.yml` | Готовый рецепт сборки для fdroiddata — копируется в MR как есть |
| `fastlane/metadata/android/{en-US,ru,fr}/` | Иконка, скриншоты, короткое и полное описание, changelog — в формате, который читает и F-Droid, и IzzyOnDroid |
| `docs/screenshots/` + `tool/screenshots/render_screenshots.dart` | Скриншоты рисуются из кода без устройства |
| `lib/services/update_service.dart` | Флаг `AGYSHA_NO_SELF_UPDATE` выключает самообновление в сборке для F-Droid (см. ниже) |

## Почему самообновление нужно выключать в F-Droid-сборке

F-Droid и IzzyOnDroid запрещают приложения, которые скачивают и устанавливают
исполняемые файлы без явного согласия пользователя. У Agysha есть встроенное
обновление с GitHub Releases. Поэтому рецепт собирает APK с
`--dart-define=AGYSHA_NO_SELF_UPDATE=true`: в этой сборке `kSelfUpdateEnabled`
равен `false`, поэтому не показывается таблетка обновления в Настройках и не
запускается тихая ежедневная проверка релизов (`silentDailyCheck` в `main.dart`).
Обновления приходят через сам F-Droid.

Локально/в своих релизах (GitHub, CI) флаг не задаётся, и самообновление
работает как раньше.

## F-Droid — первый и главный шаг

F-Droid собирает приложение из исходников сам и подписывает своим ключом. Это
снимает две проблемы сразу: не нужен приватный keystore и не нужна своя
инфраструктура раздачи. Плюс приложения F-Droid автоматически появляются в
Neo Store, Droid-ify и других клиентах F-Droid.

### Порядок подачи

Коротко: «в два клика» F-Droid не работает — приложение собирается из исходников
на стороне F-Droid, и рецепт должен быть в их репозитории. Но и «с нуля писать
рецепт» не нужно: файл уже готов, остаётся скопировать и открыть MR. Ниже —
точные команды.

1. Форк `https://gitlab.com/fdroid/fdroiddata` (кнопка Fork) и клон форка.
   Форк нужен именно от личного аккаунта: проектный токен-бот (`project_…_bot_…`)
   форк создать не может, поэтому шаг делается вручную в веб-интерфейсе.
2. Скопировать рецепт и прогнать проверки:
   ```
   pip install fdroidserver
   git clone https://gitlab.com/<ваш-логин>/fdroiddata && cd fdroiddata
   cp /path/to/Agysha/fdroid/metadata/com.wetcorp.agysha.yml metadata/
   fdroid readmeta
   fdroid checkupdates com.wetcorp.agysha
   fdroid build -v -l com.wetcorp.agysha
   ```
   `fdroid build` требует Android SDK и NDK 28.2.13676358 (см. поле `ndk` в
   рецепте) и около 30-60 минут на первый прогон.
3. Закоммитить и открыть MR прямо из веб-интерфейса GitLab (после push появится
   ссылка «Create merge request»). Заголовок: `New app: com.wetcorp.agysha`.
4. Отвечать на замечания ревьюеров — обычно просят уточнить, где хранятся
   ключи подписи и почему в рецепте такие `rm`/`prebuild`.

#### Проверено локально (на этот рецепт)

Рецепт уже прогнан через настоящий пайплайн F-Droid, повторять шаг 2 не
обязательно:

- `fdroid readmeta` — рецепт читается, `proper_format=True` (нулевой diff
  `fdroid rewritemeta`), CI-гейт формата проходит.
- `fdroid checkupdates com.wetcorp.agysha` — расхождения версии нет: `commit:`
  совпадает с тегом `v1.6.170+45242`, `versionName`/`versionCode` совпадают с
  `pubspec.yaml`.
- `fdroid lint com.wetcorp.agysha` — замечаний нет.
- Полная сборка по шагам рецепта (Flutter 3.47.5, NDK 28.2.13676358,
  `flutter pub get --enforce-lockfile`, `flutter build apk --release
  --dart-define=AGYSHA_NO_SELF_UPDATE=true`) — успешно, unsigned APK ~70 МБ
  (arm64-v8a + armeabi-v7a + x86_64), `versionCode=45242`.
- `REQUEST_INSTALL_PACKAGES` и `ENFORCE_UPDATE_OWNERSHIP` из манифеста
  вырезаются `prebuild`-шагами; проверено по `aapt2 dump badging`.

#### Грабли: `android/key.properties` и подпись

`android/key.properties` в `.gitignore` и в тег не попадает. Строка
`storeFile = file(keystoreProperties.getProperty("storeFile", ""))` в
`android/app/build.gradle.kts` при пустом значении падает с
`Cannot convert '' to File` — на чистом клоне `flutter build apk` без
дополнительных шагов ломается. F-Droid это лечит сам: перед сборкой он вызывает
`remove_signing_keys()`, который вырезает блок `signingConfigs { … }` и строку
`signingConfig = …`. Поэтому в рецепте **не нужно** ничего дописывать под
подпись; проверено, что после `remove_signing_keys` сборка проходит.


### Что ревьюеры почти наверняка спросят

- **Почему `NonFreeNet`?** Указан в рецепте честно: встроенная ИИ-помощница Ада
  ходит к сторонним бесплатным провайдерам моделей (OpenRouter, Poolside и др.).
  Остальное приложение работает офлайн. Это допустимо для F-Droid как
  Anti-Feature (предупреждение), но не блокирует включение.
- **`REQUEST_INSTALL_PACKAGES`** — разрешение на установку APK. В F-Droid-сборке
  самообновление выключено, поэтому разрешение не используется по назначению.
  Можно предложить ревьюеру удалить его в рецепте (`sed -i '/REQUEST_INSTALL_PACKAGES/d'
  android/app/src/main/AndroidManifest.xml`), если это будет замечанием.
  Вместе с ним в F-Droid-сборке не нужно и `ENFORCE_UPDATE_OWNERSHIP`
  (объявление себя владельцем обновлений) — оба относятся только к
  самообновлению: вырезать оба —
  `sed -i -e '/REQUEST_INSTALL_PACKAGES/d' -e '/ENFORCE_UPDATE_OWNERSHIP/d'
  android/app/src/main/AndroidManifest.xml`. В рецепте оставлена и строка
  `/UPDATE_PACKAGES_WITHOUT_USER_ACTION/d`: сейчас такого разрешения в
  манифесте нет (его убрали — это был триггер Play Protect), но `sed` без
  совпадений безвреден, а для старых коммитов, где разрешение ещё есть, он
  нужен.
- **`third_party/`** — два локальных форка плагинов лежат прямо в репозитории
  (не git-submodules). F-Droid это устраивает: код доступен, собирается из
  исходников.

## IzzyOnDroid — подача закрыта их ИИ-политикой

IzzyOnDroid раздаёт бинарники разработчика (собирает не он), поэтому с точки
зрения техники подача проще, чем в F-Droid: issue со ссылкой на APK-релиз.

Но политика включения (App Inclusion Policy, раздел «AI policy») прямо
говорит: «Apps acting as front-end for LLMs… or integrate with such services,
will be rejected» и «Vibe-coded apps will be rejected». Формулировка жёсткая и
без исключений для необязательных функций — решение принимает человек, но по
букве политики Agysha с Адой под неё попадает. Отсюда практический вывод:
подача туда **сейчас бессмысленна** и может лишь создать отказ, который потом
будет сложнее переиграть.

Реальные варианты, если IzzyOnDroid нужен:

1. **Не подавать.** Идти только в F-Droid — это и есть основной канал
   (Neo Store, Droid-ify, Aurora Droid тянут из F-Droid автоматически).
2. **Отдельная сборка без Ады.** Убрать раздел «Ада», `FreePoolForgeChat`,
   `REQUEST_INSTALL_PACKAGES` и самообновление — product flavor `izzy`, собрать
   отдельный APK и приложить его к релизу. Только тогда имеет смысл подавать:
   политика про интеграцию с LLM перестаёт применяться. Это заметная доработка
   (несколько экранов и сервисов), начинать с неё не стоит.
3. **Спросить напрямую.** Контакт — https://izzyondroid.org/contact/. Описать,
   что Ада необязательна, а остальное работает офлайн, и спросить, примут ли.
   Готовиться к отказу.

Подача, когда/если решитесь: issue в
`https://codeberg.org/IzzyOnDroid/repodata/issues` (трекер переехал с GitLab на
Codeberg) со ссылкой на APK-релиз. Лимит на APK — 30 МБ (наши arm64/arm32
проходят, x86_64 тоже).

## Что даёт попадание в F-Droid

- Автоматически — Neo Store, Droid-ify, Aurora Droid и другие F-Droid-клиенты.
- Поиск по `https://f-droid.org` и в клиентах.
- Бейдж «Get it on F-Droid» для README.
- Никакой возни с подписью и хостингом: F-Droid собирает и раздаёт сам.

## Дополнительные площадки (после F-Droid)

| Площадка | Как попасть |
|---|---|
| Obtainium | Ничего подавать не нужно: пользователи добавляют ссылку на GitHub Releases сами. Стоит указать это в README как способ установки |
| GitHub | Уже есть: Releases + topics (`foss`, `android`, `flutter`, `privacy`). Добавить бейдж F-Droid в README, когда приложение появится |
| Awesome-списки | PR в `awesome-fdroid`, `awesome-flutter`, `awesome-selfhosted` (если применимо) — ищут по теме |
| Reddit | r/fossdroid, r/AndroidQuestions, r/FlutterDev — пост-анонс с честным описанием |
| Hacker News / Lobsters | Пост «Show HN» про FOSS-будильник с Адой |
| Product Hunt | Анонс, если нужен более широкий, но не FOSS-ориентированный охват |

### Готовая заявка в `albertomosconi/foss-apps`

Этот список (≈1.2k звёзд) принимает любые FOSS-приложения без порога по
звёздам, а в его категории Productivity уже стоят Loop Habit Tracker и
Tasks.org — Agysha там на месте. Редактируется ровно один файл `apps.json`,
записи в категории идут по алфавиту.

Готовая запись для категории `productivity` (вставить по алфавиту, между
«GitJournal» и «Loop Habit Tracker»):

```json
{
    "host": "GitHub",
    "name": "Agysha",
    "description": "An offline alarm clock that will not let you fall back asleep, plus habit tracking, tasks and focus sessions in one app. Includes an optional AI assistant, disabled by default. No account, no ads, no trackers; everything works offline.",
    "stars_link": "https://img.shields.io/github/stars/wxstdo-boop/agysha.svg?label=★&style=flat",
    "source": "https://github.com/wxstdo-boop/agysha",
    "fdroid": "https://f-droid.org/packages/com.wetcorp.agysha"
}
```

Поля `playstore`/`website` удалены (их нет). Поле `fdroid` станет рабочим
после приёма в F-Droid; если подаёте в `foss-apps` раньше — удалите и его.

Шаги: форк `https://github.com/albertomosconi/foss-apps`, ветка `Agysha`,
правка `apps/productivity.json`, коммит `app: add Agysha in Productivity`,
PR в `main` по их шаблону.

> Почему не `awesome-flutter`: их правила требуют минимум 35 звёзд у проекта.
> Пока звёзд меньше, заявка нарушает правила и будет закрыта — это не «пиар»,
> а шум в чужом трекере.


## Чек-лист перед подачей

- [x] Релиз на GitHub собран и подписан, тег вида `vX.Y.Z+NNNNN` проставлен
      (последний — `v1.6.170+45242`).
- [x] `version` в `pubspec.yaml` на `main` совпадает с последним релизом.
- [x] `fastlane/metadata/android/{en-US,ru,fr}/` заполнены: title, short/full
      description, icon, phoneScreenshots, changelog с номером текущего
      `versionCode`.
- [x] `short_description.txt` — не длиннее 80 символов и **без точки в конце**
      (F-Droid это проверяет, ревьюеры Izzy ловят первым делом).
- [x] `changelogs/<versionCode>.txt` — не длиннее 500 символов.
- [x] В репозитории есть LICENSE (MIT — есть), README с описанием.
- [x] Коммит в рецепте (`commit:`) указывает на тот же код, что и релиз, и
      содержит `fastlane/` (F-Droid читает метаданные из этого коммита).
- [x] `fdroid build` локально проходит (см. «Проверено локально»).
- [x] Самообновление в F-Droid-сборке выключено (`AGYSHA_NO_SELF_UPDATE`).
- [x] RFP-заявка в `fdroid/rfp` открыта: issue #4794.
- [x] MR в `fdroiddata` открыт: fdroiddata!57343 (личный токен `wxstdo`).

### Важная зависимость порядка

`fastlane/` и флаг `AGYSHA_NO_SELF_UPDATE` живут в коде на `main`, а рецепт
обязан указывать `commit:` на коммит, где они уже есть. Поэтому порядок такой:

1. Сначала релиз, который содержит `fastlane/` и флаг (любой пуш в `main`).
2. Потом в рецепте обновить `commit:`, `versionName`, `versionCode`,
   `CurrentVersion`, `CurrentVersionCode` на этот тег.
3. И только затем MR в `fdroiddata`.

Сейчас рецепт смотрит на последний релиз, и расхождения нет. После каждого
нового релиза шаг 2 повторять, иначе CI-гейт `fdroid checkupdates --auto`
упадёт на diff.

> Грабли, которые уже ловились: `commit:` указывал на релизный коммит, а
> changelog версии туда не попадал — тег ложится на коммит `release: v…`,
> который трогал только `pubspec.yaml` и `app_version.dart`, поэтому в теге
> не было `fastlane/.../changelogs/<versionCode>.txt` и «Что нового» было
> пустым. Теперь `ship.yml` генерирует этот файл и коммитит его ВМЕСТЕ с
> бампом, так что у любого свежего тега changelog на месте. Рецепт всё равно
> нужно переставлять на новый тег вручную (шаг 2) — автосинхронизации нет.


## Готовый пакет подачи (осталось только отправить)

Всё, что нужно F-Droid, уже лежит в репозитории и проверено.

> **Статус подачи (обновлено):** оба шага сделаны.
> * RFP-заявка: **https://gitlab.com/fdroid/rfp/-/issues/4794** (`opened`).
> * Merge request: **https://gitlab.com/fdroid/fdroiddata/-/merge_requests/57343**
>   — заголовок `New app: Agysha`, ветка `com.wetcorp.agysha` форка
>   `wxstdo/fdroiddata`, ровно один файл `metadata/com.wetcorp.agysha.yml`.
>   MR `mergeable`, кросс-ссылка на rfp#4794 подставлена (`Closes rfp#4794`).
>
> Пайплайны в **форке** падают без джобов (`yaml_errors: null`, но раннеры
> форка не запускают `merge_request_event` для целевого проекта) — это
> нормально, CI гоняет F-Droid на своей стороне. Метку `New App` из-под
> непривилегированного аккаунта поставить нельзя (`PUT` возвращает 200, но
> метки не меняются) — её ставит мейнтейнер.
>
> Токен, которым это делалось, должен быть **личным** (`wxstdo`). Проектный
> бот (`project_…_bot_…`) умеет только открывать issue в `fdroid/rfp`; форк и
> MR ему недоступны (`409 Namespace is not valid` на форк, `403` на MR).

### Вариант A (рекомендуется для первого раза) — RFP-issue

**Подано:** https://gitlab.com/fdroid/rfp/-/issues/4794 — заголовок
`Agysha (com.wetcorp.agysha) — offline alarm clock with tasks, habits and nutrition`.
Заявка заполнена по шаблону RFP (все галочки, кроме доната), в неё вложены
application ID, готовый `metadata`-YAML, summary/description из fastlane и
заметки по сборке (Flutter, NDK, выключенное самообновление, `NonFreeNet`).

Если нужно переоткрыть заявку вручную (например, с другого аккаунта):
https://gitlab.com/fdroid/rfp/-/issues/new?issue%5Btitle%5D=Agysha%20(com.wetcorp.agysha)

**Title:** `Agysha (com.wetcorp.agysha)`

**Description:** (текст, который был отправлен, — в
`fdroid/rfp-issue-body.md` репозитория; он же дублирует содержимое варианта B
ниже).

### Вариант B — сразу merge request

Форк https://gitlab.com/fdroid/fdroiddata, ветка `com.wetcorp.agysha`,
скопировать рецепт в `metadata/com.wetcorp.agysha.yml`, закоммитить и открыть
MR по шаблону (шаблон обязателен — ревьюеры просят его заполнять).

**Title:** `New app: com.wetcorp.agysha`

**MR description:** тот же текст, что в варианте A.

### Что спросят ревьюеры (заготовленные ответы)

- **Почему `NonFreeNet`?** Ада — необязательная ИИ-помощница, ходит к
  сторонним бесплатным провайдерам (OpenRouter, Poolside). Приложение работает
  офлайн, антифича указана честно. Не блокирует включение.
- **`REQUEST_INSTALL_PACKAGES`?** В F-Droid-сборке самообновление выключено,
  разрешение вырезается в prebuild — оно не используется.
- **`third_party/`?** Два форка плагинов лежат в репозитории обычными файлами
  (не submodules), собираются из исходников — F-Droid это устраивает.

## Продвижение: что реально работает

Скачивания приходят не от «распиара» как такового, а от попадания в каталоги,
откуда люди ставят приложения:

1. **F-Droid** — главный источник. Приложения ищут внутри клиента, не в поиске.
2. **Понятное описание и скриншоты** — конверсия страницы в установку зависит
   от них сильнее всего. Первая строка описания должна объяснять, чем
   приложение полезно, без жаргона.
3. **Русскоязычные сообщества** (4pda, Telegram-каналы про FOSS/Android) — для
   русской аудитории это даёт больше, чем англоязычные посты.
4. **Регулярные обновления** — F-Droid показывает свежие версии выше; частота
   обновлений напрямую влияет на видимость.

## Следующие шаги (кратко)

1. Убедиться, что на `main` версия и метаданные синхронны с релизом.
2. Скопировать `fdroid/metadata/com.wetcorp.agysha.yml` в форк `fdroiddata`.
3. Прогнать `fdroid build` локально, исправить ошибки. — **уже сделано**
   (см. «Проверено локально»): сборка воспроизведена, APK получен.
4. Открыть MR в `fdroiddata` (или RFP-issue, вариант A).
5. После приёма — добавить бейдж F-Droid в README и анонсировать.
6. Решить, нужна ли отдельная сборка без Ады для IzzyOnDroid.
