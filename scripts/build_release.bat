@echo off
setlocal

set PROJECT=C:\Games\keramika
set JAVA_HOME=C:\Users\Грэйсик\jdk-21\jdk-21.0.5+11-beta
set PATH=%JAVA_HOME%\bin;%PATH%

echo Building release APK...
cd /d "%PROJECT%"
flutter pub get
flutter build apk --release --split-per-abi

if exist "%PROJECT%\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    echo APK built successfully
    flutter install --device-id 23021RAA2Y
) else (
    echo Build failed or APK not found
)