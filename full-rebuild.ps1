$ErrorActionPreference = "SilentlyContinue"

# Kill DSH first
Stop-Process -Name "DSH Desktop" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Kill Explorer completely
Stop-Process -Name explorer -Force
Start-Sleep -Seconds 4

# Make sure HideIcons=0
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideIcons -Value 0 -Force

# Start Explorer fresh
Start-Process explorer.exe
Start-Sleep -Seconds 8

# Check everything
$val = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons
Write-Output "HideIcons=$val"
Get-Process explorer | Select-Object Id,ProcessName | Format-Table
$f = [Environment]::GetFolderPath("Desktop")
$count = (Get-ChildItem $f).Count
Write-Output "DesktopFiles=$count"

# Check Progman
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DC {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@;
$prog = [DC]::FindWindow("Progman", $null);
Write-Output "Progman=$prog vis=$([DC]::IsWindowVisible($prog))";
