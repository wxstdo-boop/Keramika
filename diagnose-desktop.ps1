Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinFix {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumChildProc cb, IntPtr lp);
    public delegate bool EnumChildProc(IntPtr h, IntPtr lp);
}
"@;

# Check DesktopWindow 65548 class
$dw = [IntPtr]65548
$sb = New-Object System.Text.StringBuilder 256
[WinFix]::GetClassName($dw, $sb, 256) | Out-Null
Write-Output "DesktopWindow class=$($sb.ToString()) vis=$([WinFix]::IsWindowVisible($dw))"

# Get desktop PID
$dpid = 0
[WinFix]::GetWindowThreadProcessId($dw, [ref]$dpid) | Out-Null
Write-Output "DesktopWindow PID=$dpid"

# Find Shell_TrayWnd children (taskbar)
$tray = [WinFix]::FindWindow("Shell_TrayWnd", $null)
Write-Output "Shell_TrayWnd=$tray vis=$([WinFix]::IsWindowVisible($tray))"

# Check the Explorer process with empty title (should be desktop shell)
$deskExplorer = Get-Process explorer | Where-Object {$_.MainWindowTitle -eq ""}
if ($deskExplorer) {
    Write-Output "Desktop explorer PID=$($deskExplorer.Id) handle=$($deskExplorer.MainWindowHandle)"
    $hn = New-Object System.Text.StringBuilder 256
    [WinFix]::GetClassName($deskExplorer.MainWindowHandle, $hn, 256) | Out-Null
    Write-Output "  class=$($hn.ToString())"
}

# Try the HWND_BOTTOM approach - put Explorer's desktop window at the bottom of Z-order
# This is a common fix for missing desktop icons
$prog = [WinFix]::FindWindow("Progman", $null)
$worker = [WinFix]::FindWindow("WorkerW", $null)
Write-Output "Progman=$prog WorkerW=$worker"

# Try desktop via "Program Manager" title
$pm = [WinFix]::FindWindow($null, "Program Manager")
Write-Output "ProgramManager=$pm"
