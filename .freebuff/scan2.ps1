$ErrorActionPreference = 'SilentlyContinue'
$roots = @(
  (Join-Path $env:USERPROFILE 'AppData\Local'),
  (Join-Path $env:USERPROFILE 'AppData\Roaming'),
  'C:\ProgramData',
  'C:\Tools',
  'C:\flutter',
  'C:\Program Files',
  'C:\Program Files (x86)'
)
foreach ($r in $roots) {
  if (Test-Path $r) {
    $dirs = Get-ChildItem $r -Directory
    foreach ($d in $dirs) {
      $sz = (Get-ChildItem $d.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
      $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
      if ($mb -gt 500) {
        Write-Output ("{0,-55} {1,8} MB" -f $d.FullName, $mb)
      }
    }
  }
}
