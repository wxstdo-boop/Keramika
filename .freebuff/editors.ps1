$ErrorActionPreference = 'SilentlyContinue'
foreach ($t in @('C:\Program Files\cursor', 'C:\Wettixal\AionUi', 'C:\Games\AgnesCode')) {
  if (Test-Path $t) {
    $sz = (Get-ChildItem $t -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Output ("{0,-40} {1,8:N0} MB" -f $t, ($sz/1MB))
  }
}
