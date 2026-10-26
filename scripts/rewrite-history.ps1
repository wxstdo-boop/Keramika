#requires -Version 5.1
<#
.SYNOPSIS
    Перепись истории Keramika: вычистить android/key.properties и keystore
    из всех коммитов и (по флагу) силой обновить GitHub.

.DESCRIPTION
    В истории публичного репозитория лежат android/key.properties (пароли
    подписи) и android/app/keramika-release.jks (сам ключ). Они удалены из
    трекинга, но читаются через `git show`. Пока ключ не заменён, любой клон
    может выпустить «обновление», которое телефон примет как настоящее.

    Правильный порядок действий:
      1) scripts\rotate-keystore.ps1 — новый ключ, новые секреты GitHub;
      2) этот скрипт — вычистить старый ключ из истории;
      3) предупредить всех, кто клонировал: переклонировать.

    Скрипт НЕ трогает рабочее дерево: он делает зеркальный клон во временную
    папку, переписывает его через git-filter-repo, проверяет результат и
    только по -Execute пушит. Без -Execute это безопасный прогон «покажи,
    что получится».

    ВАЖНО ПОСЛЕ ЗАПИСИ
      * Ветки и теги меняют SHA: открытые PR станут «не теми», ссылки на
        старые коммиты перестанут открываться;
      * чужие форки и локальные клоны сохраняют старую историю — их надо
        переклонировать (или они сами вычистят у себя);
      * GitHub ещё какое-то время отдаёт старые объекты по прямому SHA;
        окончательно их убирает поддержка GitHub по запросу
        (Settings -> Support, «remove cached views / purge objects»);
      * перепись имеет смысл ТОЛЬКО после ротации ключа. Иначе вы просто
        спрятали живой ключ, который уже скачан.

.PARAMETER Execute
    Реально запушить переписанную историю (force). Без него — только прогон
    и отчёт.

.PARAMETER Token
    GitHub PAT с Contents: write. Нужен для клона/пуша, если git не умеет
    авторизоваться сам. В лог не пишется.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\rewrite-history.ps1
    powershell -ExecutionPolicy Bypass -File scripts\rewrite-history.ps1 -Execute
#>
[CmdletBinding()]
param(
    [string]$Repo = 'wxstdo-boop/Keramika',
    [string]$WorkDir = (Join-Path $env:TEMP 'keramika-rewrite'),
    [string[]]$SecretPaths = @(
        'android/key.properties',
        'android/app/keramika-release.jks',
        'android/app/keystore.jks'
    ),
    [string]$Token = '',
    [string]$RemoteUrl = '',
    [switch]$Execute
)

# git пишет прогресс (Cloning into..., rewriting commits...) в stderr, а при
# $ErrorActionPreference='Stop' это трактуется как фатальная ошибка и скрипт
# падает на середине. Поэтому здесь Continue: результат каждой команды
# проверяется явно (Test-Path / $LASTEXITCODE / пустой вывод), а не через
# обработчик ошибок.
$ErrorActionPreference = 'Continue'
if (-not $RemoteUrl) { $RemoteUrl = "https://github.com/$Repo.git" }

function Find-FilterRepo {
    $cmd = Get-Command git-filter-repo -ErrorAction SilentlyContinue
    if ($cmd) { return @{ Exe = $cmd.Source; Prefix = @() } }
    $pys = @(
        (Join-Path $env:USERPROFILE '.workbuddy-ai\binaries\python\envs\default\Scripts\python.exe'),
        'python'
    )
    foreach ($py in $pys) {
        try {
            $out = & $py -m git_filter_repo --version 2>&1
            if ($LASTEXITCODE -eq 0) {
                return @{ Exe = $py; Prefix = @('-m', 'git_filter_repo') }
            }
        }
        catch { }
    }
    throw 'git-filter-repo не найден. Установить: pip install git-filter-repo'
}

function Invoke-GitWithAuth {
    param([string]$WorkTree, [string[]]$Arguments)
    $extra = @()
    if ($Token) {
        $pair = "x-access-token:$Token"
        $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))
        $extra = @('-c', "http.extraheader=Authorization: Basic $b64")
    }
    $all = $extra + $Arguments
    Push-Location $WorkTree
    try {
        & git @all 2>&1 | Out-String
    }
    finally {
        Pop-Location
    }
}

Write-Host '=== Перепись истории Keramika ===' -ForegroundColor Cyan
Write-Host "repo    : $RemoteUrl"
Write-Host "workdir : $WorkDir"
Write-Host "вычищаем: $($SecretPaths -join ', ')"
Write-Host ''

if ($Execute) {
    Write-Host 'ВНИМАНИЕ: включён -Execute. Ветки и теги на GitHub будут перезаписаны.' -ForegroundColor Red
    $answer = Read-Host 'Напиши REWRITE, чтобы продолжить'
    if ($answer -ne 'REWRITE') {
        Write-Host 'Отменено.' -ForegroundColor Yellow
        exit 1
    }
}

$filter = Find-FilterRepo
Write-Host "filter-repo: $($filter.Exe) $($filter.Prefix -join ' ')" -ForegroundColor DarkGray

if (Test-Path $WorkDir) {
    Write-Host "Чищу старую рабочую папку: $WorkDir" -ForegroundColor DarkGray
    Remove-Item $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$mirror = Join-Path $WorkDir 'repo.git'

# --- 1. Зеркальный клон (рабочее дерево не трогаем) --------------------------
Write-Host ''
Write-Host '1/4 Зеркальный клон...' -ForegroundColor Cyan
$cloneArgs = @('clone', '--mirror', $RemoteUrl, $mirror)
$out = Invoke-GitWithAuth -WorkTree $WorkDir -Arguments $cloneArgs
if (-not (Test-Path (Join-Path $mirror 'HEAD'))) {
    throw "Клон не удался:`n$out"
}

# --- 2. Перепись -------------------------------------------------------------
Write-Host '2/4 Перепись истории (git-filter-repo)...' -ForegroundColor Cyan
$frArgs = @()
foreach ($p in $SecretPaths) { $frArgs += @('--path', $p) }
$frArgs += @('--invert-paths', '--force')

Push-Location $mirror
try {
    $cmdArgs = $filter.Prefix + $frArgs
    & $filter.Exe @cmdArgs 2>&1 | Select-Object -Last 12 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { throw "git-filter-repo завершился с кодом $LASTEXITCODE" }
}
finally {
    Pop-Location
}

# filter-repo удаляет remote origin, чтобы никто случайно не запушил.
if (-not (& git -C $mirror remote)) {
    & git -C $mirror remote add origin $RemoteUrl | Out-Null
}

# --- 3. Проверка -------------------------------------------------------------
Write-Host '3/4 Проверка, что файлов больше нет ни в одном коммите...' -ForegroundColor Cyan
$leftover = & git -C $mirror log --all --oneline -- $SecretPaths
if ($leftover) {
    Write-Host '  ОСТАЛИСЬ КОММИТЫ:' -ForegroundColor Red
    $leftover | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
    throw 'Перепись неполная — не пушу.'
}
$objects = & git -C $mirror rev-list --all --objects | Select-String -Pattern '\.jks$|key\.properties$'
if ($objects) {
    Write-Host '  В объектах ещё есть пути:' -ForegroundColor Red
    $objects | Select-Object -First 10 | ForEach-Object { Write-Host "   $_" }
    throw 'В истории остались секретные пути — не пушу.'
}
Write-Host '  Чисто: ни одного коммита, ни одного объекта с этими путями.' -ForegroundColor Green

$heads = (& git -C $mirror for-each-ref --format='%(refname:short)' refs/heads).Count
$tags = (& git -C $mirror for-each-ref --format='%(refname:short)' refs/tags).Count
Write-Host "  Веток: $heads, тегов: $tags" -ForegroundColor DarkGray

# --- 4. Пуш -----------------------------------------------------------------
Write-Host ''
Write-Host '4/4 Пуш...' -ForegroundColor Cyan
$pushArgs = @(
    'push', '--force', 'origin',
    'refs/heads/*:refs/heads/*',
    'refs/tags/*:refs/tags/*'
)

if (-not $Execute) {
    Write-Host '  Сухой прогон: ничего не отправлено.' -ForegroundColor Yellow
    Write-Host '  Готово к записи. Проверь отчёт выше и запусти с -Execute:' -ForegroundColor Yellow
    Write-Host "    powershell -ExecutionPolicy Bypass -File scripts\rewrite-history.ps1 -Execute"
    Write-Host ''
    Write-Host "  Переписанный клон остался здесь: $mirror" -ForegroundColor DarkGray
    exit 0
}

Push-Location $mirror
try {
    $cmdArgs = @()
    if ($Token) {
        $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("x-access-token:$Token"))
        $cmdArgs += @('-c', "http.extraheader=Authorization: Basic $b64")
    }
    $cmdArgs += $pushArgs
    & git @cmdArgs 2>&1 | Select-Object -Last 20 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($code -ne 0) { throw "Пуш не удался (код $code). Нужен PAT с Contents: write." }

Write-Host ''
Write-Host '=== История переписана ===' -ForegroundColor Green
Write-Host 'Осталось сделать руками:' -ForegroundColor Yellow
Write-Host '  1) Переклонировать локальные копии (старые пушатся только с --force и вернут ключ).'
Write-Host '  2) Сказать всем, у кого есть клон/форк: переклонировать.'
Write-Host '  3) Попросить поддержку GitHub вычистить кэш старых объектов по SHA.'
Write-Host '  4) Проверить: git log --all -- android/key.properties должен быть пустым.'
