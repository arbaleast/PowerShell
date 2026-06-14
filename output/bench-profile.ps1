$ErrorActionPreference = 'Stop'

# 模拟 profile 加载：dot-source profile 的 Stage 1 部分（只测我们关心的瓶颈点）
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Stage 1
. "$PSScriptRoot\..\ShellPrompt\Private\Initialize-Config.ps1"
$t1 = $sw.ElapsedMilliseconds

. "$PSScriptRoot\..\ShellPrompt\Public\Initialize-Environment.ps1"
$t2 = $sw.ElapsedMilliseconds

# 模拟 Show-UserScoopLogo 调用 3 次（与实际 profile 行为一致）
& (Get-Item Function:Show-UserScoopLogo) 2>$null
& (Get-Item Function:Show-UserScoopLogo) 2>$null
& (Get-Item Function:Show-UserScoopLogo) 2>$null
$t3 = $sw.ElapsedMilliseconds

Write-Host "Initialize-Config: $t1 ms"
Write-Host "+ Initialize-Environment: $t2 ms"
Write-Host "+ 3x Show-UserScoopLogo: $t3 ms"
Write-Host "Total: $t3 ms (single cold start)"
