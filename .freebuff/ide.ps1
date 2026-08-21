$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  'C:\Program Files\Android',
  'C:\Program Files\Android\Android Studio',
  'C:\Program Files\JetBrains',
  'C:\Wettixal\Bioshock 2 Remastered',
  'C:\Program Files\Karing',
  'C:\Program Files\Cloudflare',
  'C:\Program Files\EqualizerAPO',
  'C:\Program Files\Hydra',
  'C:\Program Files\SteelSeries',
  'C:\Program Files\WinDirStat',
  'C:\Program Files\Winaero Tweaker',
  'C:\Program Files\Windhawk',
  'C:\Program Files\WizTree'
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    Write-Output ("{0,-45} {1,8:N0} MB" -f $t, $mb)
  }
}
