@echo off
chcp 65001 >nul
REM Soft clean only — do NOT delete build/, .dart_tool, or pub cache.
REM Full rebuild caches are required for fast APK builds on 8GB RAM.

set "PROJECT=C:\Games\keramika"
echo Keramika soft clean (caches KEPT)...

if exist "%PROJECT%\*.log" del /q /f "%PROJECT%\*.log" 2>nul
if exist "%PROJECT%\*.hprof" del /q /f "%PROJECT%\*.hprof" 2>nul

REM Old APKs in project root only (not under build/)
forfiles /p "%PROJECT%" /m "*.apk" /d -3 /c "cmd /c del /q @path" 2>nul

echo Done. Gradle/Flutter caches untouched.
exit /b 0
