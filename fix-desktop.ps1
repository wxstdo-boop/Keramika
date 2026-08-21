$ErrorActionPreference = "SilentlyContinue"

Write-Output "=== Stopping Explorer ==="
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Output "=== Starting Explorer ==="
Start-Process explorer.exe
Start-Sleep -Seconds 6

Write-Output "=== Explorer running ==="
Get-Process explorer -ErrorAction SilentlyContinue | Select-Object Id,ProcessName

Write-Output "=== HideIcons ==="
$val = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons
Write-Output "HideIcons=$val"

Write-Output "=== Desktop files ==="
Get-ChildItem ([Environment]::GetFolderPath("Desktop")) | Select-Object Name

Write-Output "=== NoDesktop policy ==="
$nd = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name NoDesktop -ErrorAction SilentlyContinue).NoDesktop
if ($null -ne $nd) { Write-Output "NoDesktop=$nd" } else { Write-Output "No NoDesktop policy" }
