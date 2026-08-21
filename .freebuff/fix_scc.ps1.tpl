$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'SCC.lnk'
$ps1Path = Join-Path $desktop 'SCC.ps1'
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut($lnkPath)
$lnk.TargetPath = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $ps1Path + '"'
$lnk.WorkingDirectory = $desktop
$lnk.Description = 'Super Cache Cleaner'
$lnk.Save()
Write-Host ('Shortcut saved: ' + $lnkPath)
Write-Host ('Script exists: ' + (Test-Path $ps1Path))
