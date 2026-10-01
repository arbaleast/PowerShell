# ShellPrompt.psm1 - Module Entry Point

# Load configuration first; $script:ShellPromptRoot 守束避免重复 dot-source
if (-not (Get-Variable -Name 'ShellPromptRoot' -Scope Script -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Private\Initialize-Config.ps1"
}

# Load all module scripts
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1", "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
    if ($_.Name -eq 'Initialize-Config.ps1') { return }
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] Failed to load $($_.Name): $($_.Exception.Message)"
    }
}

# User config override
$userConfigPath = Join-Path $HOME ".ShellPrompt\config.ps1"
if (Test-Path $userConfigPath) {
    try {
        . $userConfigPath
    } catch {
        Write-Host "[ShellPrompt] User config failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# SSH Config auto-completion
$sshHosts = Get-SshConfigHosts
if ($sshHosts.Count -gt 0) {
    Register-ArgumentCompleter -CommandName 'Start-TmuxSession' -ParameterName 'HostName' -ScriptBlock {
        # $commandAst / $cursorPosition 由 PowerShell 补全基础架构提供，
        # 用于在多 token 命令行中精确定位当前补全位置。
        param($wordToComplete, $commandAst, $cursorPosition)
        $hosts = Get-SshConfigHosts
        $hosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
        # 静默引用 AST 与位置参数，避免 PSReviewUnusedParameter 误报（运行时由 PowerShell 注入）。
        $null = $commandAst, $cursorPosition
    }
}

# 导出声明已完全通过 .psd1 的 FunctionsToExport 控制,
# 因此不再需要 .psm1 内的 Export-ModuleMember。
