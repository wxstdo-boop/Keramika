$ErrorActionPreference = 'SilentlyContinue'
$java = Get-Process java -ErrorAction SilentlyContinue
if ($java) {
  $java | Select-Object Id, @{N='CPU_s';E={[math]::Round($_.CPU)}}, @{N='WS_MB';E={[math]::Round($_.WorkingSet64/1MB)}} | Format-Table -AutoSize | Out-String | Write-Host
} else {
  Write-Host 'no java processes'
}
Write-Host '--- recent files in build (last 5 min) ---'
Get-ChildItem 'C:\Games\keramika\build' -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) } | Sort-Object LastWriteTime -Descending | Select-Object -First 8 LastWriteTime, Length, FullName | Format-Table -AutoSize | Out-String | Write-Host
Write-Host '--- recent downloads in .gradle (last 3 min) ---'
Get-ChildItem "$env:USERPROFILE\.gradle" -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-3) } | Sort-Object LastWriteTime -Descending | Select-Object -First 5 LastWriteTime, Length, FullName | Format-Table -AutoSize | Out-String | Write-Host
