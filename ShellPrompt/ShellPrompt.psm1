# ============================================================
# ShellPrompt.psm1 — 模块入口
# ============================================================

# 1. 加载配置
. "$PSScriptRoot\Private\Initialize-Config.ps1"

# 2. 加载所有私有函数（排除配置）
# 优化：使用通配符一次性加载，避免逐个文件检查和循环开销
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -Filter '*.ps1' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'Initialize-Config.ps1' } | ForEach-Object {
    . $_.FullName
}

# 3. 加载所有公有函数
# 优化：使用通配符一次性加载，避免数组定义和循环开销
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# 4. 注册 SSH Config 别名到 PowerShell 命令补全
$sshHosts = Get-SshConfigHosts
if ($sshHosts.Count -gt 0) {
    Register-ArgumentCompleter -CommandName 'Start-TmuxSession' -ParameterName 'HostName' -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $global:sshConfigHosts = Get-SshConfigHosts
        $global:sshConfigHosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# 4. 别名
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# 5. 显式导出所有公有函数
$publicFunctions = @(
    'Initialize-Environment'
    'Start-TmuxSession'
    'reload'
    # 日志和性能监控
    'Initialize-TUILogger'
    'Initialize-TUIPerformance'
    'Get-TUIPerformance'
    'Show-TUIDebugOverlay'
    'Test-TUIDebugMode'
)

Export-ModuleMember -Function $publicFunctions

# 6. 初始化日志和性能监控（根据 DEBUG 环境变量）
if ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true" -or $env:DEBUG_TRACE -eq "1") {
    Initialize-TUILogger | Out-Null
    Initialize-TUIPerformance | Out-Null
}
