Build recipe: run
`Remove-Item Env:AGYSHA_NO_R8 -ErrorAction SilentlyContinue; & 'C:\Users\Larafut\dev\flutter\bin\flutter.bat' build apk --release --split-per-abi --target-platform android-arm64`
then install over the existing Android device (keep user data):
`& "$env:USERPROFILE\dev\android-sdk\platform-tools\adb.exe" install -r "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"`.
flutter/adb are not on PATH on this machine: flutter lives at `C:\Users\Larafut\dev\flutter\bin\flutter.bat`, adb at `C:\Users\Larafut\dev\android-sdk\platform-tools\adb.exe` (see `android/local.properties`).

## Идентификаторы проекта (переименование 2026-11)

Приложение называется **Agysha** (прежнее имя — Keramika). Android-пакет
`com.wetcorp.agysha` (был `com.wetidom.keramika`), репозиторий
`wxstdo-boop/Agysha` (GitHub капитализирует первую букву; старые ссылки
редиректят). При переименовании менять СИНХРОННО:

- `android/app/build.gradle.kts` — `namespace` и `applicationId`;
- каталог `android/app/src/main/kotlin/com/wetcorp/agysha/` + `package`-строки
  во всех `.kt`, строки `MethodChannel`/action'ов и `-keep` в `proguard-rules.pro`;
- в Dart все `MethodChannel('com.wetcorp.agysha/...')` (main, alarm_scheduler,
  notification_service, haptics, installer, screen_reader_service,
  android_settings) — рассинхрон канала даёт молчаливо нерабочие будильники;
- `kUpdateRepoOwner`/`kUpdateRepoName` в `lib/services/update_service.dart` —
  от них зависит автообновление; ссылка в Настройках (`settings_screen.dart`);
- рецепт F-Droid `fdroid/metadata/com.wetcorp.agysha.yml` (имя файла = package id);
- forge-тесты держат `owner`/`repo` в моках — при смене имени падают.

Бренд-токены по всему дереву: `Agysha`/`agysha`/`AGYSHA_` в текстах, путях
(`assets/agysha.png`, `lib/widgets/icons/agysha_icons.dart`, префикс иконок
`Ag`/`kAg`), идентификаторах хранилища (`agysha-json-v1`,
`agysha_database_key_v1`, `agysha_recovery_*`), именах каналов уведомлений
(`agysha_alarm`, `agysha_rc`, `agysha_main`), именах APK-ассетов
(`Agysha-<ver>-<abi>.apk`), keystore (`agysha-release.jks`, alias `agysha`,
`CN=Agysha`) и боте релиза (`agysha-ship`).

Исключение — обратная совместимость хранилища в `lib/services/json_file.dart`:
константы `_legacyFormat`/`_legacyKeyName` (`keramika-json-v1`,
`keramika_database_key_v1`) намеренно оставлены и должны читаться. У тех, кто
обновился с Keramika, файлы и ключ шифрования записаны под старыми именами;
без чтения legacy-значений приложение сочло бы хранилище пустым, сгенерировало
новый ключ и потеряло привычки, задачи и будильники. Не «вычищай» их при
ребрендинге — это регресс-тест `reads envelopes written under the legacy
Keramika format` в `test/json_file_test.dart`.

## Linux dev sandbox (agent environment)

No Flutter and no Android SDK are preinstalled, and the sandbox can be wiped
mid-session. Recipe that works here (pin the version — the project needs
Dart >= 3.12, so 3.35.x is too old). Install the SDK under `/workspace`, NOT
under the home directory: a mid-session sandbox wipe clears `/home` and `/tmp`
but keeps `/workspace`, so a `/workspace` SDK survives and only needs
`export PATH` again:

```
mkdir -p /workspace/sdk_tmp && cd /workspace/sdk_tmp
curl -sL -o f.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.47.5-stable.tar.xz
tar xf f.tar.xz && rm f.tar.xz
export PATH="/workspace/sdk_tmp/flutter/bin:$PATH"
git config --global --add safe.directory /workspace/sdk_tmp/flutter
```

Then `flutter pub get && flutter analyze && flutter test`. Android SDK/Java are
absent, so `flutter build apk` cannot run here — releases come from CI only.

Note: a mid-session wipe can clear `/tmp` while the shell keeps running, so a
`/tmp` file written by one command may be gone by the next. Keep scratch files
under `/workspace` (e.g. `/workspace/project/.tmp_x`) and delete them when done.
Also: a single shell command that is too long can get silently truncated — for
long lists (icons, seed data) write a small script file and run it instead.

Visual checks without a device: render widgets to PNG in a widget test via
`RenderRepaintBoundary.toImage` + `ImageByteFormat.png`, write to `/tmp`, then
inspect with Pillow (a plain `flutter test` works; screenshots are not needed).
Note `flutter test` needs a mocked `path_provider` channel and
`SharedPreferences.setMockInitialValues` before `initPrefs()` — copy the setup
from `test/section_pill_transition_test.dart`.

Грабля визуальных проверок: `testWidgets` крутит тело теста в fake-async зоне,
поэтому РЕАЛЬНЫЙ I/O там виснет — `Directory.systemTemp.createTemp()` и любой
`await` по файловой системе не завершаются, тест уходит в `flutter test`
таймаут. Для рендера подставь в мок `path_provider` готовый путь (`/tmp`),
а PNG пиши синхронным `File(...).writeAsBytesSync`. Полноэкранные сплэш-тесты
с `pumpAndSettle()` тоже виснут — анимации там бесконечные (`repeat()`),
крути время дискретными `pump(Duration)`.

## Версии пакетов и build-system

- `compileSdk` задан в ДВУХ местах и должен совпадать: `android/app/build.gradle.kts`
  и `android/build.gradle.kts` (там же `flutter.compileSdkVersion` для плагинов).
- `flutter_local_notifications` 23 требует `compileSdk 37`; его же тянут
  плагины (`file_picker` и т.п.). AGP под 37: **9.1.1** (9.0.1 не тянет),
  ему нужен **Gradle ≥ 9.3.1**. CI на JDK 17 запускает их без правок.
- `dynamic_color` держим на **1.9.x**: 2.x ушёл на пакет `material_ui`
  (второй `ColorScheme`) и несовместим с Flutter 3.47.5.
- `flutter_secure_storage` 11 поднял minSdk до 23 и мигрирует алгоритм
  шифрования сам; ключ в Keystore не теряем (`resetOnError=false`).
- Локальная проверка сборки: JDK 17 (не 21) + Android SDK в `/workspace`,
  `android/key.properties` + `keystore.jks` (оба в `.gitignore`).

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
`curl -s .../repos/wxstdo-boop/agysha/releases/latest` (пустой тег-лист =
релизов нет).

Keystore проекта: `agysha-release.jks`, alias `agysha`, сертификат
`CN=Agysha` (PKCS12, несмотря на расширение `.jks`). В рабочем дереве его
нет — он в `.gitignore` и должен лежать только локально у владельца и в
секретах репозитория.

Отпечаток для сверки подписи (должен совпасть у собранного APK):
`4B:48:38:78:6F:5D:00:29:75:F4:51:B2:C9:6B:62:91:5D:74:1D:49:0D:24:F3:D6:9F:3A:0A:F0:45:4E:12:1D`
(CN=Agysha, действует до 2053-12-13).

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
`android/app/agysha-release.jks` вычищены из всех коммитов, ветвей и тегов
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

### Установка: обычный системный установщик, а НЕ сессия PackageInstaller

Установку APK запускает `Intent.ACTION_VIEW` через `FileProvider`
(`MainActivity.installWithSystemInstaller`): система сама показывает свой
экран «Установить обновление?» с проверкой Play Protect, а пользователь
подтверждает.

Раньше здесь была сессия `PackageInstaller` (`installViaSession`) с
`setRequestUpdateOwnership(true)` и разрешением `ENFORCE_UPDATE_OWNERSHIP`:
она объявляла приложение владельцем своих обновлений и убирала лишнее
подтверждение, но система начинала трактовать установку как самообновление в
обход пользователя — и на незнакомом сайдлоаде Play Protect показывал
«вредоносное приложение заблокировано». Сессию, приёмник её результата
(`InstallResultReceiver`) и разрешение `ENFORCE_UPDATE_OWNERSHIP` убрали:
цена ускорения — сама возможность обновиться.

Что осталось:

- разрешение `REQUEST_INSTALL_PACKAGES` в манифесте — без него система не
  покажет даже экран установки для APK, пришедшего из приложения;
- `FileProvider` (`${applicationId}.fileprovider`, `exported=false`,
  `grantUriPermissions=true`) — раздаёт скачанный APK системному установщику
  точечно, флагом `FLAG_GRANT_READ_URI_PERMISSION`;
- `UpdaterBridge` и приёмник результата сессии удалены вместе с самой сессией.
  Dart-метод `consumeInstallResult` остался ради формы канала и всегда отдаёт
  `null`; при обычном системном установщике итог сообщает сама система. Поток
  `Installer.listen()` + `Installer.outcomes` тоже сохранён ради формы, а
  глобальный слушатель в `main.dart` (`_watchInstallOutcome`) показывает итог,
  если он когда-нибудь появится.

Грабли, на которые не наступать: FileProvider-путь не удалять «за
ненадобностью» молча — он оставлен в манифесте неэкспортированным; при
смене ключа подписи старый APK поверх нового не встанет (см. раздел про
keystore), это `STATUS_FAILURE_INCOMPATIBLE` и он честно показывается как
ошибка. Не возвращать сессию `PackageInstaller`, `ENFORCE_UPDATE_OWNERSHIP`
и тихий путь: регресс-тест `test/trusted_update_test.dart` это ловит.

### Play Protect: «вредоносное приложение заблокировано» — не баг установщика

Диалог «Вредоносное приложение / Приложение может быть небезопасно» с
кнопкой «Всё равно установить» — это вердикт Play Protect (проверка
репутации и эвристика по возможностям приложения), а НЕ следствие того,
каким интентом мы ставим APK. Сессия `PackageInstaller` убирает ярлык
«сторонний установщик» и на части прошивок — лишнее подтверждение, но она
не «обеляет» APK перед Play Protect.

**Что уже срабатывало и что откатили.** Порядок событий в истории проекта
это подтверждает:

1. сессия `PackageInstaller` с обычным подтверждением (`USER_ACTION_REQUIRED`)
   → Play Protect показывал «требуется проверка» — терпимо, установка шла
   в одно нажатие;
2. включили тихий путь (`USER_ACTION_NOT_REQUIRED` +
   `UPDATE_PACKAGES_WITHOUT_USER_ACTION`, коммит «тихий путь владельца
   обновлений») → вердикт сменился на «вредоносное приложение
   заблокировано». Установка перестала проходить вообще;
3. добавили владение обновлениями (`setRequestUpdateOwnership` +
   `ENFORCE_UPDATE_OWNERSHIP`) → система снова увидела самообновление в обход
   пользователя, вердикт опять ужесточился. Сессию и приёмник её результата
   убрали, установку перевели на обычный `Intent.ACTION_VIEW`.

Вывод: **разрешение `UPDATE_PACKAGES_WITHOUT_USER_ACTION` и флаг
`USER_ACTION_NOT_REQUIRED` — это и есть триггер**, а не способ запуска
установки. Их вернули назад. Регресс-тест `test/trusted_update_test.dart`
теперь проверяет ОБРАТНОЕ: разрешения нет в манифесте, флаг —
`USER_ACTION_REQUIRED`, сессии `PackageInstaller` и `ENFORCE_UPDATE_OWNERSHIP`
в коде нет.

Что ещё влияет на вердикт и что в наших руках:

- **Профиль разрешений.** Набор `REQUEST_INSTALL_PACKAGES` +
  `SYSTEM_ALERT_WINDOW` (окно поверх других приложений) + служба
  спец. возможностей, читающая экран, — это возможности, по которым Play
  Protect метит незнакомые сайдлоады как «fraud/unsafe». Убрать их из
  рабочей сборки нельзя без потери функций (оверлей Ады, чтение экрана), но
  F-Droid-рецепт вырезает `REQUEST_INSTALL_PACKAGES` (и
  `ENFORCE_UPDATE_OWNERSHIP`) из манифеста, а самообновление там выключено
  `AGYSHA_NO_SELF_UPDATE`.
- **Репутация источника.** Приложения из Google Play, F-Droid и других
  каталогов Play Protect по умолчанию считает доверенными; APK «из
  интернета» — нет. Значит честное лечение не в коде приложения, а в
  распространении через каталог (F-Droid) и/или подписанные Play-релизы.
- **Подпись одним ключом.** Обновление ставится поверх только при совпадении
  подписи; после ротации ключа APK поверх старого не встанет
  (`STATUS_FAILURE_INCOMPATIBLE`), это не «блокировка Play Protect».

Никакой `--dart-define`, «подпись сертификатом Google» или «доверенный
интент» вердикт Play Protect не снимает. Убрать предупреждение «навсегда»
из чужого устройства нельзя и не нужно: пользователь либо ставит из
каталога, либо подтверждает установку один раз вручную. Если считаешь
блокировку ошибочной — есть официальная апелляция Google
(«If you believe that your app was incorrectly flagged or blocked by Google
Play Protect, file an appeal», support.google.com/googleplay/answer/2812853).

Важно про **первую** установку: первый APK ставится всегда с системным
подтверждением — тихого пути для первой установки не существует, и код этого
не обещает.

Профиль службы спец. возможностей держим минимальным: в
`res/xml/screen_reader_config.xml` объявлен только `flagDefault`, без
`flagReportViewIds` и `flagRetrieveInteractiveWindows` — код обходит дерево
от `event.source`/`rootInActiveWindow` и читает только `text` и
`contentDescription`, `getWindows()` не вызывается. Лишняя объявленная
возможность не даёт приложения ничего, но расширяет профиль до
«шпионского». Держит регресс-тест `test/accessibility_capability_test.dart`.

## Автоэкспорт бэкапа

Раз в час приложение пишет зашифрованный бэкап в `Download/Agysha` (Android,
через нативный MediaStore-канал `saveToDownloads` на канале `alarm_payload`),
либо в `Downloads/Agysha`/документы на десктопе. Файл — фиксированного имени,
каждый экспорт перезаписывает предыдущий; время последнего лежит в
`last_auto_export_at`, чтобы «догонять» пропущенный час после возврата из фона
(`maybeCatchUpAutoExport`).

Грабли, которые уже ловили:

- **Сбой записи молчал.** `_autoExportTick` глотал исключение в `debugPrint`,
  и в релизе пользователь не видел ни файла, ни причины — автоэкспорт выглядел
  «мёртвым». Теперь при РУЧНОМ включении показывается `autoExportFailed`
  (фоновый «догон» по-прежнему молчит, чтобы не спамить).
- **Удаление старой копии роняло экспорт.** После переустановки (обновление,
  смена подписи) строка файла в MediaStore принадлежит прошлому владельцу, и
  `resolver.delete` бросает `RecoverableSecurityException` (Android 10+). Раньше
  это исключение всплывало из `saveBytesToDownloads` и срывало весь экспорт —
  теперь ошибка удаления только логируется, новая копия всё равно пишется и
  заменяет старую по имени.
- **Файл не появляется в Download при сбое нативного канала.** Тогда работает
  фолбэк через `path_provider` (`getDownloadsDirectory` →
  `getApplicationDocumentsDirectory`). Он покрыт `test/auto_export_test.dart`:
  каталог загрузок в тесте «недоступен», проверяется именно фолбэк.

## Будильники: инварианты срабатывания

Путь будильника: Dart `notification_service.scheduleAlarm` →
`AlarmSchedulerPlugin.scheduleAlarmClock` (setAlarmClock) → `AlarmReceiver`
(звонок через `AlarmForegroundService` + уведомление + экран задачи) →
`WakeTaskScreen` → `stopAlarmSound`. Догон после перезагрузки — `BootReceiver`
нативно из манифеста `alarm_manifest` (SharedPreferences, пишет плагин).

- **Срабатывание будильника НЕ зависит от уведомлений.** `scheduleAlarm`
  гейтит только по `_initialized`/`_supported`, но НЕ по тумблеру
  «Уведомления» и НЕ по `POST_NOTIFICATIONS`. Звонок поднимает
  `AlarmForegroundService` по точному `AlarmManager`, звук играет
  `MediaPlayer` сервиса — право на уведомления ему не нужно. Раньше жёсткий
  гейт `if (!_enabled || !await ensureNotificationPermission()) return false`
  молча запрещал постановку: стоило отказать в уведомлениях (или системе —
  снять право после обновления APK), как будильники оставались «включёнными,
  но не звонящими». Право лишь ПРОСИМ, но не требуем.
- **Одноразовый будильник не воскресает.** При срабатывании `AlarmReceiver`
  зовёт `AlarmSchedulerPlugin.markOneShotFired` + `removeManifestEntryFor`,
  а Dart на старте/возврате из фона гасит такие будильники через
  `AlarmService.disarmFiredOneShots` (канал `consumeFiredOneShots` — читается
  и очищается ровно один раз). Без этого «поставить один раз» превращалось
  в «звонит каждый день»: и Dart-перепланировка, и `BootReceiver` считали
  отзвонивший будильник «ещё не наступившим» и взводили его на завтра.
  Тот же инвариант в запасном пути плагина: `matchDateTimeComponents` =
  `null` при пустых `repeatDays` (раньше был `DateTimeComponents.time` —
  ежедневный повтор).
- **Prefs будильников переезжают при ребрендинге.** `PREFS_NAME` менялся
  `keramika_schedule` → `agysha_schedule` без миграции, и после обновления
  APK `MY_PACKAGE_REPLACED` будил `BootReceiver`, который читал ПУСТОЙ
  манифест и не взводил ни одного будильника («поставил на утро, обновилось
  ночью, утром тишина»). `AlarmSchedulerPlugin.migrateLegacyPrefs` переносит
  манифест и `fired_one_shots` из legacy-prefs; зовётся и в
  `registerWith` (Dart-путь), и в `BootReceiver.rescheduleFromManifest` —
  ДО чтения манифеста. Идемпотентно. Не переименовывать prefs без миграции.
- **Один звонок за раз.** `AlarmForegroundService.onStartCommand` при уже
  идущем звонке обязан сперва погасить прошлый звук (`resetAudio`): прежний
  `MediaPlayer` терял ссылку и продолжал играть рядом с новым — два звонка
  накладывались, «будильник двоит». Сброс вибрации идёт тем же экземпляром
  (`cancelVibration`, `VibratorManager.defaultVibrator`), что и старт.
- **Двойной показ экрана задачи гасится флагом** `_wakeScreenShowing`:
  cold-start (`_AlarmBootHost` как домашний экран) и hot (`onNewAlarmPayload`
  → `_handleNotificationTap`) не должны открыть `WakeTaskScreen` дважды.
- **Двойное закрытие гасится `_finished`** в `WakeTaskScreen._finish`:
  авто-закрытие (1 с после решения) и ручной «Выключить» идут одновременно —
  второй `pop`/`stopAlarmSound` ронял экран.
- **Перепланировка на старте/возврате** (`rescheduleAllNotifications`)
  сперва гасит прозвеневшие одноразовые, потом взводит включённые.
- **Каналы — не `late final`.** Раньше `_alarmPayloadChannel` и
  `_lifecycleChannel` присваивались в `initChannels()`, которую никто не
  вызывал: первый же `setMethodCallHandler` в `_startApp()` падал с
  `LateInitializationError`, и тап по уведомлению в ЖИВОМ приложении
  (`onNewIntent` → `onNewAlarmPayload`) не открывал экран задачи. Каналы
  создаются сразу константами, а `_listenForAlarmPayloads()` зовётся при
  монтировании `AgyshaAppState`. `MethodChannel` на web безвреден — не
  трогает платформу до первого `invoke`.
- **Остановка звонка — адресная.** Удаление/выключение звенящего будильника
  не гасило звук: отмена `AlarmManager` и уведомления не трогают
  `AlarmForegroundService`, и он играл до 5-минутного `MAX_RING_MS`. Теперь
  сервис помнит `ringingCode` (= `alarm_id.hashCode`), а `stopFor(ringCode)`
  (канал `stopAlarmSoundFor`) глушит звук ТОЛЬКО если звонит именно этот
  будильник — иначе параллельный звонок другого будильника не срывается.
- Диагностика — чёрный ящик `alarm_fire_log.txt` (пишут и `AlarmLog.kt`, и
  `AlarmBlackBox`), читается через adb без root.

## Витрина и «Что нового»

- **Скриншоты в README генерируются тестом**, не снимаются руками:
  `flutter test tool/screenshots/render_screenshots.dart` кладёт PNG в
  `docs/screenshots/`. Скрипт монтирует РЕАЛЬНЫЕ экраны в ТОЧНОЙ теме
  приложения по умолчанию (светлая лавандовая `ColorScheme.light`, не
  `fromSeed` — `fromSeed` даёт другую палитру, витрина расходится с видом).
  Шрифт с кириллицей (Roboto из pub-кэша / DejaVu) подгружается вручную,
  иначе `flutter_test` рисует «квадратики». Файл вне `test/`, поэтому
  обычный `flutter test` его не подхватывает.
- **Экран «Что нового» живой** (`changelog_screen.dart`): список берётся из
  публичных GitHub-релизов через `UpdateService.fetchChangelog()`, а не из
  захардкоженного массива (тот застрял на 1.6.72 при версии 1.6.104).
  Парсер `parseReleaseNotes` срезает таблицу SHA, заголовки, `by @… in …`,
  markdown-акценты, технический хвост в скобках, префикс conventional-commit
  (`feat:`, `fix(scope):`) и хвостовую пунктуацию, а также отбрасывает
  служебные коммиты (`release:`, `Merge`, `ci:`, `chore:`, `test:` …) и
  дубликаты — «Что нового» читается как заметки, а не как сырой `git log`.
  Важен ПОРЯДОК: служебные типы отсеиваются ДО снятия префикса, иначе от
  `ci:`/`chore(deps):` остаётся полезно выглядящий текст.
  При отсутствии сети показывается короткий встроенный запасной список.
  Результат кэшируется в памяти на 6 ч. Логику покрывают
  `test/services_test.dart` (парсеры) и `test/changelog_screen_test.dart`
  (запасной список без сети).
- **Числа в README/docs должны совпадать с реальностью.** Считаем:
  `find test -name '*.dart' | wc -l` — файлы, `flutter test` — число тестов,
  `find lib/services -name '*.dart' | wc -l` — сервисы. Расходились уже
  трижды (199→234→245 тестов, 33→39→42 файла, 49→56 компонентов).

## Токены дизайна и движение

- `lib/utils/design_tokens.dart` — единый источник правды (`Radii`,
  `Spacing`, `Motion`, `Weights`). Тема (`lib/theme/app_theme.dart`) тянет
  из него радиусы и начертания. Правило: новое значение берём из шкалы,
  а не «ещё один магический радиус/длительность».
- `lib/utils/motion_prefs.dart` — `MotionPrefs.shouldReduceMotion` (системный
  запрос + тумблер в настройках). Декоративные БЕСКОНЕЧНЫЕ петли обязаны
  уважать его: `MotionAwareRepeat.ambientRepeat(...)` или явная проверка
  перед `repeat()` (как в `splash_screen.dart`). ФУНКЦИОНАЛЬНЫЕ индикаторы
  (точки «печатает…», крутилка прогресса) НЕ гасим — они несут состояние.
- Тумблеры вибрации и «убрать анимации» уже в настройках
  (`settings_screen.dart`), рядом кнопка «Очистить кэш» того же вида.
- **Фирменные FAB — по рецептуре главной таблетки.** Кнопки «+» и Ада
  (`OrganicFab`/`GlassFabTile` в `press_splat.dart`, `_buildFab` в
  `ai_guide.dart`) берут ТУ ЖЕ плоскую нейтральную поверхность, тонкую
  кромку `outlineVariant` и мягкую тень, что `_GlassCapsule` в
  `section_pill.dart`. Никакого цветного `primaryContainer`-градиента,
  primary-ореола и стеклянного блика: они делали FAB отдельным «стеклянным»
  островом. Значок Ады НА КНОПКЕ — монхромный (`AdaAvatar.monochrome`):
  тот же нейтральный медальон и `primary`-чернила, что у невыбранного
  значка таблетки; в чате/пузырях Ада остаётся цветной. Меняешь материал
  капсулы — правь и плитку, иначе семья распадётся.

## Круг 21: профиль, клавиатура, окно события, «Метель», статистика, питание

- **`PressScale.pressedOpacity`.** Крупной карточке мало масштаба: на плашке
  во всю ширину 1–2 % уменьшения почти не видно. Добавлен опциональный
  `pressedOpacity` (по умолчанию 1.0) — он гаснет тем же прогрессом, что и
  масштаб, поэтому лишних слоёв не появляется, а отклик читается. В профиле
  все `_Card` обёрнуты в `PressScale(0.99, pressedOpacity: 0.94)`; карточка
  музыки исключена (`pressable: false`) — внутри свои жесты (свайп/драг).
- **Кнопка-действие в `InlineKeyboard` осталась в API, но НЕ используется.**
  В «Добавить друга» «Добавить» — снова отдельная широкая кнопка над
  панелью: встроенная в ряд клавиша отъедала место у пробела и читалась как
  ещё одна буква. Если снова понадобится — параметры `actionLabel`/`onAction`
  на месте.
- **Плавный регистр клавиатуры.** `_CaseGlyph` держит оба начертания в одном
  слоте и переключает их кроссфейдом со сдвигом ±5 px по общему
  `_caseAnim` (240 мс). Подменять `label` кадром нельзя — владелец видит
  «буквы дёргаются».
- **Каскад шапок в окне ивента нельзя пускать одновременно с входом.**
  Волна слотов (0→12) поверх ещё «доезжающего» содержимого читается
  дёрганьем. `_seedHatsAfterEntrance` ждёт, пока `_open` пройдёт 60 %, и
  только тогда сеет. Плюс вход удлинён до 700 мс, а старт масштаба поднят с
  0.94 до 0.975 — 6 % на крупной карточке выглядели «наездом».
- **Снежинки «Метели» — круги, не штрихи.** `drawLine` читался царапинами,
  а тёмный `0xFF5C7C8C` — мусором. Теперь светлое ядро `0xFFF4FBFF` плюс
  широкий белый ореол. Сияние приглушено (alpha 0.11/0.13/0.12).
- **«Иероглиф» в статистике — это наложение.** `AnimatedSwitcher` с
  `FadeTransition` держит оба ребёнка в дереве во время кроссфейда: старый и
  новый процент рисовались друг поверх друга в одной точке. Убран — числа
  меняются мгновенно (они и так не кадровые). Вторая причина — точка
  «сегодня» (`chartBottom + 6`) лезла ровно под подпись последнего дня;
  удалена, последний столбик и так подсвечен колонкой.
- **Лаг графика — клип-слои.** `canvas.clipRRect` на каждый из 30 столбиков
  = 30 слоёв отсечения на кадр роста. Стек рисуется без клипа: нижний
  сегмент прямоугольником, верхний — `RRect` со скруглённой верхней кромкой.
- **Питание: геометрия свайпа.** Радиус карточки и красной плашки выровнены
  по 20 — как у привычек и задач. Заголовок дня («Сегодня») теперь
  `_DayHeader`: новый раскрывается по высоте, ушедший остаётся «призраком»
  (`_dayGhosts`) и гаснет. Значок закрепа без `easeOutBack` — мягкий разгон.

## Плавность: грабли, на которые уже наступали

- **`toImageSync` в кадре тапа — так не делать.** Синхронный
  `RenderRepaintBoundary.toImageSync` / `Picture.toImageSync` строит сцену и
  копирует кадр прямо на UI-потоке: в момент нажатия это читается как рывок
  и просадка всего приложения. Снимок для размытия окна выхода берётся
  АСИНХРОННО (`toImage`) и ЗАРАНЕЕ — кнопка «Выйти» греет растр на
  касание/наведение (`_prewarmExitBackdrop`), сам тап лишь забирает готовый.
  Вторая половина грабли: `dispose()` исходного `ui.Image`/`ui.Picture`
  ДО завершения растеризации роняет кадр при отрисовке («Cannot clone a
  disposed image») — фон мигал. Освобождать только ПОСЛЕ `await`.
- **`IntrinsicHeight` на карточке списка — дорого.** Каждый такой виджет
  добавляет intrinsic-проход по всему поддереву на каждый layout; на списке
  из десятков карточек при скролле это «экран адски стопорится». В
  `habits_screen.dart` их было два на карточку (в `tasks`/`alarms` — ноль);
  центрирование делается `Row(crossAxisAlignment: center)`, а не intrinsic.
- **Layout текста в кадре анимации — лишняя работа.** Если строка не
  меняется, а меняется только эффект (шейдер блика, цвет, прогресс
  зачёркивания), держим `TextPainter` в кэше и переиспользуем; шейдер
  подставляем в `Paint` уже готового span (`_ShineTextPainter`,
  `AnimatedStrikeText._StrikeLayout`).
- **`ShaderMask`/`Opacity` на весь экран — это `saveLayer` каждый кадр.**
  Для затухания растровой картинки прозрачность задаёт сам `RawImage`
  (пишется прямо в `Paint` при отрисовке), отдельный слой не нужен.
- **`OverscrollNotification` не приходит с `BouncingScrollPhysics`.** У
  упругой физики пиксели уходят за границу свободно, и `applyBoundaryConditions`
  возвращает ноль — «перепротяжка» нигде не сообщается. Поэтому растяжение
  края (`_StretchScroll` в `stats_screen.dart`) считается НЕ по уведомлению, а
  по самой позиции: `minScrollExtent - pixels` / `pixels - maxScrollExtent`,
  которую опрашивает тикер, пока жест активен. Пружина возврата тогда сама
  тянет масштаб обратно, отдельная анимация отпускания не нужна. С
  `ClampingScrollPhysics` `OverscrollNotification` приходит — это разные
  механики, не путать.
- **Декоративный `Transform` нельзя вставлять/убирать под пальцем.** Если в
  покое возвращать `child` напрямую, а при протяжке оборачивать в
  `Transform.scale`, дерево меняется прямо во время жеста — и скролл рвётся
  (drag перестаёт двигать список). Держим `Transform` всегда, «покой» — это
  масштаб 1.0. Проверка в тесте — по ключу `ValueKey('stats_stretch')`.
- **`NotificationListener` обязан быть ВЫШЕ скролла.** Растяжение края ловит
  уведомления скролла, поэтому `_StretchScroll` оборачивает
  `SingleChildScrollView` СНАРУЖИ. Если положить слушателя внутрь скролла
  (обернуть `Column`-контент), уведомления до него не доходят и растяжение
  молча перестаёт работать — без единой ошибки.
- **Деформацию скролла надо сглаживать по времени, а не повторять замер.**
  Позиция при упругой протяжке дрожит от кадра к кадру; масштаб, повторяющий
  её в лоб, читался как лаги. Экспоненциальное сглаживание с шагом от
  реального `dt` (`k = 1 - exp(-dt * _smooth)`) даёт одинаковую плавность на
  60 и 120 Гц. У нуля «хвост» обрезаем, иначе значение сходится к нулю
  бесконечно и тикер не останавливается.
- **Верхняя плашка не должна растягиваться вместе с контентом.** Общая
  сводка (`stats_screen.dart`) едет отдельным `header`-слотом вне
  `Transform.scale`: иначе при протяжке она «плывёт» под пальцем и читается
  как рывок.
- **Вечная декоративная анимация чисел — главный источник лага экрана.**
  «Глитч» цифр статистики (два бегущих цветных двойника-тени) перерисовывал
  текст каждый кадр и вдобавок читался «иероглифом» на мелком числе. Числа
  сделаны статичными: свечение — одна мягкая `Shadow`, ноль лишних кадров.
  Не возвращайте `AnimationController.repeat()` под цифры.
- **Даже статичная тень на мелком числе — «иероглиф».** Мягкая `Shadow` под
  числом 10–12 px читается мутной кляксой на светлом фоне. Числа статистики
  (`_StatNumber`) — ЧИСТЫЙ текст, без `shadows` вовсе. Проверка в
  `polish_round_twenty_test.dart`.
- **`MaskFilter.blur` в `CustomPainter` — скрытый лаг.** Ореол «лучшего дня»
  на графике рисовался размытым кругом: размытие пересчитывалось КАЖДЫЙ кадр
  роста столбиков и на слабом GPU заметно тормозило. Замена — ровный круг
  малой плотности (`alpha: 0.10`), без блюра: глаз разницы не видит, кадр
  дешевле.
- **Кисти в `paint()` — до цикла по столбикам.** Тридцать `Paint()..color`
  на кадр (по штуке на столбик) — лишний мусор для GC и растеризатора.
  Все кисти (`habitPaint`, `taskPaint`, `outlinePaint`, `emptyDot`) собираются
  ОДИН раз перед циклом.
- **Подписи в `CustomPainter` не касаются кромки холста.** Дата «1»/«30»,
  прижатая к краю, сливалась с первым/последним столбиком и читалась
  «иероглифом». Отступ 3 px (`const inset = 3.0`) и кегль 11/w700 вместо
  10/w600 — цифра читается сразу.
- **Акцент внутри окна ивента — алая семья, а не `cs.primary`.** На
  дефолтной палитре primary сиреневый, в «Метели» — бирюзовый: медальон,
  бейдж дня, полоса прогресса и значок подарка читались чужими вставками
  внутри кровавой карточки. Один `accent = Color.lerp(BrandColors.red,
  cs.primary, 0.10)` на всю карточку, полоса — без примеси `tertiary`
  (в «Метели» он фиолетовый), кнопка «Забрать» — `lerp(..., 0.08)`.
- **Скелетон загрузки не крутит `CircularProgressIndicator`.** Штатный
  индикатор перерисовывается каждый кадр, пока идёт чтение, и вход окна
  ивента читался «дёрганым». Заглушка — разовый `TweenAnimationBuilder`
  (короткая пульсация) и дальше ноль кадров.
- **«Метель» — фон, а не сцена.** Шесть полос (четырнадцать заливок на кадр)
  и тридцать четыре снежинки читались на экране цветной кашей поверх
  контента. Теперь три полосы (одна подсветка неба + две ленты по два
  сегмента, пять шейдеров) и двадцать две неброские снежинки: небо держит
  настроение, но текст и карточки остаются читаемыми.
- **Смена аватарки анимируется, только если ключ стоит на ПРЯМОМ ребёнке
  `AnimatedSwitcher`.** В `ProfileAvatar._inner` ключ лежал на `SizedBox`
  ВНУТРИ `AnimatedBuilder`, а сам билдер был без ключа: переключатель видел
  «тот же виджет» и менял аватарку мгновенно. При этом содержимое обязано
  строиться ВНУТРИ билдера — иначе `sigma` размытия, растущая от прокрутки,
  замерзает на значении последней пересборки родителя.
- **Параллакс аватарки не нужен: он даёт «залысину».** Сдвиг содержимого
  круга вверх при прокрутке открывал сверху пустую полосу. Оставлено только
  размытие (`ProfileAvatar.motion` без `Transform.translate`). Тест-регресс —
  в `test/polish_round_two_test.dart` (ищет отсутствие `ValueKey('avatar_motion')`).
- **Размытие — НАСТОЯЩИЙ кросс-фейд, а не копия поверх.** Размытый слой
  ложился ПОВЕРХ резкого, и резкая картинка «съедала» расфокус — он читался
  слабым. Теперь резкий слой гаснет (`1 - amount`), размытый проявляется.
  Оба слоя под `RepaintBoundary`: сигма постоянна, при прокрутке меняется
  только прозрачность, растры берутся из кэша.
- **Обводка карточки статистики — ОДНА.** `_ringedCard` рисует градиентное
  кольцо; `Card` внутри с ненулевым `elevation` добавлял ВТОРОЙ край, и кант
  читался жирным. У карточек статистики `elevation: 0`; внутренние канты
  мотивационной карточки — волосяные (0.6–0.8).
- **Лист с встроенной клавиатурой — под `RepaintBoundary`.** Листы профиля
  («Добавить друга», «Очки», действия над другом) изолированы: перерисовка
  клавиатуры не тянет весь экран. Строки действий («Очки»/«Удалить») обязаны
  иметь отдачу (`PressScale`) — раньше тап срабатывал без отклика.
- **Смена шага листа (действия → очки) — сразу, плавность несёт переход.**
  Искусственная пауза перед сменой контента (`Future.delayed` в `_pressThen`)
  только добавляла лаг между пальцем и откликом. Плавность даёт сам
  `AnimatedSwitcher` (`SlideTransition` + fade на `Motion.emphasized` —
  нулевая скорость на обоих концах) плюс `AnimatedSize` вокруг.
- **`BackdropFilter` под анимацией появления/ухода «мигает».** Размытие
  пересобирается каждый кадр, пока идёт transition, и окно/плашка мерцает.
  В окне подтверждения обновления (`_UpdateConfirmDialog`) и в снекбаре
  стекло делается БЕЗ размытия: полупрозрачная подложка
  (`surfaceContainerHigh`/`primaryContainer`, alpha ≈ 0.9/0.78) — тот же вид,
  но без пересборки фильтра. Прозрачность даёт «стекло», плавность — чистая
  отрисовка.
- **Таблетка-бейдж с градиентным кольцом: закладывай толщину кольца в
  размер.** Кольцо — внешний `Container` с `padding: 1`; если ширину/высоту
  считать только по контенту, содержимое сжимается на 2 px. Размер
  прибавляем на двойную толщину канта.
- **Кант окна обновления — ПОЛУПРОЗРАЧНЫЙ КРАСНЫЙ бренда, как у клавиатуры.**
  Градиент `primary → tertiary` на дефолтной палитре уходил в сиреневый и
  выбивал окно из «кровавой» семьи. Теперь кромка — один алый тон
  (`BrandColors.red`, alpha 0.22…0.55 по периметру), а подложка — красный
  отлив через `Color.alphaBlend`, ровно как панель ввода (`InlineKeyboard`).
- **Фирменный алый — один источник: `BrandColors.red` в `design_tokens.dart`.**
  До этого `0xFFE0192F` был скопирован в трёх файлах (клавиатура, пятна FAB,
  кольцо музыки) — правка тона требовала синхронных изменений. Все они теперь
  ссылаются на константу.
- **Значок Agysha «зайчик» — СВОЙ векторный глиф, а не шрифтовая иконка.**
  `lib/widgets/agysha_bunny.dart`: силуэт описан нормированно (0…1) и потому
  чётко ложится и на 18 px таблетки, и на 22 px медальона окна. Системные
  `Icons.system_update_alt`/`Icons.cruelty_free` читались чужеродно, а стрелка
  в мелком размере сливалась в пятно. Общий глиф для таблетки и окна — одна
  рецептура, а не две похожие картинки.
- **Живой зайчик — `AnimatedBunny`, а не покадровая перерисовка.** Глиф
  [AgyshaBunny] рисуется ОДИН раз в постоянный слой (`RepaintBoundary`), а
  кадры анимации лишь переносят готовый растр: `Transform.translate` (подскок)
  и `Transform.scale` (лёгкое растяжение на отрыве / сплющивание на посадке).
  Кривые за кадр не пересобираются — именно на этом раньше «лагало» вечное
  «дыхание». Цикл — `sin(π·x)` внутри фазы подскока: значение И производная
  нулевые на обоих концах, стык витков без рывка; фаза покоя даёт мягкое
  «дыхание». Подскок регистрируется через `ambientRepeat` (миксин
  `MotionAwareRepeat`) и гаснет на «убрать анимации».
- **Вход значка уважает «убрать анимации» НЕ пропуском, а завершённым
  контроллером.** `_enter` создаётся с `value: MotionPrefs.shouldReduceMotion ?
  1 : 0`: при выключенном движении `_enter.forward()` не вызывается, и если
  оставить контроллер на нуле, зайчик остаётся полностью прозрачным. Проверено
  виджет-тестом «при «убрать анимации» зайчик остаётся видимым».
- **Пятна «кровью» — одна рецептура на обе фирменные FAB.** `BloodSpecks`
  (бывш. `_PlusSpeckPainter`) теперь публичен и стоит и на «плюсе», и на
  Аде (`intensity: 0.6` — «чуть крови», чтобы аватарка не тонула в кляксах).
  Геометрия СТАТИЧНА: нажатие лишь углубляет цвет, пятна не растут.
- **Кольцо музыки: ОДИН шейдер на кадр.** Три `createShader` за кадр
  (свечение + линия) читались лагом пульса на слабом GPU. Теперь градиент
  строится один раз, а прозрачность слоёв даёт `ColorFilter.modulate`.
  На паузе пульс не обрывается кадром: `Timer(_fade)` даёт гаснущему кольцу
  дожить фейд, и только потом `_ctrl.stop()`.
- **Очки рейтинга меняются ПО БУКВАМ, как поле очков.** `SmoothDigits`
  (`lib/widgets/smooth_digits.dart`) оборачивает `SmoothTyping`: цифра
  проявляется из прозрачного, старая гаснет. Барабан `AnimatedCounter`
  читался грубым подменом. `sample` держит ширину — при «99 → 100» строка
  не дёргается по горизонтали.
- **`MaskFilter.blur` на Impeller размывает ПРЯМОУГОЛЬНИК слоя.** Круглая
  обводка со свечением через `MaskFilter.blur` давала вокруг кольца
  светящуюся КВАДРАТНУЮ кромку (видно на устройстве, в software-рендере
  теста — чисто). Мягкость делаем второй, более широкой полупрозрачной
  обводкой (`strokeWidth = stroke * 3.2`), без `MaskFilter`. Тест-регресс —
  `test/polish_round_fourteen_test.dart` (углы окна без цвета, кромка цветная).
- **Кольцо со свечением — отступ на ПОЛНУЮ ширину свечения.** Радиус
  считаем `min(w,h)/2 - stroke * 1.6`, иначе широкая обводка выходит за окно
  виджета и её режет соседний клип.
- **Цвета долей столбчатого графика — из РАЗНЫХ ролей темы.** В Material
  You `secondary` почти сливается с `primary`: две доли столбика читались
  одним пятном («непонятно, что нарисовано»). Привычки — `primary`, задачи
  — `tertiary`; контур столбика — волосяной (`strokeWidth 0.5`), иначе
  частокол из 1 px линий выглядел жирным.
- **Полоса прогресса — ровная заливка, без тёмных краёв.** Градиент с
  затемнёнными концами читался грязным пятном и спорил с тонкой обводкой
  карточки; один тон акцента с еле заметным световым швом справа — монотонно
  и чисто.
- **Обводка карточек статистики — действительно волосяная.** `_hairline`
  снижен до 0.45 (было 0.6): на плотности 3× кант всё ещё виден, но уже не
  «толстый». Толстая (1.6) — только у сводки общего прогресса.
- **Отдача кнопок — не забывать на НОВЫХ экранах.** `PressScale` вокруг
  `FilledButton`/`OutlinedButton`/ячейки; окно пробуждения долго был
  единственным экраном без отдачи (палец нажимал — кнопка не двигалась).
- **`Matrix4.getMaxScaleOnAxis()` в тестах отдачи бесполезен.** У
  `Transform.scale` ось Z остаётся единичной, поэтому максимум ВСЕГДА 1.0 —
  проверка «кнопка уменьшилась» молча проходит на сломанном коде. Читать
  масштаб по X: `transform.entry(0, 0)` (см. `test/wake_task_press_test.dart`).
- **Анимацию отдачи проверять на середине, а не на конце.** `PressScale` в
  окне пробуждения вдавливается за 160 мс; `pump(200 мс)` дожидается конца
  анимации, и масштаб снова 1.0. Гнать кадры до половины длительности.
- **`SmoothDigits` рисует число без `TextField`.** Раньше внутри лежало
  невидимое поле ввода ради совпадения метрик со шрифтом поля. Для ЧИСЛА это
  вредно: скрытое поле попадало в `find.byType(TextField)` и сдвигало выбор
  настоящих полей в тестах (питание: «калории» уезжали на другое поле, тест
  падал на `'0' != '500'`). Теперь разряды — обычные `Text` в `Row` с
  `AnimatedSwitcher` на каждый разряд; ключ считается ОТ ПРАВОГО края
  (`digit_<last - i>`), поэтому при «500 → 1500» анимируется только новый
  старший разряд.
- **Свечение кольца музыки — радиальное затухание, а не «слоёный бублик».**
  Одна широкая обводка (`strokeWidth = stroke * 3.2`) с `RadialGradient`
  (альфа 0 → пик на середине полосы → 0) даёт мягкие края без резкой
  окружности; `SweepGradient` задаёт перелив тона, оба шейдера строятся по
  разу за кадр. `MaskFilter` не возвращать (квадратная кромка на Impeller).
  Регресс — `test/polish_round_twelve_test.dart` / `_fourteen_test.dart` /
  `_sixteen_test.dart` (ровно 2 `createShader` и 2 `drawCircle`).
- **Переход «пусто ↔ история» не выбрасывает уходящего ребёнка.** Прежний
  `layoutBuilder: (c, p) => Stack(children: [?c])` ронял уходящего кадром, и
  подпись «Пока нет приёмов пищи» мигала. Держим уходящего ПОД текущим и
  схлопываем по высоте (`ClipRect` + `Align(heightFactor: animation.value)`),
  кривая ухода — `easeOutQuad` (гаснет быстрее, чем растут строки).
- **Комментарии-кракозябры («РјРµС…Р°РЅРёР·Рј») чинить, а не оставлять.**
  В `nutrition_screen.dart` при прошлых правках UTF-8-текст писался поверх
  cp1251-байтов: `вЂ”`, `В·`, целые фразы. Читается как «иероглиф» и путает
  следующий проход. Ловить так: строка содержит `Р`/`С` + кириллица подряд и
  декодируется в осмысленный русский через `latin1`/`cp1251`.
- **Кнопки в `AlertDialog` тоже несут `PressScale`.** Диалог удаления приёма
  пищи был единственным окном без отдачи — «Отмена»/«Удалить» не отвечали на
  палец.
- **Ключ `AnimatedSwitcher` обязан стоять на ПРЯМОМ ребёнке — и различаться.**
  В питании ребёнок всегда был `KeyedSubtree('meals_history')`, поэтому
  переключатель видел «того же ребёнка» и переход «пусто ↔ история» шёл одним
  кадром. Ключи `meals_empty` / `meals_history` теперь на самом содержимом
  (`_buildHistory` возвращает keyed-поддерево). Тот же класс ошибки, что и с
  аватаркой (см. выше).
- **`CustomPainter.shouldRepaint` по ссылке = перерисовка каждый раз.**
  `_DaysBarPainter` сравнивал `old.days != days`, а `lastDays(30)` возвращал
  НОВЫЙ список на каждой пересборке — график из 30 столбиков перерисовывался
  даже когда менялась одна надпись. Список кэшируется (`_recomputeMonth` в
  `_onData`) и сравнивается по содержимому (`listEquals`), а `DayCompletion`
  получил `==`/`hashCode`.
- **Первую запись в ПУСТОЙ истории не растим из нуля.** Пустая подпись выше,
  чем «заголовок дня + карточка нулевой высоты»: блок сначала проседал, потом
  рос — читалось рывком. Переход целиком ведёт `AnimatedSwitcher` + `AnimatedSize`
  (`_grownFromEmptyId` отключает `_GrowIntoPlace`).
- **Заголовок не делит строку с бейджем, если он «главный».** В окне ивента
  заголовок ужимался бейджем «3 / 12» до мелочи; теперь заголовок занимает всю
  строку, а день живёт ТОЛЬКО в бейдже (из `nyEventBody` убран `{0}` — дубль
  «День 3 из 12» под бейджем).
- **Акцент «своей» кнопки брать от бренда, а не `cs.primary`.** На дефолтной
  палитре `primary` сиреневый, и «Забрать» в кровавой карточке ивента читалась
  синей заглушкой. Так же в окне сброса. Тон темы лишь подмешивается
  (`Color.lerp(BrandColors.red, cs.primary, 0.18)`).
- **Два `AnimationController` — `TickerProviderStateMixin`, не `Single…`.**
  Второй `vsync` на одиночном провайдере роняет сборку («multiple tickers»).
- **Зажатие кнопки — ОДНА кривая на входе и отпускании.** `easeOutCubic` за
  150 мс читался щелчком; `easeInOut` за 210 мс — ровное монотонное движение.

## Списки: полки, цвета секций и похвала

- **Цвета секций — один источник правды.** `lib/utils/section_tints.dart`:
  «Полезные» (привычки) и активные задачи — ОДИН светло-зелёный
  (`SectionTints.active`, `_activeLight`), архивная полка задач — приглушённый
  сине-серый (`completed`), «Вредные» — красный (`harmful`). Цвета адаптивны к теме
  (на тёмном фоне берётся осветлённый оттенок). Не заводите свой `Colors.green`
  в отдельном экране — разделы сразу читаются как из разных приложений.
  Контраст заголовков к фону стережёт `test/task_shelves_test.dart` (WCAG AA).
- **Заголовки секций — только текст.** У «Архивные»/«Полезные»/«Вредные» нет
  линии-разделителя (`Divider` убран): он читался как случайная полоса.
  ВОЗВРАЩАТЬ `Divider` не нужно — это уже пробовали и откатили.
- **Активные задачи — без заголовка.** Они и есть основной список, подпись
  «Активные» подписывала очевидное. Заголовок несёт только архивная полка
  («Архивные» / Archived / Archivées, ключ `tasksSectionDone`); ключ
  `tasksSectionActive` убран за ненадобностью.
- **Архивная полка появляется и сворачивается плавно.** Первая выполненная
  задача рождает полку; чтобы список не «щёлкал», появление ведёт `_splitReveal`
  (фейд через `SliverFadeTransition` + растущий зазор, заголовок И сами карточки
  через `SizeTransition` — высота полки набирается плавно, а не кадром).
  Длительность 460 мс, кривая `easeInOutCubic` (нулевая скорость на обоих
  концах — нет «толчка»). `reveal` прокидывается в `_taskSliver` параметром;
  ключ элемента (`ValueKey('item_task_<id>')`) обязан остаться на САМОМ внешнем
  узле — `SliverReorderableList` падает с «All list items must have a key»,
  если ключ «съедает» обёртка. Видимость полки — флаг `_archiveVisible`, а НЕ «done не
  пуст»: когда уходит последняя архивная задача, полку надо успеть свернуть.
  Переходы ловит слушатель сервиса `_syncArchive` (снятие галки, удаление
  свайпом — любое изменение списка), а не только тап по галке.
- **Галка задачи снимается.** Повторный тап по выполненной задаче возвращает
  её из архива в активный список (в `TaskService.toggle` это просто `!done`).
  Похвалу Ады выдаём только за ОТМЕТКУ (`wasDone`), не за снятие.
- **Переезд карточки читается как движение.** Только что отмеченная задача
  «приезжает» на полку выполненных (420 мс): `_cardDrop` даёт съезд сверху
  (`_cardDropSlide`, доля высоты карточки — не пиксели, чтобы не читать
  `.value` в `build`) + фейд + `SizeTransition`. Метка `_justCompletedId`
  снимается в `whenComplete`, чтобы лишние слои не висели на карточке всегда.
- **Похвала за задачу — одна строка и разная.** `AiGuideService.taskDoneLine`
  чередует варианты по индексу в prefs (соседние отметки не повторяются),
  круглые вехи (5/10/25/50/100…) дают особую строку. Одна строка — требование
  к снекбару (без переносов). Регресс-тест — группа «Похвала за выполненную
  задачу» в `test/services_test.dart`.
- **Нормализация привычек — на ЛЮБОМ входе.** `HabitService._normalizeForToday`
  обязана пройти не только `load`/`toggle`/`normalizeIfDayChanged`, но и
  `add()`/`update()`: иначе привычка, записанная формой/импортом/Аdой, хранит
  «мёртвый» стрик (пропущенный день), который схлопывается лишь при следующем
  `load` — «одни счётчики сбросились, другие нет». Побочный эффект: фикстура
  вида `Habit(streak: 10)` без `lastDoneDate` теперь честно обнуляется при
  `add()` (это «мёртвые данные») — в тестах задавайте живой стрик через
  `doneToday: true` + `lastDoneDate: HabitService.mskToday()`.

## Доступность

- У кастомного `VolumetricSwitch` есть `semanticLabel` — задаём для важных
  настроек. `SmoothTooltip` кладёт свою подпись в дерево доступности как
  `Semantics(tooltip:)`, поэтому значки шапки (обновить/статистика/настройки)
  озвучиваются, а не читаются как «кнопка». `tooltip`, а не `label` — чтобы
  не дублировать подпись там, где у ребёнка уже есть текст/`Semantics.label`.

## Звуковой дизайн

- `lib/services/sounds.dart` — `Sounds` парный к `Haptics`: там тактильная
  отдача, здесь короткий штатный `SystemSound` (`click`). Свои WAV-ассеты НЕ
  нужны: `SystemSound` мгновенен, вписан в системную громкость «касаний».
- **Выключены по умолчанию** (`Sounds.enabled = false`) — звук навязчивее
  вибрации, его включает сам человек. Флаг читается ДО первого кадра
  (`main.dart`, `Future.wait`), иначе отклик успеет прозвучать до применения
  настройки. Тумблер — в настройках рядом с вибрацией (`settings_screen.dart`),
  ключ `setting_sounds` в `SettingsService`.
- Звук — только подтверждения (отметка задачи/привычки/проверки реальности,
  само включение тумблера). Будильники и уведомления идут своим громким
  каналом (`NotificationService`) — `Sounds` туда не лезет.
- Тест звуков: `SystemSound` шлёт `SystemSound.play` на `flutter/platform` с
  **JSON-кодеком**, поэтому `setMockMethodCallHandler` его «портит»
  (`FormatException: Message corrupted`). Перехват — только бинарный:
  `setMockMessageHandler(SystemChannels.platform.name, …)` с
  `platformChannel.codec.decodeMethodCall(...)` (см. `preferences_test.dart`).

## Профиль «Agysha-юзера»

- Экран — `lib/screens/profile_screen.dart`, состояние — `lib/services/profile_service.dart`
  (синглтон-`ChangeNotifier`), аватарки — `lib/widgets/profile_avatar.dart`
  (индекс варианта стабилен, поэтому друг не «перекрашивается» между запусками).
  Аватарки — «стеклянный» красный шар: мягкий `RadialGradient` (светлое пятно
  сверху-слева), чистая обводка, значок варианта и два белых блика-«зайчика».
  Смена варианта — плавный кросс-фейд со «проявлением» (`AnimatedSwitcher`
  с `ScaleTransition`), а не подмена кадром; обводка выбора в пикерах —
  `AnimatedContainer`. Глубокое свечение (glow) в шапке профиля не возвращать:
  оно уже ловило блик.
- Профиль (имя, аватарка, друзья, музыка) читается в общем стартовом
  `Future.wait` (`main.dart`), как остальные сервисы. Онлайн-статус вынесен
  ОТДЕЛЬНЫМ ключом в `SharedPreferences` (`profile_online`), потому что его
  читают и шапка (`OnlineDot`), и экран профиля, и он не должен тянуть разбор
  всего файла профиля.
- Кружок онлайна (`lib/widgets/online_dot.dart`) в шапке стоит СПРАВА от
  ПОСЛЕДНЕЙ буквы заголовка, почти вплотную, по СЕРЕДИНЕ её высоты (не над
  буквой — «слишком высоко» уже отклонено). Позиция считается по реальной
  геометрии текста (`TextPainter.getBoxesForSelection`): `dotCx =
  lastGlyph.right + _gapX`, `dotCy = lastGlyph.center.dy`. `Stack` хит-тестит
  только внутри своих границ, поэтому рамка заголовка раздута на недостающие
  поля по всем четырём сторонам (`padTop`/`padBottom`/`padRight`), а текст
  сдвинут на ту же величину. Новогодняя шапка убрана. Если в профиле сохранено
  короткое имя, вместо «Agysha» показывается оно — плавным `AnimatedSwitcher`
  (520 мс, `AnimatedBlurTitle` слушает `ProfileService`).
- Смена статуса кружка (красный ↔ пустой) идёт ПЛАВНО и МЕДЛЕННО (640 мс,
  `AnimatedContainer` + `AnimatedScale`), «пустой» — прозрачная середина с
  тонким кольцом. При зажатии кружок мягко «вдавливается» (`PressScale`), фон
  тапа подсвечивается со СКРУГЛЕНИЕМ, а не квадратом. Учитывает
  `MotionPrefs.shouldReduceMotion` (при «убрать анимации» — мгновенно).
- В шапке профиля кружок стоит СЛЕВА от имени (тап переключает статус), строки
  «В сети / Не в сети» нет. Зона тапа кружка (30 px) шире глифа, поэтому пару
  «кружок + имя» сдвигаем на её «свес» (`_dotOverhang`), чтобы по центру
  карточки осталось имя. Зазор между кружком и именем минимальный (1 px).
  Без имени в шапке показывается «Аноним» (ключ `profileAnonymous`) — это уже
  пробовали менять на «Как вас звать?» и откатили; приглашение «Как вас звать?»
  живёт ТОЛЬКО в поле ввода (`profileNameHint`, hint поля). Смена имени —
  плавный `AnimatedSwitcher`.
- Поля профиля (имя, имя друга, очки) — как остальные поля приложения:
  `SmoothTyping` (плавные буквы), `magnifierConfiguration: disabled`, короткое
  `minimalContextMenuBuilder`, плоская заливка без рамки
  (`_fieldDecoration`).
- **Короткое имя — максимум 10 символов** (`ProfileService.maxNameLength`).
  Поле ввода обрезает набор через `LengthLimitingTextInputFormatter`, счётчик
  под полем скрыт (`counterText: ''`), а сервис режет имя и сам (на случай
  прихода извне). Пробелы по краям снимаются.
- Кнопки профиля — капсульные (`_roundButtonStyle`, `StadiumBorder`) в тоне
  `FilledButton.tonal` и с отдачей `PressScale`, как кнопки настроек.
- **Система очков «Agysha-рейтинг»** — `lib/services/score_service.dart`
  (синглтон-`ChangeNotifier`). Копилка ПОЖИЗНЕННАЯ: очки только прибавляются
  и НЕ отбираются при снятии галочки или потере стрика — иначе цифра ничего
  не значит. Счёт ведётся ПО КАТЕГОРИЯМ (`ScoreKind`: привычка, задача, Ада,
  приём пищи, проверка реальности, активный день), веса — в `ScoreWeight`.
  Начисление подключено в сервисах действий (`habit_service` на toggle→done,
  `task_service` на переход в done, `ai_guide_service` на сообщение Аде,
  `nutrition_service.add`, `reality_check_service`). Активный день —
  `markActiveDay()`: один раз в сутки, защита ключом дня от «фарма» тапами.
  Загрузка — в общем стартовом `Future.wait` (`main.dart`).
- Рейтинг — локальный: свой счёт (`ProfileService.localScore()`) = копилка
  `ScoreService().total` + текущие стрики привычек + выполненные задачи +
  бонус за активные дни; друзья добавляются вручную. Общего сервера у приложения
  нет, поэтому «онлайн»-рейтинг пока локальный; сеть нужна только для
  открытия событий в браузере (`url_launcher`).
- `_Card` в профиле — это `Material`, а не голый `DecoratedBox`: `ListTile`
  рисует чернильные волны на ближайшем `Material`, иначе Flutter роняет
  assertion «ListTile background color or ink splashes may be invisible».
- Своя музыка копируется в приватную папку (`getApplicationDocumentsDirectory()
  /sounds`) — путь из общего хранилища/кэша переживёт не всякий день. Играет
  через общий сервис `lib/services/music_service.dart` (`MusicService`,
  синглтон): плеер живёт вне экрана, поэтому уход с профиля НЕ обрывает трек.
  Зациклено всегда (`ReleaseMode.loop`).
- **Музыка профиля — подборка до 15 треков** (`ProfileService.maxTracks`),
  модель `MusicTrack` (id, path, title, addedAt). Старое одиночное поле
  `musicPath`/`musicTitle` читается как подборка из одного трека (обратная
  совместимость) и дублируется при сохранении — мини-плеер не сломался.
  Подписи треков — не имена файлов, а «человеческие» названия из пула
  (`_funSongTitle`); пул большой, а имя трека ещё и замешивается хвостом
  (` · live`, ` (nocturne)`…), чтобы у двух разных звуков почти никогда не
  выходила одна подпись. Повтор того же ФАЙЛА не добавляется: экран считает
  SHA-256 содержимого и зовёт `hasTrackWithFingerprint` (`crypto` в
  зависимостях) — сравнение по байтам, а не по имени файла.
  `MusicPulseRing` — НЕ переливающееся кольцо: от кнопки расходятся
  монотонные волны (одна краска, только радиус и альфа), тонкая опорная
  кромка держит пульс между волнами. Никаких `MaskFilter` и `SweepGradient`. Карточка музыки: переход «пусто ↔ подборка» тянет ОДИН
  `AnimatedSize` (высота) + `AnimatedSwitcher` (проявка), строки — `_TrackRow`
  с пульсирующим кольцом; добавление «врастает», удаление схлопывается
  (`_removingTrackIds`). На пределе кнопка «Добавить» гаснет.
- Кнопка-действие листа (например, «Добавить» в листе друга) ВСТРОЕНА в
  `InlineKeyboard` (`actionLabel`/`onAction`) акцентной клавишей, а не висит
  отдельной кнопкой над панелью. В нижнем ряду букв стоит КЛАВИША-РЕГИСТР
  (`⇧`, одноразовая: заглавная уходит и клавиша гаснет) — второй «стереть»
  там читался ошибкой раскладки, а заглавную букву набрать было нельзя.
- Питание живёт в том же стиле, что привычки и задачи: свайп влево удаляет
  (красная плашка), долгое нажатие закрепляет/снимает закреп. История и
  строка приёма пищи идут под ОДНИМ `AnimatedSize`; у `SwipeToDelete` есть
  `resizeDuration: null`, чтобы высоту тянул только внешний `AnimatedSize`
  (иначе две анимации высоты спорили и строка «прыгала»).
- Тест экрана профиля не делает файловый I/O внутри `testWidgets`
  (fake-async виснет): профиль читается в `setUp` (настоящая async-зона), а
  сам виджет-тест только рендерит и скроллит.

## Публикация в F-Droid / IzzyOnDroid

Полная инструкция — `docs/publishing-fdroid.md`. Ключевое, чтобы не наступать
на грабли повторно:

- **Рецепт сборки** лежит в `fdroid/metadata/com.wetcorp.agysha.yml`. Это
  копия того, что уходит в MR в `fdroid/fdroiddata`; структуру проверить можно
  `python3 -c "from fdroidserver import metadata; ..."` или `fdroid lint` внутри
  клона fdroiddata (в пустом каталоге lint ругается на категории — конфиг пуст).
- **F-Droid собирает универсальный APK** (`build/app/outputs/flutter-apk/app-release.apk`),
  а не `--split-per-abi`. Причина: Flutter при сплите прибавляет к `versionCode`
  `1000 * индекс ABI` (arm=1000, arm64=2000, x64=4000 — см.
  `FlutterPluginConstants.ABI_VERSION`), и APK перестаёт совпадать по номеру с
  тем, что ждёт F-Droid. Универсальный APK сохраняет `versionCode` из pubspec.
- **`flutter.sdk` в `android/local.properties`.** `android/settings.gradle.kts`
  читает его и падает без него. `flutter build` пишет файл сам, но F-Droid-сборке
  безопаснее добавить явно: `echo "flutter.sdk=$$flutter$$" >> android/local.properties`
  в prebuild.
- **Подпись — руками НЕ трогать.** `android/app/build.gradle.kts` жёстко
  ссылается на `signingConfigs.getByName("release")` и без `key.properties`
  упал бы на `:app:packageRelease`. Но fdroidserver сам вызывает
  `common.remove_signing_keys()` в `prepare_source` — это происходит ДО
  `prebuild`, и он вырезает и блок `signingConfigs { ... }`, и строку
  `signingConfig = ...` (проверено на этом `.kts`: сносит обе). После этого
  release собирается неподписанным, а F-Droid подписывает APK своим ключом.
  Никакой `sed` с подменой на debug в рецепте не нужен — раньше он был и
  оказался лишним. `remove_signing_keys` понимает и Groovy, и Kotlin DSL.
- **Снятие `REQUEST_INSTALL_PACKAGES`.** Разрешение объявлено в манифесте ради
  самообновления, а в F-Droid-сборке оно выключено — оставлять его нельзя
  (F-Droid помечает как «не используемое» и просит убрать). Рецепт вырезает
  строку в prebuild: `sed -i -e '/REQUEST_INSTALL_PACKAGES/d'
  android/app/src/main/AndroidManifest.xml`.
- **Память Gradle.** `android/gradle.properties` подогнан под домашнюю машину
  (`-Xmx1024m`, `workers.max=1`) — на buildserver этого мало, `assembleRelease`
  умирает с «JVM garbage collector is thrashing» (та же болезнь, что ловили в
  CI, см. «Память Gradle»). Рецепт в prebuild поднимает значения ровно как
  CI-шаг: `jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:ReservedCodeCacheSize=256m
  -XX:+UseParallelGC`, `workers.max=4`, `kotlin.daemon.jvmargs=-Xmx1g`. Дефолт
  buildserver — 1 CPU / 2048 MB; трёхпроходный ретрай с меньшим heap спасает не
  всегда, поэтому подъём обязателен.
- **Build-tools и platform.** AGP 9.1.1 по умолчанию требует build-tools
  **36.0.0** (не 33!) и `compileSdk 37` → нужен `platforms;android-37.0`.
  В образе buildserver предустановлены только до `build-tools;33.0.0` и
  `platforms;android-33`, поэтому prebuild обязан звать `sdkmanager
  "platforms;android-37.0" "build-tools;36.0.0"`. Имена пакетов — именно с
  `.0` у платформы (в fdroiddata так у 105 рецептов).
- **Java на buildserver.** Образ на Debian trixie, `default-jdk-headless` =
  **openjdk-21**. AGP 9 требует Java 17+ → `sudo` с установкой JDK в рецепте НЕ
  нужен (в отличие от старых рецептов с `apt-get install openjdk-21`).
- **Самообновление выключено в F-Droid-сборке** через
  `--dart-define=AGYSHA_NO_SELF_UPDATE=true` → `kSelfUpdateEnabled = false`.
  Флаг обязан гасить ОБА места: таблетку обновления в Настройках И тихую
  ежедневную проверку `UpdateService.instance.silentDailyCheck()` в `main.dart`.
  Забыть второе легко — тогда F-Droid-сборка молча ходит в GitHub API.
- **AntiFeature `NonFreeNet`.** Ада ходит к сторонним бесплатным LLM-провайдерам
  (OpenRouter, Poolside и др. в `lib/services/ai_guide_service.dart`). F-Droid
  это допускает как Anti-Feature (предупреждение), но не блокирует включение.
- **IzzyOnDroid приложение с Адой НЕ примет.** Их App Inclusion Policy прямо
  запрещает фронтенды к LLM и «vibe-coded» приложения. Раздают они бинарники
  разработчика, так что для подачи туда нужна отдельная сборка БЕЗ Ады. Начинать
  с IzzyOnDroid бессмысленно — сначала F-Droid.
- **Fastlane-метаданные** в `fastlane/metadata/android/{en-US,ru,fr}/`: title,
  short_description, full_description, icon (512×512), phoneScreenshots,
  changelogs/`<versionCode>`. Их читают и F-Droid, и IzzyOnDroid. Лимиты:
  `short_description` ≤ 80 символов и БЕЗ точки в конце, changelog ≤ 500.
- **Порядок подачи.** Рецепт обязан указывать `commit:` на коммит, где уже есть
  и `fastlane/`, и флаг `AGYSHA_NO_SELF_UPDATE` в `update_service.dart` —
  иначе сборка выйдет со старым кодом. Такой коммит — обычный пуш в `main`:
  он же триггерит `ship.yml`, который бампает версию и выпускает релиз. Поэтому
  порядок такой: (1) коммит с `fastlane/` + флагом уходит в `main`; (2) рецепт
  указывает на него и на актуальные `versionName`/`versionCode`; (3) копия
  рецепта — MR в `fdroiddata`. Нельзя ссылаться на коммит, которого нет на
  GitHub: F-Droid клонирует именно его.
- **Changelog обязан лежать в коммите рецепта, а не просто в репозитории.**
  Тег указывает на коммит `release: v…`, и раньше в него не попадал
  `fastlane/metadata/android/en-US/changelogs/<versionCode>.txt` (коммит трогал
  только `pubspec.yaml` и `app_version.dart`) — на стороне fdroiddata «Что
  нового» было пустым. Теперь `ship.yml` шагом «Changelog для F-Droid»
  генерирует файл из тех же коммитов, что и заметки релиза, и коммитит его
  вместе с бампом; уже написанный автором файл не перетирается. Проверка:
  `git ls-tree -r --name-only <tag>` должен содержать `changelogs/<versionCode>.txt`.
- **Служебные коммиты в changelog не попадают.** Заметки релиза и fastlane-файл
  собираются из заголовков коммитов, и туда утекали «F-Droid: рецепт на тег…»,
  «docs(AGENTS): …», «ship: …» — пользователь в «Что нового» видел внутреннюю
  кухню. Фильтр вынесен в `tool/release_notes.sh` (отбрасывает префиксы
  F-Droid/fdroid/ship/release/Документация/Переименование и conventional
  docs/chore/ci/style/test/build/refactor), `ship.yml` гоняет его и для заметок,
  и для changelog. Покрыто `test/release_notes_test.dart`: он запускает скрипт
  на реальных заголовках и отдельно проверяет, что ни в одном уже лежащем
  changelog нет служебных пунктов. Правило: если коммит не меняет поведение
  приложения для пользователя — его заголовок не должен попадать в «Что нового».
- **Рецепт указывает на тег релиза, а не на коммит после него.** У `v1.6.171+45243`
  тег стоял на `2c1156d` (F-Droid-коммит), а сам релизный коммит `3568f6b`
  лежал ниже. Для F-Droid это неважно (changelog в дереве тега есть), но
  `UpdateCheckMode: Tags` берёт версию из последнего тега — поэтому рецепт и
  `CurrentVersion*` держать на версии, которая в этом теге действительно есть.
- **`fdroid rewritemeta` — жёсткий гейт CI.** В fdroiddata есть job
  `fdroid rewritemeta`, который переформатирует файл и требует НУЛЕВОЙ diff.
  Поэтому рецепт держать строго в каноническом виде: ключи верхнего уровня
  отсортированы (`AntiFeatures` идёт ПЕРВЫМ, затем `Categories`, `License`,
  `AuthorName`, `SourceCode`, `IssueTracker`, `Changelog`), `UpdateCheckMode`
  без кавычек, длинные строки автопереносятся с отступом. Проверить локально:
  `python3 -c "from fdroidserver import metadata,rewritemeta as rw;
  print(rw.proper_format(metadata.parse_metadata('metadata/com.wetcorp.agysha.yml')))"`
  — должно быть `True`.
- **`fdroid checkupdates --auto` тоже гейт.** Job прогоняет автообновление и
  падает, если появился diff. Значит `UpdateCheckData` и `AutoUpdateMode:
  Version` должны РЕАЛЬНО резолвить версию из тегов, а `CurrentVersion`/
  `CurrentVersionCode` — совпадать с последним тегом. Проверено на настоящих
  тегах: `Tags ^v[0-9.]+\+[0-9]+$` + `UpdateCheckData: pubspec.yaml|
  version:\s.+\+(\d+)|.|version:\s(.+)\+` дают актуальную версию из последнего тега.
- **`fdroid lint` — тоже гейт** (см. выше про категории: в пустом каталоге он
  ругается, потому что `config.yml` без `categories`). В клоне fdroiddata
  проходит без замечаний.
- **Скриншоты** рисуются из кода: `flutter test tool/screenshots/render_screenshots.dart`
  (в CI не гоняется). Складывает PNG в `docs/screenshots/` и
  `fastlane/.../phoneScreenshots/`.
- **Готовый текст заявки** — в `docs/publishing-fdroid.md`, раздел «Готовый
  пакет подачи»: вариант A (RFP-issue в `fdroid/rfp`) и вариант B (сразу MR).
  Точный отправленный текст RFP лежит в `fdroid/rfp-issue-body.md`.
  Подача MR требует ЛИЧНОГО аккаунта GitLab (`wxstdo`): проектный токен-бот
  (`project_…_bot_…`, как в зеркале ниже) форк `fdroid/fdroiddata` создать не
  может — GitLab отвечает `409 Namespace is not valid` на форк и `403` на
  ветку/MR. Бот МОЖЕТ открыть issue в `fdroid/rfp` (заявка #4794; `403`
  только на удаление чужого issue — вместо удаления закрывать через
  `state_event=close`).
  Оба шага уже сделаны: RFP #4794 и MR fdroiddata!57343.
  Грабли подачи MR (проверено): (1) MR надо создавать через эндпоинт ФОРКА
  `POST /projects/<fork_id>/merge_requests` с `target_project_id=36528` —
  тот же POST в проект `36528` отдаёт `403`; (2) файл заливать по API
  (`POST /repository/files/...` с base64) — клонировать fdroiddata ради
  одного файла не нужно, репо огромный; (3) пайплайны в форке «падают» без
  джобов — раннеров нет, CI гоняет сторона F-Droid; (4) метку `New App`
  из-под непривилегированного аккаунта не поставить, её вешает мейнтейнер;
  (5) реальный шаблон MR — `.gitlab/merge_request_templates/Default.md`
  (не `New App.md`, такого файла в fdroiddata нет).
- **Зеркало на GitLab.** Репозиторий зеркалируется в приватный
  `https://gitlab.com/wxstdo/keramika` (тот же код, имя проекта осталось
  «keramika»). `main` там защищена от force-push: чтобы залить разошедшуюся
  историю, надо временно снять защиту (`DELETE /projects/:id/protected_branches/main`),
  сделать `git push --force`, затем вернуть её
  (`POST ... name=main&push_access_level=40&merge_access_level=40&allow_force_push=false`).
  Теги и ветки заливать обычным `git push gitlab --all` + `git push gitlab --tags`.


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
