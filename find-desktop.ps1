Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class EnumW {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
}
"@;

$desktop = [EnumW]::GetDesktopWindow();
Write-Output "DesktopWindow=$desktop";

# Enumerate all top-level windows
$found = @();
$callback = [EnumW+EnumWindowsProc]{
    param($h, $lp)
    $cn = New-Object System.Text.StringBuilder 256
    [EnumW]::GetClassName($h, $cn, 256) | Out-Null
    $tn = New-Object System.Text.StringBuilder 256
    [EnumW]::GetWindowText($h, $tn, 256) | Out-Null
    $vis = [EnumW]::IsWindowVisible($h)
    $name = $cn.ToString()
    if ($name -match "Progman|WorkerW|SHELLDLL|SysListView|Shell_TrayWnd|Shell_SecondaryTrayWnd|ExploreWClass") {
        Write-Output "  $h class=$name vis=$vis text=$($tn.ToString())"
    }
    return $true
};
[EnumW]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null

Write-Output "---"
Write-Output "HideIcons=$((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced').HideIcons)"
