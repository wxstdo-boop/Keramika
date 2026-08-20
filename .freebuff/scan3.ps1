$ErrorActionPreference = 'SilentlyContinue'
$roots = @('C:\ProgramData', 'C:\Users', 'C:\Tools')
foreach ($r in $roots) {
  if (Test-Path $r) {
    Get-ChildItem $r -Directory -Depth 1 | ForEach-Object {
      $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
      $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
      if ($mb -gt 800) {
        Write-Output ("{0,-60} {1,8} MB" -f $_.FullName, $mb)
      }
    }
  }
}
