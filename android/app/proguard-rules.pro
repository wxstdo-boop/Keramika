# Rules для R8-минификации release-сборки.
# Содержимое flutter_proguard_rules.pro (из Flutter SDK) + базовые keep.

# Build the ephemeral app in a module project.
# Prevents: Warning: library class <plugin-package> depends on program class io.flutter.plugin.**
# This is due to plugins (libraries) depending on the embedding (the program jar)
-dontwarn io.flutter.plugin.**

# The android.** package is provided by the OS at runtime.
-dontwarn android.**

# In some cases, R8 is incorrectly stripping plugin classes. Keep
# all implementations of FlutterPlugin until we can determine
# why this is the case.
-if class * implements io.flutter.embedding.engine.plugins.FlutterPlugin
-keep,allowshrinking,allowobfuscation class <1>

# Keep Flutter engine embedding classes — без них приложение падает на старте.
-keep class io.flutter.** { *; }
-keep class com.wetidom.keramika.** { *; }

# Метод-каналы обращаются по именам из Dart — не трогаем.
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel *;
}

# Плагины, которые могут быть вызваны по reflection (android_intent_plus и пр.).
-keep class androidx.core.app.** { *; }
-keep class androidx.appcompat.app.** { *; }
# Please add these rules to your existing keep rules in order to suppress warnings.
# This is generated automatically by the Android Gradle plugin.
-dontwarn androidx.window.extensions.WindowExtensions
-dontwarn androidx.window.extensions.WindowExtensionsProvider
-dontwarn androidx.window.extensions.area.ExtensionWindowAreaPresentation
-dontwarn androidx.window.extensions.layout.DisplayFeature
-dontwarn androidx.window.extensions.layout.FoldingFeature
-dontwarn androidx.window.extensions.layout.WindowLayoutComponent
-dontwarn androidx.window.extensions.layout.WindowLayoutInfo
-dontwarn androidx.window.sidecar.SidecarDeviceState
-dontwarn androidx.window.sidecar.SidecarDisplayFeature
-dontwarn androidx.window.sidecar.SidecarInterface$SidecarCallback
-dontwarn androidx.window.sidecar.SidecarInterface
-dontwarn androidx.window.sidecar.SidecarProvider
-dontwarn androidx.window.sidecar.SidecarWindowLayoutInfo
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
# ── Gson TypeToken (flutter_local_notifications) ──────────────
# R8 стирает generic-сигнатуры (Signature) у анонимных подклассов
# TypeToken — плагин падает с «Missing type parameter» при zonedSchedule
# (напр. ежедневные напоминания Ады, fallback-будильники). Сохраняем
# сигнатуры и классы плагина целиком: Gson читает поля через reflection,
# переименование полей сломало бы сохранённое расписание.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Gson: сохранить generic-сигнатуры TypeToken и его подклассов при R8.
# Без этого zonedSchedule падает с «Missing type parameter» (AGP 8.x).
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Системный оверлей Ады (flutter_overlay_window): OverlayService
# вызывается из AndroidManifest и через reflection — R8 не должен его
# вырезать/переименовывать, иначе мини-окошко не появится.
-keep class flutter.overlay.window.flutter_overlay_window.** { *; }
-keepattributes ServiceLoader
# InnerClasses обязателен вместе с EnclosingMethod: без него R8 падает
# с «Attribute EnclosingMethod requires InnerClasses attribute» (Gson,
# Kotlin-лямбды, анонимные классы плагинов).
-keepattributes InnerClasses
-keepattributes EnclosingMethod
