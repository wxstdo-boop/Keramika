# Сборка и разработка

## Что нужно

| Инструмент | Версия |
|---|---|
| Flutter | 3.35 или новее (проверено на 3.35) |
| Dart | 3.12+ (тянется из Flutter) |
| JDK | 17 или 21 |
| Android SDK | compileSdk **36** |
| Android device | API 26+ (Android 8.0) |

Проверить окружение:

```bash
flutter doctor
flutter --version
```

## Зависимости

```bash
flutter pub get
```

Два плагина берутся не из pub, а из локальных форков в `third_party/`:

| Плагин | Почему форк |
|---|---|
| `flutter_overlay_window` | Публичная версия не регистрирует плагины (`shared_preferences`, `path_provider`) внутри оверлейного движка. Без этого в мини-окошке Ады пустая история и ИИ не отвечает. |
| `flutter_keyboard_visibility` | Версия 6.0.0 из pub собирает android-библиотеку с `compileSdk 31` и падает на метаданных AAR (androidx требует 33+). Форк поднят до 36. |

Оба форка менять без нужды не стоит — правки в них ломают сборку приложения.

## Запуск

```bash
flutter run                      # на подключённом устройстве
flutter run -d chrome            # в браузере
flutter run --release            # release-сборка на устройство
```

## Сборка

### APK под один ABI (быстрее, для установки на телефон)

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

Результат — `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.

### APK для всех ABI

```bash
flutter build apk --release --split-per-abi
```

### App Bundle (для Google Play)

```bash
flutter build appbundle --release
```

### Web (для отладки UI без телефона)

```bash
flutter build web --release
python scripts/web_server.py      # http://127.0.0.1:8080 без кэша
```

`scripts/web_server.py` отдаёт `build/web` с заголовками `no-store`, чтобы
изменения не застревали в кэше. Данные на web идут в `localStorage`
(`lib/services/json_file.dart` проверяет `kIsWeb`).

## Установка по ADB

```bash
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Если падает с `INSTALL_FAILED_VERSION_DOWNGRADE` — поднять `versionCode` в
`pubspec.yaml`. Подробности в [RELEASE.md](RELEASE.md).

## Подпись релизной сборки

Файл `android/key.properties` нужен Gradle для release-сборки и **никогда не
коммитится** (он в `.gitignore`):

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=keystore.jks
```

Сам `keystore.jks` тоже в `.gitignore`. Локально он лежит в `android/`.

## Проверка качества

```bash
flutter analyze    # должно быть "No issues found!"
flutter test
flutter_lints 6.0.0 включён через analysis_options.yaml
```

## Структура репозитория

```
lib/           код приложения
android/       нативная часть (Kotlin)
assets/        звуки, шрифт Caveat, логотип
shaders/       GLSL-шейдеры (film grain)
test/          тесты + golden-изображения диалогов
third_party/   локальные форки плагинов
tools/         скрипты сборки датасета Ады, генерация логотипа
scripts/       вспомогательные скрипты сборки и веб-сервер
data/          обучающая выборка Ады (не в git)
```

Мусор в корень не кладём: логи, разовые скрипты, собранные APK и скриншоты
игнорируются правилами в конце `.gitignore`.

## Если что-то сломалось

**`A problem occurred evaluating android/app` после смены JDK**
Сбросить кэш Gradle:

```bash
cd android
./gradlew --stop
rm -rf .gradle ../.dart_tool ../build   # Windows: удалить вручную
flutter pub get
flutter run
```

**Оверлей Ады пустой, история пустая, ИИ не отвечает**
Почти всегда — репозиторий собран без локального форка
`flutter_overlay_window`, либо в его `pubspec.yaml` не прописаны
`shared_preferences` и `path_provider`. Сверься с `third_party/`.

**Приложение не переживает перезагрузку**
Проверь `RECEIVE_BOOT_COMPLETED` в `AndroidManifest.xml` и что
`AlarmReceiver` объявлен в `<receiver>` с экспортом наружу.

**Будильник срабатывает с задержкой**
На Android 12+ нужны `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`. Если
пользователь их не выдал, система даёт вольное расписание — отсюда «минута
позже, минута раньше».