# ============================================================
# ShellPrompt.psm1 - Module Entry Point
# ============================================================

# Load configuration first
. "$PSScriptRoot\Private\Initialize-Config.ps1"

# 调试模式标志（影响 TUI 日志和性能监控行为）
$script:IsDebugMode = ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true" -or $env:DEBUG_TRACE -eq "1")

# Load private functions（所有文件均已点引用加载，TUI 文件始终定义以便函数可用）
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | Where-Object {
    $_.Name -notin @('Initialize-Config.ps1')
} | ForEach-Object {
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] 加载私有模块失败 $($_.Name): $($_.Exception.Message)"
    }
}

# Load public functions
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] 加载公共模块失败 $($_.Name): $($_.Exception.Message)"
    }
}

# User config override
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    try {
        . $userConfigPath
    } catch {
        Write-Host "[ShellPrompt] 用户配置加载失败: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# SSH Config 自动补全
$sshHosts = Get-SshConfigHosts
if ($sshHosts.Count -gt 0) {
    Register-ArgumentCompleter -CommandName 'Start-TmuxSession' -ParameterName 'HostName' -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        # 使用局部变量，避免污染全局作用域
        $hosts = Get-SshConfigHosts
        $hosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# 调试模式初始化
# TUI 文件已在上面被点引用加载，所以函数定义始终可用
# 以下仅在启用调试模式时激活 TUI 功能
if ($script:IsDebugMode) {
    try {
        Initialize-TUILogger | Out-Null
        Initialize-TUIPerformance | Out-Null
        Write-Host "[ShellPrompt] DEBUG 模式已激活" -ForegroundColor Cyan
    } catch {
        Write-Warning "[ShellPrompt] DEBUG 初始化失败: $($_.Exception.Message)"
    }
}

# 注意：别名（ll、which）在 Set-ProfileAliases.ps1 中统一管理
# 避免在 psm1 中重复注册导致冲突
