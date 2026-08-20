$ErrorActionPreference = 'SilentlyContinue'
$results = @()
$roots = @('C:\')
foreach ($r in $roots) {
  Get-ChildItem $r -Directory -Depth 2 | ForEach-Object {
    $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
    if ($mb -gt 400) {
      $results += [PSCustomObject]@{ Path = $_.FullName; MB = $mb }
    }
  }
}
$results | Sort-Object MB -Descending | Select-Object -First 60 | ForEach-Object {
  Write-Output ("{0,-70} {1,8:N0} MB" -f $_.Path, $_.MB)
}
