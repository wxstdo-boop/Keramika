# SCC — Super Cache Cleaner. Cleans safe caches, shows what was freed.
$ErrorActionPreference = 'SilentlyContinue'
$total = 0

function Free-MB([long]$bytes) {
  return [math]::Round($bytes / 1MB, 1)
}

$before = (Get-PSDrive C).Free

# 1. User Temp
$tmp = $env:TEMP
$t0 = (Get-ChildItem $tmp -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
Remove-Item "$tmp\*" -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("Temp: freed " + (Free-MB $t0) + " MB")

# 2. Flutter / Gradle caches
$paths = @(
  "$env:USERPROFILE\.gradle\caches",
  "$env:USERPROFILE\.gradle\wrapper\dists",
  "$env:USERPROFILE\AppData\Local\Pub\Cache\git"
)
foreach ($p in $paths) {
  if (Test-Path $p) {
    $s = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ("Deleted cache: " + $p + " (" + (Free-MB $s) + " MB)")
  }
}

# 3. build/ + .dart_tool of known Flutter projects
$projects = @(
  'C:\Games\keramika',
  'C:\Games\ataraxy'
)
foreach ($pr in $projects) {
  foreach ($sub in @('build', '.dart_tool')) {
    $p = Join-Path $pr $sub
    if (Test-Path $p) {
      $s = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
      Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
      Write-Host ("Deleted build cache: " + $p + " (" + (Free-MB $s) + " MB)")
    }
  }
}

$after = (Get-PSDrive C).Free
$freed = Free-MB ($after - $before)
Write-Host ""
Write-Host ("Total freed: " + $freed + " MB")
Write-Host ("Free space now: " + [math]::Round($after / 1GB, 1) + " GB")
Write-Host ""
Write-Host "Press any key to close..."
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
