$ErrorActionPreference = 'SilentlyContinue'
foreach ($d in @('.grok', '.codex', '.local', '.config')) {
  $base = Join-Path $env:USERPROFILE $d
  if (Test-Path $base) {
    Get-ChildItem $base -Directory | ForEach-Object {
      $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
      $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
      if ($mb -gt 30) { Write-Output ("{0,-45} {1,8:N0} MB" -f $_.FullName, $mb) }
    }
  }
}
