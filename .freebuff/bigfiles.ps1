$ErrorActionPreference = 'SilentlyContinue'
$roots = @(
  (Join-Path $env:USERPROFILE 'Downloads'),
  (Join-Path $env:USERPROFILE 'Documents'),
  (Join-Path $env:USERPROFILE 'Desktop'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Temp'),
  'C:\Windows\Temp'
)
foreach ($r in $roots) {
  if (Test-Path $r) {
    Get-ChildItem $r -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 200MB } | Sort-Object Length -Descending | Select-Object -First 5 | ForEach-Object {
      Write-Output ("{0,-70} {1,7:N0} MB" -f $_.FullName, ($_.Length/1MB))
    }
  }
}
