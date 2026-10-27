Build recipe: run
`Remove-Item Env:KERAMIKA_NO_R8 -ErrorAction SilentlyContinue; & 'C:\Users\Larafut\dev\flutter\bin\flutter.bat' build apk --release --split-per-abi --target-platform android-arm64`
then install over the existing Android device (keep user data):
`& "$env:USERPROFILE\dev\android-sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"`.
flutter/adb are not on PATH on this machine: flutter lives at `C:\Users\Larafut\dev\flutter\bin\flutter.bat`, adb at `C:\Users\Larafut\dev\android-sdk\platform-tools\adb.exe` (see `android/local.properties`).

## CI (GitHub Actions): грабли, на которые уже наступали

Релизы собирает `.github/workflows/ship.yml` (push в `main`) и `release.yml`
(по тегу `v*`). Оба падали по двум независимым причинам — не повторяй:

1. **Память Gradle.** `android/gradle.properties` подогнан под домашнюю
   машину (~8 ГБ RAM): `-Xmx1024m`, `workers.max=1`. На раннере этого мало —
   `assembleRelease` умирает с `the JVM garbage collector is thrashing`.
   Лечится шагом «Настройки Gradle для CI»: поднимает heap до `-Xmx4g`
   **только в CI**, локальные настройки не трогает.
2. **Пустые секреты подписи.** Если `KEYSTORE_BASE64` / `STORE_PASSWORD` /
   `KEY_PASSWORD` / `KEY_ALIAS` не заданы, падает
   `KeytoolException: Failed to read key  from store ".../keystore.jks":
   Tag number over 30 is not supported` на `:app:packageRelease`. Обрати
   внимание на пустое имя ключа — это признак пустого файла, а не битого
   keystore. Шаг «Распаковать keystore» теперь проверяет вход и падает сразу
   с внятным `::error::`.

Секреты не заданы — сборка не подпишется, релиз не выйдет, автообновление в
приложении (`lib/services/update_service.dart` читает `releases/latest`) не
сработает. Проверить, что релиз реально есть:
`curl -s .../repos/wxstdo-boop/Keramika/releases/latest` (пустой тег-лист =
релизов нет).

Keystore проекта: `keramika-release.jks`, alias `keramika`, сертификат
`CN=Keramika` (PKCS12, несмотря на расширение `.jks`). В рабочем дереве его
нет — он в `.gitignore` и должен лежать только локально у владельца и в
секретах репозитория.

Отпечаток для сверки подписи (должен совпасть у собранного APK):
`4B:48:38:78:6F:5D:00:29:75:F4:51:B2:C9:6B:62:91:5D:74:1D:49:0D:24:F3:D6:9F:3A:0A:F0:45:4E:12:1D`
(CN=Keramika, действует до 2053-12-13).

### Релизная цепочка: кто кого страхует

Сборка одна — `release.yml` (reusable). Её зовут три входа: `ship.yml`
(push в main), `release-on-tag.yml` (тег `v*`) и `release-watchdog.yml`
(догон пропущенного релиза). Внутри `release.yml` уже стоит
`timeout-minutes: 35` на job и до трёх попыток `flutter build apk`: раньше
зависший Gradle держал прогон ~3 часа, и релиз просто не выходил.

`release-watchdog.yml` раз в 30 минут сравнивает `version` из `pubspec.yaml`
на main с `releases/latest` и при разрыве зовёт `release.yml` с версией из
main. Грабли, на которых он уже стоял мёртвым (не повторять):

- подсчёт активных прогонов через `grep -cE 'ship|release'` считал сам
  watchdog: его имя `release-watchdog` содержит `release`, поэтому
  «активный прогон» находился всегда и цикл заканчивался выходом. Теперь
  имена сравниваются точно (`^(ship|release|release-on-tag)$`), а свой
  `run_id` исключается;
- запросы к `api.github.com` шли без токена. На общих IP раннеров лимит
  60/час выбирается мгновенно, `releases/latest` отдавал ошибку, версия
  последнего релиза считалась нулевой → попытка опубликовать уже вышедший
  релиз. Теперь запросы авторизованы, а любая ошибка API = «пропустить
  цикл», а не «публиковать»;
- job `publish` брал значения как `needs.check.missing` / `needs.check.name`.
  Такого пути не существует (нужно `needs.check.outputs.missing`), выражение
  молча даёт null, условие всегда false — job не запускался никогда, даже
  когда check решал «релиза нет».

Та же болезнь была в `release-on-tag.yml`: job `release` не объявлял
`outputs:`, поэтому в `publish` уезжали пустые `version_name` /
`version_code` и релиз по тегу собирался с версией «+». Проверять оба файла
стоит `actionlint` — он ловит именно эти «undefined property» без запуска:

```
actionlint .github/workflows/
```

`release-alert.yml` закрывает «никто не знает, что релиз не вышел»: на
`workflow_run` от ship / release / release-on-tag с провалом открывает
issue «Релиз не вышел — автоалерт» (и дополняет его ссылками на новые
прогоны), на первом успехе — закрывает. Секретов не требует, работает на
штатном `GITHUB_TOKEN` с `issues: write`.

Побочный эффект, который стоит помнить: **force-push в main тоже запускает
ship** (paths-фильтр видит изменённые файлы во всей переписанной истории) и
выпускает релиз с бампом версии, даже если код не менялся. После переписи
истории так и вышло — v1.6.79+45151 собралась «на пустом месте». Force-push
в main — это всегда релиз.

### Диагностика подписи без локального keytool

Локально нет Java/keytool — использовать `openssl` и Python `cryptography`.
Быстрая проверка, что залитый keystore и пароли верны (секреты читаются из
env, значения не печатать — только длины и sha256):

```bash
printf '%s' "$KEYSTORE_BASE64" | base64 -d > /tmp/ks.jks
openssl pkcs12 -in /tmp/ks.jks -passin "pass:$STORE_PASSWORD" -nokeys -legacy
```

Подпись готового APK (v2-схема, `META-INF` пуст) проверяется так:
`python3 -c` скан DER-сертификатов в хвосте APK через
`openssl x509 -inform DER -fingerprint -sha256`. Сравнить с отпечатком выше.

Грабли, уже пойманные на живых прогонах:

- `SP length : 13` вместо 12 → в секрете `STORE_PASSWORD` оказался лишний
  символ (например, подчёркивание). Секреты **не** тримятся и не
  нормализуются: вставлять ровно то, что задано;
- `keystore password was incorrect` при верном keystore = опечатка в
  `STORE_PASSWORD`; `Failed to read key *** from store` при непустом alias =
  опечатка в `STORE_PASSWORD`/`KEY_PASSWORD`;
- пароль не хранить в репозитории и не подбирать по хешу из документации:
  значения живут только в секретах GitHub и локально у владельца.

### Секреты подписи в истории

**История переписана 2026-10-27.** `android/key.properties` и
`android/app/keramika-release.jks` вычищены из всех коммитов, ветвей и тегов
(`git-filter-repo --invert-paths`, 16 ветвей + 18 тегов force-push). Проверка
после переписи: `git log --all -- <пути>` пуст, `git rev-list --all --objects`
не содержит этих путей, старые SHA (`8925a78` и соседние) с GitHub больше не
фетчатся. Локальные теги и remote-tracking ветки перетянуты на новые SHA,
reflog прочищен, `gc --prune=now` собран.

**Ключ при этом НЕ заменён — решение владельца от 2026-10-27: риск принят.**
Это значит: кто успел склонировать/скачать историю до переписи, у того ключ
остался, и он по-прежнему подписывает релизы (отпечаток выше). Перепись
закрывает доступ для новых клонов, но не отзывает ключ. Если решение
пересмотрят — `scripts\rotate-keystore.ps1`, цена описана в его шапке.

Ничего из этого не класть в рабочее дерево и в документацию: ни пароли,
ни base64 keystore, ни путь его достать из истории.

Проверено на релизе `v1.6.63+45135`: сертификат APK из `releases/latest`
совпадает с отпечатком выше, то есть ключ подписи действительно тот же,
что утёк. Обновление поверх установленного приложения проходит.

Что осталось на потом (сделать руками, когда дойдут руки):

- попросить поддержку GitHub вычистить кэш старых объектов по SHA
  (Settings -> Support). После переписи старые коммиты уже не фетчатся,
  но внутренний кэш GitHub может отдавать их по прямой ссылке;
- все, у кого был клон или форк, должны переклонировать: их `push` без
  `--force` вернёт вычищенные объекты обратно;
- открытые PR после force-push стали «висеть» на несуществующих базовых
  коммитах — dependabot пересоздаст свои, остальные закрыть руками.

Инструменты (оба безопасны по умолчанию, ничего не коммитят и не пушат):

- `scripts\rotate-keystore.ps1` — выпускает новый keystore (PKCS12, RSA 4096),
  кладёт старый в резерв вне репозитория, пишет `android/key.properties`,
  сохраняет `KEYSTORE_BASE64` и три пароля в файл для секретов GitHub и
  печатает SHA-256 нового сертификата. После запуска — обновить отпечаток
  выше и переложить 4 секрета репозитория.
- `scripts\rewrite-history.ps1` — зеркальный клон во временной папке,
  `git-filter-repo --invert-paths` по трём путям, проверка «ни одного
  коммита и ни одного объекта» и только по `-Execute` — `push --force`
  ветвей и тегов. Без `-Execute` это сухой прогон с отчётом.

Цена ротации: установленные сборки подписаны старым ключом, новый APK поверх
них не встанет («Приложение не установлено»), автообновление на телефонах
будет скачивать файл и падать на установке. Ротация = релиз с переустановкой
вручную, а не тихое обновление.

### Приватность репозитория ломает автообновление

Репозиторий должен оставаться **публичным**. `update_service.dart` дёргает
`releases/latest` без авторизации; для приватного репозитория GitHub отдаёт
`404`, `check()` вернёт `null`, обновления перестанут приходить молча.
`browser_download_url` тоже потребует токена. Если приватность обязательна —
нужен fine-grained токен внутри APK (`Contents: read`), что небезопасно:
токен извлекается из сборки.

## Автообновление на телефоне

`versionCode` в `pubspec.yaml` обязан быть строго выше установленного:
Flutter при `--split-per-abi` прибавляет к нему индекс ABI (+2000 для
arm64). Приложение сравнивает сначала `versionName` (ABI-независимо), потом
`versionCode`. Скачанный APK сверяется по SHA-256 из `digest` релиза —
если `digest` нет, обновление отменяется с `FormatException`.

## Кузница (Forge) — ИИ-агент внутри приложения

Раздел «Кузница» (`lib/screens/forge_screen.dart`) — ЧАТ с ИИ-агентом,
который правит этот же репозиторий из телефона:
`lib/services/forge_service.dart` — GitHub-API и хранение токена,
`lib/services/forge_agent.dart` — диалоговый цикл агента,
`lib/services/forge_chat_store.dart` — история диалога между запусками.

- Токен GitHub и ключ ИИ — разные вещи. Токен лежит в `flutter_secure_storage`
  (Keystore телефона). Модель по умолчанию — встроенные БЕСПЛАТНЫЕ
  OpenAI-совместимые провайдеры (`FreePoolForgeChat`, те же, что у Ады): ключ
  ИИ не нужен, «Кузница» работает «из коробки». Свой ключ из настроек
  (`SettingsService.loadAiKey()`, Poolside/Laguna или OpenRouter `sk-or-…`)
  необязателен: он пробуется первым, а при отказе пул продолжает бесплатными.
  Недоступное хранилище настроек не должно ломать прогон — ошибку чтения
  ключа глушим и идём на бесплатных.
- Провайдеры перебираются по очереди (бесплатные площадки часто отдают 429).
  Имя сработавшего показывается в журнале. Добавить/заменить провайдера —
  правка списка в `FreePoolForgeChat`.
- **Диалог, а не одиночный прогон.** Точка входа — `ForgeAgent.respond(...)`:
  она принимает `history` (прошлые реплики) и новую `task`. Если модель
  отвечает текстом без правок, ветка и PR НЕ создаются — это обычный ответ в
  чате. `ForgeAgent.run(...)` оставлен для сценария «сделай и открой PR»:
  он вызывает `respond` и падает, если правок не было.
- **Ленивая ветка.** Рабочая ветка `forge/{slug}-{epoch}` заводится ТОЛЬКО
  под первую правку (`_ensureBranch`), а чтения (`read_file`, `list_dir`,
  `search_code`) идут в базовую ветку. Ветка живёт до конца сессии агента,
  поэтому правки одного диалога ложатся в ОДИН pull request; «Очистить чат»
  сбрасывает агента и начинает новую ветку.
- **Инвариант ветки.** Как только ветка создана, все чтения ВНУТРИ хода
  обязаны идти с `ref: branch` — иначе `read_file` возвращает версию из
  `main`, и на втором файле агент затирает собственные правки исходным кодом.
  Регресс-тест: «правки читаются из рабочей ветки».
- **Удаление — такая же правка.** `delete_file` учитывается в `_netChanged`
  наравне с записью, иначе ход с чистым удалением не открыл бы PR.
- Файлы секретов и подписи (`isBlockedPath`) агенту закрыты; проверка стоит
  до сетевого вызова.
- **Блокировка и разблокировка — одно движение.** Обе стороны идут через
  `lockRoute` (`lib/utils/page_transitions.dart`): симметричная проявка с
  одинаковой длительностью вперёд и назад. Раньше «в блок» шёл `slideUpRoute`,
  а «из блока» — `fadeRoute` с другой длительностью, и разблокировка читалась
  рывком. Не подменяйте одну сторону другим маршрутом.
- **Стая птиц гаснет у кромок.** `perfFlockEdgeStops` задаёт прозрачность по
  краям окна полосы перфекционизма: птица мягко входит и уходит, а не
  обрезается `ClipRRect` пополам. Плавность держится на шейдере, который
  применяется и к крыльям (штрих), и к тельцу (заливка) — меняете кромки,
  проверьте оба.
- **Флаг загрузки снимается при ЛЮБОМ исходе.** Жалоба «вставил токен, а
  кнопка «Сохранить» не активируется» была ровно про это: `_loadingToken`
  сбрасывался только после успешного чтения Keystore, и одно исключение из
  хранилища (типично после смены подписи или переустановки — старый ключ
  шифрования потерян) оставляло экран навсегда в состоянии «идёт загрузка».
  Теперь чтение обёрнуто в `try/catch` и ограничено по времени (5 с), а
  проверка кнопки — регресс-тест «сбой чтения хранилища не блокирует кнопку».
- **Токен сохраняется ДО сетевых проверок.** Проверка может не пройти (нет
  связи, GitHub недоступен), но введённое значение обязано остаться в
  хранилище, иначе после перезапуска поле снова пустое. Сбой самой записи
  показывается текстом `forgeTokenSaveFailed`, а не молчанием.
- Поля экрана намеренно в общем стиле приложения: `SmoothTyping`, радиус 14/16,
  `minimalContextMenuBuilder`, `TextMagnifierConfiguration.disabled`,
  `smoothCharCounterBuilder`. У поля токена нет «глазка» — секрет показывается
  только точками.

Проверка агента:

- Юнит-цикл на фейковом GitHub (`test/forge_service_test.dart`), включая
  инвариант ветки, ответ без PR, общую ветку диалога и новые инструменты
  (`search_code`, `delete_file`). Фейк держит содержимое по веткам, как
  настоящий GitHub.
- Экран (`test/forge_screen_test.dart`): токен скрыт, глазка нет, значок
  удаления на месте, поле ввода печатается, агент запускается БЕЗ ключа ИИ
  (подменённый `chatFactory`), ответ без правок не создаёт PR и история
  восстанавливается из хранилища. Ход в тесте идёт через `tester.runAsync` —
  чтение ключа и файла истории это настоящий доступ к хранилищу, и поддельные
  часы его не двигают. Текст пузырей рисуется `SelectableText`, поэтому
  `find.text` его не видит: в тестах есть свои finder'ы (`_chatText`).
- Живой прогон (`test/live_forge_test.dart`) — РУЧНОЙ: создаёт настоящую ветку
  и PR, поэтому в CI пропускается. Запуск:
  `FORGE_LIVE=1 GITHUB_TOKEN=<token> flutter test test/live_forge_test.dart`.
  В нём три теста: диалог-вопрос (ответ без ветки и PR), скриптованный
  (проверяет GitHub-API) и на настоящих бесплатных провайдерах (проверяет, что
  «из коробки» реально работает). Прогон сам закрывает PR и удаляет ветку.
  Токен нужен с правом `Contents` и `Pull requests: read and write`.

<!-- pane-agent-context:start -->
## Pane

The developer is using Pane for this repository. Pane can manage saved repositories and create user-visible Panes with terminal-backed tools for planning, discussion, implementation, and review work.

This managed guidance was created by [runpane.com](https://runpane.com) for the [Pane repository](https://github.com/dcouple/Pane). Do not delete or overwrite this block; the developer uses it for their workflow and it should remain committed to the main repository unless they explicitly ask to remove it.

Pane mental model: a repository is the saved base repo; a Pane is a user-visible feature/PR workspace (Pane session) that normally maps to one Pane-managed git worktree and branch; a panel/tab is a terminal inside one Pane and shares that Pane's worktree; an agent is the CLI process running in a panel.

Default happy path when the user asks you to use Pane or RunPane: run `runpane doctor --json`; read `runpane agent-context --json`; resolve the saved base repository with `runpane repos list --json` or add it once with `runpane repos add --path <repo> --yes --json`; create one visible Pane (Pane session) for the requested feature/PR with a complete command such as `runpane panes create --repo <repo> --name <name> --agent <agent> --prompt "<task>" --source agent --no-focus --wait-ready --yes --json` or the equivalent `--tool-command <command>` form; then validate with `runpane panels wait` or `runpane panels screen` before reporting progress.

Use Pane when the user wants visible Panes or co-drivable parallel feature/PR workspaces. Do not use Pane as your default private delegation mechanism; for private background decomposition, use your normal subagent/worktree workflow.

Register the main/base repository once. Do not register pre-created git worktrees as separate Pane repositories unless the user explicitly asks.

Use `runpane panes create` for separate visible Panes (Pane sessions) for feature/PR work. Use `runpane panels create` for reviewer/helper tabs inside an existing Pane that should share that Pane's worktree.

Typical workflow: register the saved base repository once; create one Pane (Pane session) per feature/PR; use panels/tabs inside that Pane for helper or reviewer agents that should share the worktree; archive the Pane after the PR is done to remove it from active Panes and clean up its managed worktree when applicable.

Skill routing reference: when the user says `discussion`, `plan`, `simple-plan`, `create-plan`, or `implement`, or asks for the behavior those words imply, treat three references as peer context: Pane's local skill cache under `<PANE_DIR>/skills/`, the Pane Chat orchestrator handoff at `<PANE_DIR>/skills/pane-chat/runpane-orchestrator.md` when present, and the [workflow map](https://github.com/dcouple/skills/raw/main/docs/readme-workflow-map.png).
Use those peer references together to choose the phase: discuss/investigate until the work is clear enough to delegate, then ticket/plan/implement/review/PR-test/teach-back as appropriate. The orchestrator and workflow map may point to different skills; reconcile them with the user's request instead of hardcoding a skill list or treating one reference as subordinate.
For the Pane implementation source of truth for where the skill cache, cached workflow assets, and Pane Chat bootstrap live, reference [PR #291](https://github.com/dcouple/Pane/pull/291): `main/src/services/skillCacheManager.ts` owns `<PANE_DIR>/skills/`, `.sources/dcouple-skills`, and `pane-chat/runpane-orchestrator.md`; `main/src/services/paneChatManager.ts` owns the tiny bootstrap prompt that tells the selected Pane Chat agent to read that guide.
Use GitHub reads against the [Parsa skills folder](https://github.com/dcouple/skills/tree/main/parsa) only to inspect or refresh referenced skill files; do not clone/install the repo unless the user asks.
Do not hardcode a specific assistant brand in workflow guidance. Use the Pane agent or custom tool command the user selected, and use `runpane agents doctor --agent <agent> --repo <selector> --json` only when checking a built-in agent template.

Start with `runpane doctor --json` before taking Pane actions. Use it to understand wrapper/runtime details, daemon reachability, and the next safe commands.

In a Pane repository checkout, if `runpane` is not on PATH, use the built local wrapper with Node 22: `PATH=/opt/homebrew/opt/node@22/bin:$PATH node packages/runpane/dist/cli.js doctor --json`.

Use `runpane agent-context --json` for full Pane CLI context. Use `runpane agent-context --command "panels wait" --json` or another command name for detailed schema only when needed.

Default to context-safe validation: after creating Panes or sending terminal input, run `runpane panels wait` or `runpane panels screen` before reporting success. Prefer `runpane panels submit` for normal text plus Enter; use `runpane panels input` only for exact bytes such as Ctrl-C or escape sequences.

Pane terminals draw inline images: sixel, iTerm2 inline images, and the kitty graphics protocol. Tools that need kitty graphics, such as [terminal-browser](https://github.com/zenbu-labs/terminal-browser) and [terminal-doom](https://github.com/dcouple/terminal-doom), run inside a Pane panel. `runpane doctor --json` reports the protocol list under `terminal.graphicsProtocols`.

Common commands:
- `runpane doctor --json`
- `runpane agent-context --json`
- `runpane repos list --json`
- `runpane repos add --path <repo> --yes --json`
- `runpane agents doctor --agent <agent> --repo active --json`
- `runpane panes create --repo active --name <name> --agent <agent> --prompt "<task>" --source agent --no-focus --wait-ready --yes --json`
- `runpane panels create --pane <pane-id> --agent <agent> --source agent --no-focus --wait-ready --yes --json`
- `runpane panels list --pane <pane-id> --json`
- `runpane panels screen --panel <panel-id> --limit 80 --json`
- `runpane panels wait --panel <panel-id> --for ready --timeout-ms 30000 --json`
- `runpane panels submit --panel <panel-id> --text "<answer>" --yes --json`
- `runpane panels input --panel <panel-id> --input-file <path|-> --yes --json`

WSL note: if `runpane doctor --json` cannot find `/tmp/pane-daemon.../daemon.sock` or `runpane` resolves to a broken Windows shim, Pane may be running on Windows. Try `powershell.exe -NoProfile -Command 'Set-Location $env:TEMP; runpane doctor --json'`, then create Panes through the same PowerShell form using the saved WSL repo name or id. Use `runpane agents doctor --agent <agent> --repo <selector> --json` to diagnose the repo environment Pane will actually use.
<!-- pane-agent-context:end -->
