$ErrorActionPreference = 'SilentlyContinue'
$targets = @(
  "$env:USERPROFILE\.gradle",
  "$env:USERPROFILE\AppData\Local\Pub",
  "$env:USERPROFILE\AppData\Local\Android",
  "$env:USERPROFILE\AppData\Local\Flutter",
  "C:\Games"
)
foreach ($t in $targets) {
  if (Test-Path $t) {
    $dirs = Get-ChildItem $t -Directory
    foreach ($d in $dirs) {
      $sz = (Get-ChildItem $d.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
      $mb = if ($sz) { [math]::Round($sz/1MB, 1) } else { 0 }
      Write-Output ("{0,-45} {1,10:N1} MB" -f $d.FullName, $mb)
    }
  }
}
