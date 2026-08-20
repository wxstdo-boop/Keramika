$ErrorActionPreference = 'SilentlyContinue'
$base = Join-Path $env:USERPROFILE 'omniroute'
foreach ($sub in @('node_modules', '.git')) {
  $p = Join-Path $base $sub
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Output ("{0,-14} {1,8:N0} MB" -f $sub, ($sz/1MB))
  }
}
