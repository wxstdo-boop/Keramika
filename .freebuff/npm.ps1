$ErrorActionPreference = 'SilentlyContinue'
$p = Join-Path $env:USERPROFILE 'AppData\Roaming\npm\node_modules'
$sz = (Get-ChildItem $p -Recurse -File | Measure-Object -Property Length -Sum).Sum
Write-Output ("npm node_modules {0:N0} MB" -f ($sz/1MB))
Get-ChildItem $p -Directory | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
  $m = if ($s) { [math]::Round($s/1MB, 0) } else { 0 }
  if ($m -gt 100) { Write-Output ("  {0,-30} {1,6} MB" -f $_.Name, $m) }
}
