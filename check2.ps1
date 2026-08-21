Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DC {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@;
$prog = [DC]::FindWindow("Progman", $null);
Write-Output "Progman=$prog vis=$([DC]::IsWindowVisible($prog))";
if ($prog -ne [IntPtr]::Zero) {
    $dv = [DC]::FindWindowEx($prog, [IntPtr]::Zero, "SHELLDLL_DefView", $null);
    Write-Output "DefView=$dv";
    if ($dv -ne [IntPtr]::Zero) {
        $lv = [DC]::FindWindowEx($dv, [IntPtr]::Zero, "SysListView32", "FolderView");
        Write-Output "ListView=$lv vis=$([DC]::IsWindowVisible($lv))";
    }
}
$worker = [DC]::FindWindow("WorkerW", $null);
Write-Output "WorkerW=$worker vis=$([DC]::IsWindowVisible($worker))";
