$dirs = @(
  "$env:USERPROFILE/AppData/Local",
  "$env:USERPROFILE/AppData/Roaming",
  "$env:USERPROFILE/AppData/Local/Temp",
  "$env:USERPROFILE/Downloads",
  "$env:USERPROFILE/.gradle",
  "$env:USERPROFILE/.pub-cache",
  "$env:USERPROFILE/.cache",
  "$env:USERPROFILE/.config",
  "$env:USERPROFILE/.local",
  "$env:USERPROFILE/.android"
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    $s = (Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $d)
  }
}
Write-Output "---- ProgramData top ----"
Get-ChildItem C:/ProgramData -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($s -gt 100MB) { Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $_.Name) }
}
Write-Output "---- Program Files (x86) top ----"
Get-ChildItem "C:/Program Files (x86)" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
  $s = (Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
  if ($s -gt 100MB) { Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $_.Name) }
}
