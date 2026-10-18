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
нет — он в `.gitignore`, лежит только локально у владельца.

## Автообновление на телефоне

`versionCode` в `pubspec.yaml` обязан быть строго выше установленного:
Flutter при `--split-per-abi` прибавляет к нему индекс ABI (+2000 для
arm64). Приложение сравнивает сначала `versionName` (ABI-независимо), потом
`versionCode`. Скачанный APK сверяется по SHA-256 из `digest` релиза —
если `digest` нет, обновление отменяется с `FormatException`.

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
