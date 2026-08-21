import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "com.wetidom.keramika"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wetidom.keramika"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias", "")
            keyPassword = keystoreProperties.getProperty("keyPassword", "")
            storeFile = file(keystoreProperties.getProperty("storeFile", ""))
            storePassword = keystoreProperties.getProperty("storePassword", "")
        }
    }

    buildTypes {
        release {
            // Self-signed release keystore generated via keytool.
            // Replace with a real production keystore before publishing to
            // Play Store; for FOSS sideload distribution this is fine.
            signingConfig = signingConfigs.getByName("release")
            // R8 минификация: включаем сами (свойство shrink=false в
            // gradle.properties отключает сломанную автоматику Flutter-
            // плагина с getDefaultProguardFile в AGP 9). Правила — в
            // android/app/proguard-rules.pro.
            //
            // Быстрые сборки для установки на телефон (БЕЗ R8, в разы
            // быстрее):  KERAMIKA_NO_R8=1 flutter build apk --release
            // Финальный релиз собирается как обычно (с R8).
            isMinifyEnabled = System.getenv("KERAMIKA_NO_R8") != "1"
            // ВАЖНО: сжатие ресурсов ОТКЛЮЧЕНО. R8 с isShrinkResources
            // вырезал res/raw/*.wav (звуки будильника ссылаются строкой
            // "android.resource://pkg/raw/alarm_default", шинкер их не видит)
            // и переименовывал drawable — уведомления и звуки будильников
            // молча умирали. Код-минификация (R8) остаётся.
            isShrinkResources = false
            proguardFiles("proguard-rules.pro")
            isCrunchPngs = false
        }
    }

    lint {
        // Lint's release analysis (lintVital) runs out of metaspace on this
        // machine and aborts the build. Lint is static analysis only — it
        // doesn't affect the APK output, so skip it for release builds.
        checkReleaseBuilds = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
