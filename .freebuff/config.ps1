$ErrorActionPreference = 'SilentlyContinue'
$base = Join-Path $env:USERPROFILE '.config'
foreach ($d in @('koda', 'mimocode', 'opencode', 'kilo', 'manicode', 'poolside', 'amp', 'freellmpool')) {
  $p = Join-Path $base $d
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    Write-Output ("{0,-28} {1,8:N0} MB" -f $d, $mb)
  }
}
