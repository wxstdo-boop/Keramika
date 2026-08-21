$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem (Join-Path $env:USERPROFILE 'AppData\Local\Programs') -Directory | ForEach-Object {
  $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
  $mb = if ($sz) { [math]::Round($sz/1MB, 0) } else { 0 }
  Write-Output ("{0,-30} {1,8} MB" -f $_.Name, $mb)
}
