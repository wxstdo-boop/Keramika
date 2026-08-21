Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;
public class WScan {
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lp);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    public delegate bool EnumWindowsProc(IntPtr h, IntPtr lp);
}
"@;

$explorerPids = (Get-Process explorer -ErrorAction SilentlyContinue).Id
$results = @()

$callback = [WScan+EnumWindowsProc]{
    param($h, $lp)
    $cn = New-Object System.Text.StringBuilder 256
    [WScan]::GetClassName($h, $cn, 256) | Out-Null
    $tn = New-Object System.Text.StringBuilder 256
    [WScan]::GetWindowText($h, $tn, 256) | Out-Null
    $vis = [WScan]::IsWindowVisible($h)
    $parent = [WScan]::GetParent($h)
    $pid = 0
    [WScan]::GetWindowThreadProcessId($h, [ref]$pid) | Out-Null
    $className = $cn.ToString()
    $title = $tn.ToString()
    
    if ($pid -in $script:explorerPids -and $vis) {
        Write-Output "EXP PID=$pid class=$className title=$title handle=$h parent=$parent vis=$vis"
    }
    return $true
}

[void][WScan]::EnumWindows($callback, [IntPtr]::Zero)
