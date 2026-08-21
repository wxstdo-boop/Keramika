$ErrorActionPreference = "SilentlyContinue"

# Kill Explorer
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 3

# Ensure HideIcons stays 0 BEFORE starting Explorer
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideIcons -Value 0 -Force

# Start Explorer
Start-Process explorer.exe
Start-Sleep -Seconds 6

# Check result
$val = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons
Write-Output "HideIcons=$val"
Get-Process explorer | Select-Object Id,ProcessName
Get-ChildItem ([Environment]::GetFolderPath("Desktop")) | Select-Object Name
