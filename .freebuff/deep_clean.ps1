$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\Games\logs\deep_clean.log'
Add-Content -Path $log -Value ("[{0}] === deep clean start ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

# 1) WinSxS Temp — всегда можно
$winsxsTemp = 'C:\Windows\WinSxS\Temp'
if (Test-Path $winsxsTemp) {
    $before = (Get-ChildItem $winsxsTemp -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Remove-Item "$winsxsTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Add-Content -Path $log -Value ("WinSxS Temp: {0:N0} MB" -f ($before/1MB)) -Encoding UTF8
}

# 2) DISM component cleanup (WinSxS) — удаляет старые версии компонентов
$beforeDism = (Get-ChildItem 'C:\Windows\WinSxS' -Recurse -File | Measure-Object -Property Length -Sum).Sum
& Dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet 2>&1 | Out-Null
$afterDism = (Get-ChildItem 'C:\Windows\WinSxS' -Recurse -File | Measure-Object -Property Length -Sum).Sum
Add-Content -Path $log -Value ("DISM: {0:N0} MB freed" -f (($beforeDism-$afterDism)/1MB)) -Encoding UTF8

# 3) Windows Update cleanup (SoftwareDistribution\Download)
$sd = 'C:\Windows\SoftwareDistribution\Download'
if (Test-Path $sd) {
    $sz = (Get-ChildItem $sd -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Get-ChildItem $sd -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Add-Content -Path $log -Value ("SoftwareDistribution: {0:N0} MB" -f ($sz/1MB)) -Encoding UTF8
}

# 4) CBS-логи (Component Based Servicing) — только старые persist
Get-ChildItem 'C:\Windows\Logs\CBS' -Filter 'CbsPersist_*.log' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
    ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
Add-Content -Path $log "CBS: old persist logs cleaned" -Encoding UTF8

Add-Content -Path $log ("[{0}] === deep clean done ===" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
