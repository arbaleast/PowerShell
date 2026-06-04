# 性能基准测试 - 输出到 stdout 和文件
$results = @{}
$outFile = "$PSScriptRoot\results.txt"

# 测试 starship
$s = [System.Diagnostics.Stopwatch]::StartNew()
if (Get-Command starship -ErrorAction SilentlyContinue) {
    $null = starship init powershell 2>$null
}
$s.Stop()
$results['starship'] = $s.ElapsedMilliseconds

# 测试 fnm
$f = [System.Diagnostics.Stopwatch]::StartNew()
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    $null = fnm env --use-on-cd --shell powershell 2>$null
}
$f.Stop()
$results['fnm'] = $f.ElapsedMilliseconds

# 测试 PSReadLine
$p = [System.Diagnostics.Stopwatch]::StartNew()
Import-Module PSReadLine -ErrorAction SilentlyContinue
$p.Stop()
$results['PSReadLine'] = $p.ElapsedMilliseconds

# 输出结果
"starship=$($results['starship'])" | Tee-Object -FilePath $outFile
"fnm=$($results['fnm'])" | Tee-Object -Append -FilePath $outFile
"PSReadLine=$($results['PSReadLine'])" | Tee-Object -Append -FilePath $outFile
"Total=$($results.Values | Measure-Object -Sum).Sum" | Tee-Object -Append -FilePath $outFile

Write-Host "=== BENCHMARK RESULTS ===" -ForegroundColor Green
Get-Content $outFile
