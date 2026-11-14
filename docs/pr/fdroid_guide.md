# 🚀 Руководство по публикации Agysha в F-Droid

## Что такое F-Droid
**F-Droid** — крупнейший независимый каталог свободного и открытого ПО (FOSS) для Android. Публикация в F-Droid даёт приложению доверие миллионов пользователей, ценящих приватность, отсутствие трекеров и открытый исходный код.

---

## Что уже подготовлено в репозитории Agysha
1. **Fastlane Metadata**:
   - `fastlane/metadata/android/ru-RU/` — русское описание, заголовки, краткие аннотации и скриншоты.
   - `fastlane/metadata/android/en-US/` — английское описание и скриншоты.
2. **F-Droid Build Recipe**:
   - `fdroid/metadata/com.wetcorp.agysha.yml` — готовый рецепт сборки для официального репозитория `fdroiddata`.

---

## Пошаговый план добавления приложения в F-Droid (2 способа)

### Способ 1: Merge Request в репозиторий `fdroiddata` (Самый быстрый, 3-7 дней)
1. Зарегистрируйтесь / войдите на **GitLab** ([gitlab.com](https://gitlab.com)).
2. Сделайте Fork репозитория [fdroiddata](https://gitlab.com/fdroid/fdroiddata).
3. В ветку своего форка добавьте файл:
   `metadata/com.wetcorp.agysha.yml` (содержимое возьмите из нашего файла `fdroid/metadata/com.wetcorp.agysha.yml`).
4. Создайте Merge Request в `fdroid/fdroiddata`.
5. Автоматический CI F-Droid проверит:
   - Лицензию (у нас MIT — полностью соответствует требованиям F-Droid).
   - Чистоту от проприетарных блобов (Google Play Services, рекламы нет, только чистый Flutter и Android AlarmManager API).
   - Сборку из исходников.
6. После мержа приложение появится в официальном каталоге F-Droid и станет доступно для установки через официальный клиент F-Droid, Droid-ify и Aurora Droid!

---

### Способ 2: Запрос на упаковку (RFP — Request for Packaging)
Если вы не хотите делать MR вручную:
1. Откройте GitLab Issues в [fdroiddata/issues](https://gitlab.com/fdroid/fdroiddata/-/issues/new).
2. Выберите шаблон **"Request for Packaging (RFP)"**.
3. Заполните поля:
   - **App Name**: Agysha
   - **Application ID**: `com.wetcorp.agysha`
   - **Repository**: `https://github.com/wxstdo-boop/Agysha`
   - **License**: MIT
   - **Summary**: 100% Reliable Open Source alarm clock, habits, reality checks & tasks
   - **Fastlane metadata**: Already available in the root repo!
4. Мейнтейнеры F-Droid возьмут рецепт из нашего репозитория и включат в следующий билд-цикл.
