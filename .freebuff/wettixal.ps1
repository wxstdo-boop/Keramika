Get-ChildItem C:/Wettixal -Force | ForEach-Object {
  if ($_.PSIsContainer) {
    $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  } else { $s = $_.Length }
  Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $_.Name)
} | Sort-Object -Descending
