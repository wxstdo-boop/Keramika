# Safe system cleanup (admin): DISM WinSxS + old drivers + update cache
Write-Output "=== Start $(Get-Date -Format 'HH:mm:ss') ==="
$before = (Get-PSDrive C).Free
# 1. WinSxS component cleanup (frees several GB, official Microsoft command)
Dism.exe /Online /Cleanup-Image /StartComponentCleanup 2>&1 | Select-Object -Last 2
# 2. Remove superseded service pack components
Dism.exe /Online /Cleanup-Image /SPSuperseded 2>&1 | Select-Object -Last 2
# 3. Old CBS logs (system recreates them)
Remove-Item C:/Windows/Logs/CBS/CbsPersist_*.log -Force -ErrorAction SilentlyContinue
# 4. Windows Update download cache
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item C:/Windows/SoftwareDistribution/Download/* -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv -ErrorAction SilentlyContinue
$after = (Get-PSDrive C).Free
Write-Output ("Freed: {0:N1} GB" -f (($after-$before)/1GB))
Write-Output "=== Done ==="
