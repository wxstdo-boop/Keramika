param(
    [switch]$SkipClean = $false,
    [switch]$Install = $true
)

$ErrorActionPreference = 'Stop'
$Project = 'C:\Games\keramika'
$ApkOutput = Join-Path $Project 'build\app\outputs\flutter-apk\app-release.apk'

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

try {
    Set-Location $Project

    if (-not $SkipClean) {
        Write-Step 'Быстрая очистка кеша'
        if (Test-Path 'build') { Remove-Item -Recurse -Force 'build' }
        if (Test-Path '.dart_tool') { Remove-Item -Recurse -Force '.dart_tool' }
        if (Test-Path 'ephemeral') { Remove-Item -Recurse -Force 'ephemeral' }
        $lightFiles = @('Generated.xcconfig', '.flutter-plugins-dependencies', 'flutter_export_environment.sh')
        foreach ($f in $lightFiles) { if (Test-Path $f) { Remove-Item -Force $f } }
        Write-Ok 'Кеш очищен'
    }

    Write-Step 'Resolve dependencies'
    flutter pub get
    Write-Ok 'Зависимости обновлены'

    Write-Step 'Build release APK (android-arm64 + android-arm)'
    flutter build apk `
        --no-tree-shake-icons `
        --target-platform android-arm,android-arm64
    Write-Ok 'APK собран'

    if ($Install -and (Test-Path $ApkOutput)) {
        Write-Step 'Установка на устройство'
        flutter install --device-id 23021RAA2Y
        Write-Ok 'Установлено'
    }

    Write-Step 'Готово'
    if (Test-Path $ApkOutput) {
        $size = [math]::Round((Get-Item $ApkOutput).Length / 1MB, 1)
        Write-Host "APK: $ApkOutput ($size MB)"
    }
} catch {
    Write-Err $_.Exception.Message
    exit 1
}
