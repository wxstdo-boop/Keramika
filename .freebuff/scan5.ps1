$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  (Join-Path $env:USERPROFILE 'AppData\Local\JetBrains'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Google'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Cursor'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming\Code'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming\Godot\export_templates'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Docker'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Packages'),
  (Join-Path $env:USERPROFILE '.vscode'),
  (Join-Path $env:USERPROFILE '.cursor'),
  (Join-Path $env:USERPROFILE '.gitconfig_cache'),
  'C:\ProgramData\chocolatey',
  (Join-Path $env:USERPROFILE 'AppData\Local\Yarn'),
  (Join-Path $env:USERPROFILE 'AppData\Local\pnpm'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming\npm-cache')
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    if ($mb -gt 50) { Write-Output ("{0,-60} {1,8} MB" -f $t, $mb) }
  }
}
