Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DC {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@;
$prog = [DC]::FindWindow("Progman", $null);
Write-Output "Progman=$prog vis=$([DC]::IsWindowVisible($prog))";
$w = [DC]::FindWindow("WorkerW", $null);
Write-Output "WorkerW=$w vis=$([DC]::IsWindowVisible($w))";
$dv = [DC]::FindWindowEx($w, [IntPtr]::Zero, "SHELLDLL_DefView", $null);
Write-Output "DefView=$dv";
$lv = [DC]::FindWindowEx($dv, [IntPtr]::Zero, "SysListView32", "FolderView");
Write-Output "ListView=$lv vis=$([DC]::IsWindowVisible($lv))";
Write-Output "HideIcons=$((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideIcons)";
