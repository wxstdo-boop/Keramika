allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Плагины из pub-кеша (например flutter_keyboard_visibility) компилируются
// против устаревшего android-31 — форсируем compileSdk для всех подпроектов.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.BaseExtension>("android") {
            compileSdkVersion(36)
        }
        // Some plugins (flutter: file_picker 13 -> android_file_picker 2.1.1)
        // read the `flutter` extension DURING CONFIGURATION:
        //   extensions.getByName("flutter").intProperty("compileSdkVersion")
        // On AGP 9 (+ android.builtInKotlin=false) the flutter-plugin-loader
        // does not always create it in time, so configuration dies with
        // "Extension with name 'flutter' does not exist". Guarantee it exists
        // on the subproject, WITHOUT clobbering the real Flutter Gradle Plugin
        // extension if it has already been created.
        if (extensions.findByName("flutter") == null) {
            extensions.add(
                "flutter",
                mapOf<String, Any>(
                    "compileSdkVersion" to 36,
                    "minSdkVersion" to 21,
                ),
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
