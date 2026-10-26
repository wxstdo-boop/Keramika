#requires -Version 5.1
<#
.SYNOPSIS
    Ротация ключа подписи Keramika: новый keystore, новые пароли, готовые
    значения для секретов GitHub.

.DESCRIPTION
    Старый ключ (keramika-release.jks) лежит в истории публичного репозитория
    и читается через `git show`. Пока он жив, любой клон может собрать
    «обновление», которое телефон примет как настоящее. Этот скрипт выпускает
    НОВЫЙ ключ и складывает старый в резервную папку вне репозитория.

    Что делает по шагам:
      1. находит keytool (JDK 21 в C:\Users\<user>\dev\jdk21);
      2. копирует текущий keystore и key.properties в папку резерва;
      3. генерирует новый keystore (PKCS12, RSA 4096, срок 10000 дней);
      4. пишет android/key.properties (он в .gitignore) и новый .jks;
      5. сохраняет KEYSTORE_BASE64 в файл для секрета репозитория;
      6. печатает 4 значения секретов и SHA-256 отпечаток сертификата.

    ВАЖНО, ПРОЧТИ ПЕРЕД ЗАПУСКОМ
    Смена ключа подписи = подпись нового APK не совпадает с установленной.
    Android не даст поставить такой APK поверх старого («Приложение не
    установлено»), а встроенное автообновление будет скачивать файл и падать
    на установке. Поэтому ротация делается ОДНОВРЕМЕННО с релизом, который
    сообщает пользователям «переустанови вручную», и только если риск
    утёкшего ключа признан выше, чем потеря бесшовных обновлений.
    Альтернатива — оставить ключ и принять риск.

    Скрипт ничего не коммитит и не пушит. Секреты не попадают в рабочее
    дерево: только на консоль и в файлы вне репозитория.

.PARAMETER Force
    Заменить существующий android/app/keramika-release.jks без вопроса
    (резервная копия всё равно делается).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\rotate-keystore.ps1
#>
[CmdletBinding()]
param(
    [string]$Alias = 'keramika',
    [string]$DName = 'CN=Keramika, OU=Release, O=Keramika, C=RU',
    [int]$ValidityDays = 10000,
    [string]$Keytool = '',
    [string]$BackupRoot = (Join-Path $env:USERPROFILE 'keramika-keystore-backup'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$androidDir = Join-Path $repoRoot 'android'
$ksPath = Join-Path $androidDir 'app\keramika-release.jks'
$propsPath = Join-Path $androidDir 'key.properties'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot "before-rotation-$stamp"

function Find-Keytool {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "keytool не найден по пути: $Explicit" }
        return (Resolve-Path $Explicit).Path
    }
    $candidates = @(
        (Join-Path $env:USERPROFILE 'dev\jdk21\bin\keytool.exe'),
        (Join-Path $env:JAVA_HOME 'bin\keytool.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    $cmd = Get-Command keytool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    throw "keytool не найден. Укажи путь: -Keytool C:\path\to\jdk\bin\keytool.exe"
}

# keytool пишет прогресс и предупреждения в stderr, а при
# $ErrorActionPreference='Stop' это трактуется как фатальная ошибка.
# Поэтому зовём его отдельно и судим по коду возврата.
function Invoke-Keytool {
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & $keytoolExe @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $prev
    }
    if ($code -ne 0) {
        throw "keytool завершился с кодом $code`n$out"
    }
    return $out
}

function New-StrongPassword {
    param([int]$Length = 32)
    # Только [A-Za-z0-9]: дефисы, подчёркивания и кавычки в секретах GitHub
    # уже приводили к «SP length : 13 вместо 12» и «keystore password was
    # incorrect». Секреты не тримятся, поэтому алфавит максимально скучный.
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'.ToCharArray()
    $bytes = New-Object 'byte[]' $Length
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $charset = $chars.Length
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $bytes) { [void]$sb.Append($chars[$b % $charset]) }
    return $sb.ToString()
}

Write-Host '=== Ротация ключа подписи Keramika ===' -ForegroundColor Cyan

$keytoolExe = Find-Keytool -Explicit $Keytool
Write-Host "keytool : $keytoolExe"

if ((Test-Path $ksPath) -and -not $Force) {
    $oldSize = (Get-Item $ksPath).Length
    $oldDate = (Get-Item $ksPath).LastWriteTime.ToString('yyyy-MM-dd HH:mm')
    Write-Host ''
    Write-Host "Текущий keystore: $ksPath" -ForegroundColor Yellow
    Write-Host "  размер $oldSize Б, изменён $oldDate" -ForegroundColor Yellow
    Write-Host '  пароль не запрашиваю: для ротации он не нужен.' -ForegroundColor DarkGray
    Write-Host ''
    $answer = Read-Host 'Выпустить НОВЫЙ ключ и заменить текущий? Резервная копия будет сделана. [y/N]'
    if ($answer -notmatch '^(y|Y|д|Д)') {
        Write-Host 'Отменено. Ничего не изменено.' -ForegroundColor Yellow
        exit 1
    }
}

# --- 1. Резерв текущего состояния -------------------------------------------
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($f in @($ksPath, $propsPath)) {
    if (Test-Path $f) {
        Copy-Item $f (Join-Path $backupDir (Split-Path -Leaf $f)) -Force
        Write-Host "  резерв: $f -> $backupDir" -ForegroundColor DarkGray
    }
}
if (-not (Test-Path $ksPath)) {
    Write-Host '  ВНИМАНИЕ: текущего keystore нет — ротация с нуля, откатывать нечего.' -ForegroundColor Yellow
}

# --- 2. Новый keystore -------------------------------------------------------
$storePassword = New-StrongPassword
$keyPassword = $storePassword          # PKCS12: пароль ключа = пароль хранилища
$tmpKs = Join-Path $backupDir 'keramika-release.jks.new'

$null = Invoke-Keytool -Arguments @(
    '-genkeypair',
    '-keystore', $tmpKs,
    '-storetype', 'PKCS12',
    '-alias', $Alias,
    '-keyalg', 'RSA',
    '-keysize', '4096',
    '-validity', "$ValidityDays",
    '-dname', $DName,
    '-storepass', $storePassword,
    '-keypass', $keyPassword
)

if (-not (Test-Path $tmpKs)) { throw 'keytool не создал keystore — смотри вывод выше.' }

# --- 3. Раскладка по рабочему дереву ----------------------------------------
Copy-Item $tmpKs $ksPath -Force
@(
    "storePassword=$storePassword"
    "keyPassword=$keyPassword"
    "keyAlias=$Alias"
    "storeFile=keramika-release.jks"
) | Set-Content -Path $propsPath -Encoding ASCII

# --- 4. Значения для секретов GitHub ----------------------------------------
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($ksPath))
$secretsFile = Join-Path $backupDir 'GITHUB_SECRETS.txt'
@(
    '# Секреты репозитория Keramika (Settings -> Secrets and variables -> Actions)',
    '# Задать ровно как есть: пробелы и переводы строк не тримятся.',
    '',
    "KEYSTORE_BASE64=$b64",
    "STORE_PASSWORD=$storePassword",
    "KEY_PASSWORD=$keyPassword",
    "KEY_ALIAS=$Alias"
) | Set-Content -Path $secretsFile -Encoding ASCII

$certInfo = Invoke-Keytool -Arguments @(
    '-list', '-v',
    '-keystore', $ksPath,
    '-storetype', 'PKCS12',
    '-alias', $Alias,
    '-storepass', $storePassword
)
$fingerprint = ''
$m = [regex]::Match($certInfo, 'SHA256:\s*([0-9A-Fa-f:]+)')
if ($m.Success) { $fingerprint = $m.Groups[1].Value }

@(
    "keystore: $ksPath",
    "alias: $Alias",
    "SHA256: $fingerprint",
    "validity: $ValidityDays дней",
    "создан: $stamp"
) | Set-Content -Path (Join-Path $backupDir 'FINGERPRINT.txt') -Encoding UTF8

Write-Host ''
Write-Host '=== Готово. Что дальше ===' -ForegroundColor Green
Write-Host '1) Секреты репозитория (4 штуки) лежат в:'
Write-Host "   $secretsFile" -ForegroundColor Cyan
Write-Host '   Settings -> Secrets and variables -> Actions -> New repository secret:'
Write-Host "     KEYSTORE_BASE64, STORE_PASSWORD, KEY_PASSWORD, KEY_ALIAS ($Alias)"
Write-Host '2) Отпечаток нового сертификата (обновить в AGENTS.md):'
Write-Host "   $fingerprint" -ForegroundColor Cyan
Write-Host '3) Старый ключ и старые пароли — в резерве:'
Write-Host "   $backupDir" -ForegroundColor Cyan
Write-Host ''
Write-Host 'ПОМНИ: установленные сборки подписаны СТАРЫМ ключом.' -ForegroundColor Yellow
Write-Host 'Новый APK не встанет поверх них: нужна переустановка вручную,' -ForegroundColor Yellow
Write-Host 'а автообновление на их телефонах будет падать на установке.' -ForegroundColor Yellow
Write-Host 'Перед публикацией такого релиза подними minor-версию и напиши' -ForegroundColor Yellow
Write-Host 'в заметках, что нужна переустановка.' -ForegroundColor Yellow
