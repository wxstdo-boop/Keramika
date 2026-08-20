$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  'C:\Wettixal\VSCodium',
  'C:\Wettixal\Poppy Playtime (2021)',
  (Join-Path $env:USERPROFILE 'AppData\Local\Programs\@opencode-aidesktop'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Programs\pool'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Programs\Pinokio'),
  'C:\Program Files\VSCodium',
  'C:\Program Files\Windhawk',
  'C:\Program Files\Hydra',
  'C:\Program Files\SteelSeries',
  (Join-Path $env:USERPROFILE 'AppData\Roaming\Code')
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    Write-Output ("{0,-55} {1,8} MB" -f $t, $mb)
  }
}
