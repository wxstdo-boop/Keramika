$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Windows\INetCache'),
  (Join-Path $env:USERPROFILE 'AppData\Local\D3DSCache'),
  'C:\Windows\Logs',
  'C:\ProgramData\USOShared',
  'C:\Windows\SoftwareDistribution',
  (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Edge\User Data\Default\Service Worker'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Edge\User Data\Default\IndexedDB'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming\Godot\shader_cache'),
  (Join-Path $env:USERPROFILE 'AppData\Local\crashpad'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming\Microsoft\Windows\Recent')
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    if ($mb -gt 20) { Write-Output ("{0,-65} {1,8} MB" -f $t, $mb) }
  }
}
