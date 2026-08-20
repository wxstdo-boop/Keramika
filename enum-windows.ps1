Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WEnum {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@;

$procs = Get-Process | Where-Object {$_.MainWindowHandle -ne 0}
foreach ($p in $procs) {
    $h = $p.MainWindowHandle
    $vis = [WEnum]::IsWindowVisible($h)
    Write-Output "PID=$($p.Id) Proc=$($p.ProcessName) Handle=$h Title=$($p.MainWindowTitle) vis=$vis"
}

Write-Output "---"
Write-Output "Progman: $([WEnum]::FindWindow('Progman', $null))"
Write-Output "Shell_TrayWnd: $([WEnum]::FindWindow('Shell_TrayWnd', $null))"
$w = [WEnum]::FindWindow('WorkerW', $null)
Write-Output "WorkerW: $w vis=$([WEnum]::IsWindowVisible($w))"

# Try to find WorkerW children
$child = [WEnum]::FindWindowEx($w, [IntPtr]::Zero, $null, $null)
Write-Output "WorkerW first child: $child"
