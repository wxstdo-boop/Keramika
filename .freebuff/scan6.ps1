$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  'C:\Windows\Installer',
  'C:\ProgramData\Package Cache',
  'C:\Windows\SoftwareDistribution\Download',
  (Join-Path $env:USERPROFILE 'AppData\Local\Packages'),
  (Join-Path $env:USERPROFILE 'AppData\Local\D3DSCache'),
  (Join-Path $env:USERPROFILE 'AppData\Local\NVIDIA'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Google'),
  (Join-Path $env:USERPROFILE 'AppData\Local\CrashDumps'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Windows\Explorer'),
  'C:\Windows\Prefetch'
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    if ($mb -gt 30) { Write-Output ("{0,-60} {1,8} MB" -f $t, $mb) }
  }
}
