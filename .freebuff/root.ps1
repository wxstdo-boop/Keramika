$ErrorActionPreference = 'SilentlyContinue'
foreach ($p in @('C:\dev', 'C:\tmp', 'C:\shorebird', 'C:\jdk21', 'C:\zapret-discord-youtube-1.9.9c', 'C:\Disfigured', 'C:\Wettixal')) {
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Output ("{0,-40} {1,8:N0} MB" -f $p, ($sz/1MB))
  }
}
