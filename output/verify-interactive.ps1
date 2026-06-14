# 真实交互式验证：启动一个会真正执行 prompt() 的 pwsh 会话
# 比 bench-profile 强的地方：调用 prompt() 多次，模拟真实终端
$ErrorActionPreference = 'Stop'
$env:NO_COLOR = '1'

# 1. dot-source 整个 profile
. "$PSScriptRoot\..\ShellPrompt\Private\Initialize-Config.ps1"
. "$PSScriptRoot\..\ShellPrompt\Public\Initialize-Environment.ps1"
$script:ActualRoot = (Resolve-Path "$PSScriptRoot\..").Path
. "$script:ActualRoot\Microsoft.PowerShell_profile.ps1"

Write-Host "=== INTERACTIVE PROMPT VERIFY ===" -Fg Green

# 2. 调用 prompt 多次（每次都强制走完整链：DeferredInit + OriginalPrompt）
for ($i = 1; $i -le 3; $i++) {
    $r = prompt
    Write-Host "Call $i => type=$($r.GetType().Name) len=$($r.Length) value=[$r]"
}

# 3. 检查关键全局状态
Write-Host "DeferredInitDone: $script:DeferredInitDone"
Write-Host "OriginalPrompt type: $($script:OriginalPrompt.GetType().FullName)"

# 4. 检查 prompt 函数本身就是 global:
$cmd = Get-Command prompt -CommandType Function
Write-Host "prompt command scope: $($cmd.CommandType) module=$($cmd.Module) name=$($cmd.Name)"

Write-Host "=== DONE ===" -Fg Green
