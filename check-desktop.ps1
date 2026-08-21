Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DeskCheck {
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cn, string wn);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr ch, string cn, string wn);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@;

$prog = [DeskCheck]::FindWindow("Progman", $null);
$hidden = [DeskCheck]::FindWindow("#32769", $null);
$worker = [DeskCheck]::FindWindow("WorkerW", $null);

Write-Output "Progman=$prog visible=$([DeskCheck]::IsWindowVisible($prog))";
Write-Output "DeskHidden=$hidden visible=$([DeskCheck]::IsWindowVisible($hidden))";
Write-Output "WorkerW=$worker visible=$([DeskCheck]::IsWindowVisible($worker))";

# Find SHELLDLL_DefView in any parent
foreach ($p in @($prog, $hidden, $worker)) {
    if ($p -ne [IntPtr]::Zero) {
        $dv = [DeskCheck]::FindWindowEx($p, [IntPtr]::Zero, "SHELLDLL_DefView", $null);
        if ($dv -ne [IntPtr]::Zero) {
            $lv = [DeskCheck]::FindWindowEx($dv, [IntPtr]::Zero, "SysListView32", "FolderView");
            Write-Output "DefView=$dv under parent=$p";
            Write-Output "ListView=$lv visible=$([DeskCheck]::IsWindowVisible($lv))";
            # Force show everything
            [DeskCheck]::ShowWindow($p, 9) | Out-Null;
            [DeskCheck]::ShowWindow($dv, 9) | Out-Null;
            [DeskCheck]::ShowWindow($lv, 9) | Out-Null;
            Write-Output "Applied ShowWindow(9) SW_RESTORE to all";
            break;
        }
    }
}

$v = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced").HideIcons;
Write-Output "HideIcons=$v";

$f = [Environment]::GetFolderPath("Desktop");
$count = (Get-ChildItem $f).Count;
Write-Output "DesktopFiles=$count";
