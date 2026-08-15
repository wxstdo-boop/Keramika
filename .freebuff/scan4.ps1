$ErrorActionPreference = 'SilentlyContinue'
$roots = @(
  (Join-Path $env:USERPROFILE 'AppData\Local'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming'),
  'C:\Users\Default',
  'C:\ProgramData'
)
foreach ($r in $roots) {
  if (Test-Path $r) {
    Get-ChildItem $r -Directory -Depth 1 | ForEach-Object {
      $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
      $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
      if ($mb -gt 300) {
        Write-Output ("{0,-55} {1,8} MB" -f $_.FullName, $mb)
      }
    }
  }
}
