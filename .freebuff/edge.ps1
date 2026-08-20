$ErrorActionPreference = 'SilentlyContinue'
$base = Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\Edge\User Data'
Get-ChildItem $base -Directory | ForEach-Object {
  $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
  $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
  if ($mb -gt 50) {
    Write-Output ("{0,-40} {1,8} MB" -f $_.Name, $mb)
  }
}
