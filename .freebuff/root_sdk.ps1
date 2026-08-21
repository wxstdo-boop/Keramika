$ErrorActionPreference = 'SilentlyContinue'
foreach ($p in @('C:\android-sdk', 'C:\android-ndk')) {
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File | Measure-Object -Property Length -Sum).Sum
    Write-Output ("{0,-16} {1,8:N0} MB" -f (Split-Path $p -Leaf), ($sz/1MB))
  }
}
