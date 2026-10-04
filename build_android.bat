@echo off
set JAVA_HOME=C:\Users\Larafut\dev\jdk21
set PATH=%JAVA_HOME%\bin;%PATH%
cd /d C:\wetcorporation\projects\keramika
call C:\Users\Larafut\dev\flutter\bin\flutter.bat clean
call C:\Users\Larafut\dev\flutter\bin\flutter.bat build apk --release --split-per-abi --target-platform android-arm64
