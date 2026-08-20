$ErrorActionPreference = "Stop"
$f = "C:\ProgramData\Windhawk\userprofile.json"
$json = Get-Content $f -Raw
$j = $json | ConvertFrom-Json
$j.mods."icon-resource-redirect" | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force -ErrorAction SilentlyContinue
# Remove the property and re-add as True
$j.mods."icon-resource-redirect".enabled = $true
$utf8noBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($f, ($j | ConvertTo-Json -Depth 10), $utf8noBom)
Write-Output "icon-resource-redirect re-enabled"

# Make sure HideIcons=0 (the mod will manage icons its own way)
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name HideIcons -Value 0 -Force
Write-Output "HideIcons=0"

# Restart only Windhawk service, not Explorer
Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Start-Service -Name Windhawk -ErrorAction SilentlyContinue
Write-Output "Windhawk service restarted"
