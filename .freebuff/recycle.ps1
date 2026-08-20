$sh = New-Object -ComObject Shell.Application
$rb = $sh.Namespace(0xA)
$total = 0
$count = 0
foreach ($item in $rb.Items()) {
  $s = $item.Size
  if ($s -gt 0) { $total += $s; $count++ }
}
Write-Output ("RecycleBin items={0} size={1:N0} MB" -f $count, ($total/1MB))
