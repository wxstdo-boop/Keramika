$ErrorActionPreference = 'SilentlyContinue'
$sh = New-Object -ComObject WScript.Shell
$lnk = $sh.CreateShortcut('C:\Users\Грэйсик\Desktop\SCC.lnk')
Write-Host ('Target: ' + $lnk.TargetPath)
Write-Host ('Args: ' + $lnk.Arguments)
Write-Host ('WorkDir: ' + $lnk.WorkingDirectory)
Write-Host ('Icon: ' + $lnk.IconLocation)
if (Test-Path $lnk.TargetPath) {
  Write-Host ('TargetExists: yes, size ' + (Get-Item $lnk.TargetPath).Length + ' bytes')
} else {
  Write-Host 'TargetExists: NO'
}
