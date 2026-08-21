$ErrorActionPreference = 'SilentlyContinue'
Get-ChildItem 'C:\Windows\Logs' -Recurse -File | Where-Object { $_.Length -gt 10MB } | Sort-Object Length -Descending | Select-Object -First 12 | ForEach-Object {
  Write-Output ("{0,-50} {1,8:N0} MB" -f $_.FullName, ($_.Length/1MB))
}
