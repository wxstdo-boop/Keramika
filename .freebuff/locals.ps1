Get-ChildItem "$env:USERPROFILE/AppData/Local" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($s -gt 150MB) { Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $_.Name) }
} | Sort-Object -Descending
Write-Output "---- Roaming ----"
Get-ChildItem "$env:USERPROFILE/AppData/Roaming" -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($s -gt 150MB) { Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $_.Name) }
} | Sort-Object -Descending
