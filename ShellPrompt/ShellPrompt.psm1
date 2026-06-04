# ============================================================
# ShellPrompt.psm1 - Module Entry Point
# ============================================================

# Load configuration first
if (-not (Get-Variable -Name 'UserScoop_CONF' -Scope Global -ErrorAction SilentlyContinue)) {
    . "$PSScriptRoot\Private\Initialize-Config.ps1"
}

# Debug mode flag
$script:IsDebugMode = ($env:DEBUG -eq "1" -or $env:DEBUG -eq "true" -or $env:DEBUG_TRACE -eq "1")

# Load private functions
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" | Where-Object {
    $_.Name -notin @('Initialize-Config.ps1')
} | ForEach-Object {
    try {
        . $_.FullName
    } catch {
        Write-Warning "[ShellPrompt] Failed to load $($_.Name): $($_.Exception.Message)"
    }
}

# Load public functions
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" | ForEach-Object {
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
        param($wordToComplete, $commandAst, $cursorPosition)
        $hosts = Get-SshConfigHosts
        $hosts | Where-Object { $_ -like "*$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}

# Debug mode initialization
if ($script:IsDebugMode) {
    try {
        Initialize-TUILogger | Out-Null
        Initialize-TUIPerformance | Out-Null
        Write-Host "[ShellPrompt] DEBUG mode activated" -ForegroundColor Cyan
    } catch {
        Write-Warning "[ShellPrompt] DEBUG init failed: $($_.Exception.Message)"
    }
}