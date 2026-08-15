$dirs = @(
  'C:/Program Files',
  'C:/Program Files (x86)',
  'C:/ProgramData',
  'C:/Windows',
  'C:/Users/Грэйсик/AppData/Local',
  'C:/Users/Грэйсик/AppData/Roaming',
  'C:/Users/Грэйсик/Downloads',
  'C:/Users/Грэйсик/Documents',
  'C:/Users/Грэйсик/Desktop',
  'C:/flutter',
  'C:/Disfigured',
  'C:/Wettixal',
  'C:/Games',
  'C:/jdk21',
  'C:/tools'
)
foreach ($d in $dirs) {
  if (Test-Path $d) {
    $s = (Get-ChildItem $d -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    Write-Output ("{0,8:N1} GB  {1}" -f ($s/1GB), $d)
  }
}
$page = (Get-Item C:/pagefile.sys -ErrorAction SilentlyContinue).Length
$hiber = (Get-Item C:/hiberfil.sys -ErrorAction SilentlyContinue).Length
if ($page) { Write-Output ("{0,8:N1} GB  pagefile.sys" -f ($page/1GB)) }
if ($hiber) { Write-Output ("{0,8:N1} GB  hiberfil.sys" -f ($hiber/1GB)) }
Write-Output "---- root files ----"
Get-ChildItem C:/ -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 10 | ForEach-Object { Write-Output ("{0,8:N1} GB  {1}" -f ($_.Length/1GB), $_.Name) }
