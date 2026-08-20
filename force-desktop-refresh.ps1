Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DesktopFix {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
    [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
}
"@;

# Try to send WM_COMMAND refresh to desktop
$desktop = [DesktopFix]::GetDesktopWindow();
Write-Output "DesktopWindow=$desktop vis=$([DesktopFix]::IsWindowVisible($desktop))";

# Send SC_SETREDRAW to force repaint
[DesktopFix]::SendMessage($desktop, 0x000B, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null;  # WM_SETREDRAW off
[DesktopFix]::SendMessage($desktop, 0x000B, [IntPtr]::One, [IntPtr]::Zero) | Out-Null;  # WM_SETREDRAW on
Write-Output "Sent WM_SETREDRAW toggle";

# SHChangeNotify SHCNE_ASSOCCHANGED to refresh shell
[DesktopFix]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero);  # SHCNE_ASSOCCHANGED
Write-Output "Sent SHChangeNotify";

Start-Sleep -Seconds 3;

$prog = [DesktopFix]::FindWindow("Progman", $null);
Write-Output "Progman after fix=$prog vis=$([DesktopFix]::IsWindowVisible($prog))";
$w = [DesktopFix]::FindWindow("WorkerW", $null);
Write-Output "WorkerW=$w vis=$([DesktopFix]::IsWindowVisible($w))";
$v = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons;
Write-Output "HideIcons=$v";
