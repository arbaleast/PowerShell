# ============================================================
# ShellPrompt.psm1 - 模块入口
# ============================================================

# 1. 加载配置（最先加载，用户配置可能覆盖默认值）
. "$PSScriptRoot\Private\Initialize-Config.ps1"

# 2. 加载所有私有函数（排除配置和按需加载的模块）
# 优化：使用通配符一次性加载，避免逐个文件检查和循环开销
# 注意：TUILogger.ps1 和 TUIPerformanceState.ps1 在首次访问时才加载
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -Filter '*.ps1' -ErrorAction SilentlyContinue | Where-Object { 
    $_.Name -ne 'Initialize-Config.ps1' -and
    $_.Name -ne 'TUILogger.ps1' -and
    $_.Name -ne 'TUIPerformanceState.ps1'
} | ForEach-Object {
    . $_.FullName
}

# 3. 加载所有公有函数
# 优化：使用通配符一次性加载，避免数组定义和循环开销
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# 4. 用户配置覆盖（延迟加载）
# 用户可以在 ~/.ShellPrompt/config.ps1 中覆盖默认配置
# 此文件在模块加载后执行，允许用户自定义所有配置项
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    try {
        . $userConfigPath
        if ($Global:TUI_Logger) {
            $Global:TUI_Logger.Info("用户配置已加载", @{ Path = $userConfigPath })
        }
    } catch {
        Write-Host "[ShellPrompt] 用户配置加载失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# 5. 注册 SSH Config 别名到 PowerShell 命令补全
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

# 6. 别名
Set-Alias ll Get-ChildItem -ErrorAction SilentlyContinue
Set-Alias which where.exe -ErrorAction SilentlyContinue

# 7. 显式导出所有公有函数
$publicFunctions = @(
    'Initialize-Environment'
    'Start-TmuxSession'
    'reload'
    # 日志和性能监控（延迟加载，按需初始化）
    'Initialize-TUILogger'
    'Initialize-TUIPerformance'
    'Get-TUIPerformance'
    'Show-TUIDebugOverlay'
    'Test-TUIDebugMode'
    # 多终端复用器支持
    'Get-MultiplexerSessions'
    'Test-MultiplexerAvailable'
)

Export-ModuleMember -Function $publicFunctions

# 8. 延迟加载：日志和性能监控根据 DEBUG 环境变量初始化
# 改为按需加载，不在模块加载时立即初始化
if ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true" -or $env:DEBUG_TRACE -eq "1") {
    # 立即初始化调试模式所需的功能
    Initialize-TUILogger | Out-Null
    Initialize-TUIPerformance | Out-Null
}
