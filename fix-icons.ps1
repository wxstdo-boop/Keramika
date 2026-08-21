$ErrorActionPreference = "Stop"
$f = "C:\ProgramData\Windhawk\userprofile.json"
$json = Get-Content $f -Raw
$j = $json | ConvertFrom-Json
$j.mods."icon-resource-redirect" | Add-Member -NotePropertyName "enabled" -NotePropertyValue $false -Force
$utf8noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 10), $utf8noBom)
Write-Output "1. icon-resource-redirect disabled"

# Reset HideIcons
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideIcons -Value 0 -Force
Write-Output "2. HideIcons=0"

# Restart Windhawk service
Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name Windhawk -ErrorAction SilentlyContinue
Write-Output "3. Windhawk service restarted"

# Refresh shell
ie4uinit.exe -show
Write-Output "4. Shell refreshed"
Start-Sleep -Seconds 3
$v = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons
Write-Output "Final HideIcons=$v"
